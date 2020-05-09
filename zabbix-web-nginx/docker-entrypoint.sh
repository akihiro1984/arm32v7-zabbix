#!/bin/bash

set -eo pipefail

set +e

# Script trace mode
if [ "${DEBUG_MODE}" == "true" ]; then
    set -o xtrace
fi

# Type of Zabbix component
# Possible values: [server, proxy, agent, frontend, java-gateway, appliance]
zbx_type=${ZBX_TYPE}
# Type of Zabbix database
# Possible values: [mysql, postgresql]
zbx_db_type=${ZBX_DB_TYPE}
# Type of web-server. Valid only with zbx_type = frontend
# Possible values: [apache, nginx]
zbx_opt_type=${ZBX_OPT_TYPE}

# Default Zabbix installation name
# Used only by Zabbix web-interface
ZBX_SERVER_NAME=${ZBX_SERVER_NAME:-"Zabbix docker"}
# Default Zabbix server host
ZBX_SERVER_HOST=${ZBX_SERVER_HOST:-"zabbix-server"}
# Default Zabbix server port number
ZBX_SERVER_PORT=${ZBX_SERVER_PORT:-"10051"}

# Default timezone for web interface
PHP_TZ=${PHP_TZ:-"Europe/Riga"}

#Enable PostgreSQL timescaleDB feature:
ENABLE_TIMESCALEDB=${ENABLE_TIMESCALEDB:-"false"}

# Default directories
# User 'zabbix' home directory
ZABBIX_USER_HOME_DIR="/var/lib/zabbix"
# Configuration files directory
ZABBIX_ETC_DIR="/etc/zabbix"
# Web interface www-root directory
ZBX_FRONTEND_PATH="/usr/share/zabbix"

escape_spec_char() {
    local var_value=$1

    var_value="${var_value//\\/\\\\}"
    var_value="${var_value//[$'\n']/}"
    var_value="${var_value//\//\\/}"
    var_value="${var_value//./\\.}"
    var_value="${var_value//\*/\\*}"
    var_value="${var_value//^/\\^}"
    var_value="${var_value//\$/\\\$}"
    var_value="${var_value//\&/\\\&}"
    var_value="${var_value//\[/\\[}"
    var_value="${var_value//\]/\\]}"

    echo $var_value
}

update_php_var() {
    local config_path=$1
    local var_name=$2
    local var_value=$3

    if [ ! -f "$config_path" ]; then
        echo "**** Configuration file '$config_path' does not exist"
        return
    fi

    echo -n "** Updating '$config_path' parameter \"$var_name\": '$var_value'... "

}

update_config_var() {
    local config_path=$1
    local var_name=$2
    local var_value=$3
    local is_multiple=$4

    if [ ! -f "$config_path" ]; then
        echo "**** Configuration file '$config_path' does not exist"
        return
    fi

    echo -n "** Updating '$config_path' parameter \"$var_name\": '$var_value'... "

    # Remove configuration parameter definition in case of unset parameter value
    if [ -z "$var_value" ]; then
        sed -i -e "/^$var_name=/d" "$config_path"
        echo "removed"
        return
    fi

    # Remove value from configuration parameter in case of double quoted parameter value
    if [ "$var_value" == '""' ]; then
        sed -i -e "/^$var_name=/s/=.*/=/" "$config_path"
        echo "undefined"
        return
    fi

    # Use full path to a file for TLS related configuration parameters
    if [[ $var_name =~ ^TLS.*File$ ]]; then
        var_value=$ZABBIX_USER_HOME_DIR/enc/$var_value
    fi

    # Escaping characters in parameter value
    var_value=$(escape_spec_char "$var_value")

    if [ "$(grep -E "^$var_name=" $config_path)" ] && [ "$is_multiple" != "true" ]; then
        sed -i -e "/^$var_name=/s/=.*/=$var_value/" "$config_path"
        echo "updated"
    elif [ "$(grep -Ec "^# $var_name=" $config_path)" -gt 1 ]; then
        sed -i -e  "/^[#;] $var_name=$/i\\$var_name=$var_value" "$config_path"
        echo "added first occurrence"
    else
        sed -i -e "/^[#;] $var_name=/s/.*/&\n$var_name=$var_value/" "$config_path"
        echo "added"
    fi

}

update_config_multiple_var() {
    local config_path=$1
    local var_name=$2
    local var_value=$3

    var_value="${var_value%\"}"
    var_value="${var_value#\"}"

    local IFS=,
    local OPT_LIST=($var_value)

    for value in "${OPT_LIST[@]}"; do
        update_config_var $config_path $var_name $value true
    done
}

# Check prerequisites for MySQL database
check_variables_mysql() {
    local type=$1

    DB_SERVER_HOST=${DB_SERVER_HOST:-"mysql-server"}
    DB_SERVER_PORT=${DB_SERVER_PORT:-"3306"}
    USE_DB_ROOT_USER=false
    CREATE_ZBX_DB_USER=false

    if [ ! -n "${MYSQL_USER}" ] && [ "${MYSQL_RANDOM_ROOT_PASSWORD}" == "true" ]; then
        echo "**** Impossible to use MySQL server because of unknown Zabbix user and random 'root' password"
        exit 1
    fi

    if [ ! -n "${MYSQL_USER}" ] && [ ! -n "${MYSQL_ROOT_PASSWORD}" ] && [ "${MYSQL_ALLOW_EMPTY_PASSWORD}" != "true" ]; then
        echo "*** Impossible to use MySQL server because 'root' password is not defined and it is not empty"
        exit 1
    fi

    if [ "${MYSQL_ALLOW_EMPTY_PASSWORD}" == "true" ] || [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
        USE_DB_ROOT_USER=true
        DB_SERVER_ROOT_USER="root"
        DB_SERVER_ROOT_PASS=${MYSQL_ROOT_PASSWORD:-""}
    fi

    [ -n "${MYSQL_USER}" ] && CREATE_ZBX_DB_USER=true

    # If root password is not specified use provided credentials
    DB_SERVER_ROOT_USER=${DB_SERVER_ROOT_USER:-${MYSQL_USER}}
    [ "${MYSQL_ALLOW_EMPTY_PASSWORD}" == "true" ] || DB_SERVER_ROOT_PASS=${DB_SERVER_ROOT_PASS:-${MYSQL_PASSWORD}}
    DB_SERVER_ZBX_USER=${MYSQL_USER:-"zabbix"}
    DB_SERVER_ZBX_PASS=${MYSQL_PASSWORD:-"zabbix"}

    if [ "$type" == "proxy" ]; then
        DB_SERVER_DBNAME=${MYSQL_DATABASE:-"zabbix_proxy"}
    else
        DB_SERVER_DBNAME=${MYSQL_DATABASE:-"zabbix"}
    fi
}

check_db_connect_mysql() {
    echo "********************"
    echo "* DB_SERVER_HOST: ${DB_SERVER_HOST}"
    echo "* DB_SERVER_PORT: ${DB_SERVER_PORT}"
    echo "* DB_SERVER_DBNAME: ${DB_SERVER_DBNAME}"
    if [ "${USE_DB_ROOT_USER}" == "true" ]; then
        echo "* DB_SERVER_ROOT_USER: ${DB_SERVER_ROOT_USER}"
        echo "* DB_SERVER_ROOT_PASS: ${DB_SERVER_ROOT_PASS}"
    fi
    echo "* DB_SERVER_ZBX_USER: ${DB_SERVER_ZBX_USER}"
    echo "* DB_SERVER_ZBX_PASS: ${DB_SERVER_ZBX_PASS}"
    echo "********************"

    WAIT_TIMEOUT=5

    while [ ! "$(mysqladmin ping -h ${DB_SERVER_HOST} -P ${DB_SERVER_PORT} -u ${DB_SERVER_ROOT_USER} \
                --password="${DB_SERVER_ROOT_PASS}" --silent --connect_timeout=10)" ]; do
        echo "**** MySQL server is not available. Waiting $WAIT_TIMEOUT seconds..."
        sleep $WAIT_TIMEOUT
    done
}

prepare_web_server_nginx() {
    NGINX_CONFD_DIR="/etc/nginx/conf.d"
    NGINX_SSL_CONFIG="/etc/ssl/nginx"
    PHP_SESSIONS_DIR="/var/lib/php5"

    echo "** Disable default vhosts"
    rm -f $NGINX_CONFD_DIR/*.conf

    echo "** Adding Zabbix virtual host (HTTP)"
    if [ -f "$ZABBIX_ETC_DIR/nginx.conf" ]; then
        ln -s "$ZABBIX_ETC_DIR/nginx.conf" "$NGINX_CONFD_DIR"
    else
        echo "**** Impossible to enable HTTP virtual host"
    fi

    if [ -f "$NGINX_SSL_CONFIG/ssl.crt" ] && [ -f "$NGINX_SSL_CONFIG/ssl.key" ] && [ -f "$NGINX_SSL_CONFIG/dhparam.pem" ]; then
        echo "** Enable SSL support for Nginx"
        if [ -f "$ZABBIX_ETC_DIR/nginx_ssl.conf" ]; then
            ln -s "$ZABBIX_ETC_DIR/nginx_ssl.conf" "$NGINX_CONFD_DIR"
        else
            echo "**** Impossible to enable HTTPS virtual host"
        fi
    else
        echo "**** Impossible to enable SSL support for Nginx. Certificates are missed."
    fi

    if [ -d "/var/log/nginx/" ]; then
        ln -sf /dev/fd/2 /var/log/nginx/error.log
    fi

    ln -sf /dev/fd/2 /var/log/php5-fpm.log
    ln -sf /dev/fd/2 /var/log/php7.2-fpm.log
}

prepare_zbx_web_config() {
    local db_type=$1
    local server_name=""

    echo "** Preparing Zabbix frontend configuration file"

    ZBX_WWW_ROOT="/usr/share/zabbix"
    ZBX_WEB_CONFIG="$ZABBIX_ETC_DIR/web/zabbix.conf.php"

    if [ -f "$ZBX_WWW_ROOT/conf/zabbix.conf.php" ]; then
        rm -f "$ZBX_WWW_ROOT/conf/zabbix.conf.php"
    fi

    ln -s "$ZBX_WEB_CONFIG" "$ZBX_WWW_ROOT/conf/zabbix.conf.php"

    # Different places of PHP configuration file
    if [ -f "/etc/php5/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php5/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php5/fpm/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php5/fpm/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php5/apache2/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php5/apache2/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php/7.0/apache2/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php/7.0/apache2/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php/7.0/fpm/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php/7.0/fpm/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php.d/99-zabbix.ini"
    elif [ -f "/etc/php7/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php7/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php/7.2/fpm/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php/7.2/fpm/conf.d/99-zabbix.ini"
    elif [ -f "/etc/php/7.2/apache2/conf.d/99-zabbix.ini" ]; then
        PHP_CONFIG_FILE="/etc/php/7.2/apache2/conf.d/99-zabbix.ini"
    fi

    if [ -n "$PHP_CONFIG_FILE" ]; then
        update_config_var "$PHP_CONFIG_FILE" "max_execution_time" "${ZBX_MAXEXECUTIONTIME:-"600"}"
        update_config_var "$PHP_CONFIG_FILE" "memory_limit" "${ZBX_MEMORYLIMIT:-"128M"}" 
        update_config_var "$PHP_CONFIG_FILE" "post_max_size" "${ZBX_POSTMAXSIZE:-"16M"}"
        update_config_var "$PHP_CONFIG_FILE" "upload_max_filesize" "${ZBX_UPLOADMAXFILESIZE:-"2M"}"
        update_config_var "$PHP_CONFIG_FILE" "max_input_time" "${ZBX_MAXINPUTTIME:-"300"}"
        update_config_var "$PHP_CONFIG_FILE" "date.timezone" "${PHP_TZ}"
    else
        echo "**** Zabbix related PHP configuration file not found"
    fi

    ZBX_HISTORYSTORAGETYPES=${ZBX_HISTORYSTORAGETYPES:-"[]"}

    # Escaping characters in parameter value
    server_name=$(escape_spec_char "${ZBX_SERVER_NAME}")
    server_user=$(escape_spec_char "${DB_SERVER_ZBX_USER}")
    server_pass=$(escape_spec_char "${DB_SERVER_ZBX_PASS}")
    history_storage_url=$(escape_spec_char "${ZBX_HISTORYSTORAGEURL}")
    history_storage_types=$(escape_spec_char "${ZBX_HISTORYSTORAGETYPES}")

    sed -i \
        -e "s/{DB_SERVER_HOST}/${DB_SERVER_HOST}/g" \
        -e "s/{DB_SERVER_PORT}/${DB_SERVER_PORT}/g" \
        -e "s/{DB_SERVER_DBNAME}/${DB_SERVER_DBNAME}/g" \
        -e "s/{DB_SERVER_SCHEMA}/${DB_SERVER_SCHEMA}/g" \
        -e "s/{DB_SERVER_USER}/$server_user/g" \
        -e "s/{DB_SERVER_PASS}/$server_pass/g" \
        -e "s/{ZBX_SERVER_HOST}/${ZBX_SERVER_HOST}/g" \
        -e "s/{ZBX_SERVER_PORT}/${ZBX_SERVER_PORT}/g" \
        -e "s/{ZBX_SERVER_NAME}/$server_name/g" \
        -e "s/{ZBX_HISTORYSTORAGEURL}/$history_storage_url/g" \
        -e "s/{ZBX_HISTORYSTORAGETYPES}/$history_storage_types/g" \
    "$ZBX_WEB_CONFIG"

    [ "$db_type" = "postgresql" ] && sed -i "s/MYSQL/POSTGRESQL/g" "$ZBX_WEB_CONFIG"

    [ -n "${ZBX_SESSION_NAME}" ] && sed -i "/ZBX_SESSION_NAME/s/'[^']*'/'${ZBX_SESSION_NAME}'/2" "$ZBX_WWW_ROOT/include/defines.inc.php"
    [ -n "${ZBX_GRAPH_FONT_NAME}" ] && sed -i "/ZBX_GRAPH_FONT_NAME/s/'[^']*'/'${ZBX_GRAPH_FONT_NAME}'/2" "$ZBX_WWW_ROOT/include/defines.inc.php"
}

prepare_web() {
    local web_server=$1
    local db_type=$2

    echo "** Preparing Zabbix web-interface"

    check_variables_$db_type
    check_db_connect_$db_type
    prepare_web_server_$web_server
    prepare_zbx_web_config $db_type
}

#################################################

if [ ! -n "$zbx_type" ]; then
    echo "**** Type of Zabbix component is not specified"
    exit 1
elif [ "$zbx_type" == "dev" ]; then
    echo "** Deploying Zabbix installation from SVN"
else
    if [ ! -n "$zbx_db_type" ]; then
        echo "**** Database type of Zabbix $zbx_type is not specified"
        exit 1
    fi

    if [ "$zbx_db_type" != "none" ]; then
        if [ "$zbx_opt_type" != "none" ]; then
            echo "** Deploying Zabbix $zbx_type ($zbx_opt_type) with $zbx_db_type database"
        else
            echo "** Deploying Zabbix $zbx_type with $zbx_db_type database"
        fi
    else
        echo "** Deploying Zabbix $zbx_type"
    fi
fi

prepare_web $zbx_opt_type $zbx_db_type

echo "########################################################"

if [ "$1" != "" ]; then
    echo "** Executing '$@'"
    exec "$@"
elif [ -f "/usr/bin/supervisord" ]; then
    echo "** Executing supervisord"
    exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
else
    echo "Unknown instructions. Exiting..."
    exit 1
fi

#################################################
