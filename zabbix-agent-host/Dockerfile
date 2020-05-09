FROM arm32v7/alpine as builder

ARG APK_FLAGS_COMMON=""
ARG APK_FLAGS_DEV="${APK_FLAGS_COMMON} --no-cache"

ARG MAJOR_VERSION=4.2
ARG ZBX_VERSION=${MAJOR_VERSION}.4
ARG ZBX_SOURCES=https://git.zabbix.com/scm/zbx/zabbix.git
ENV TERM=xterm ZBX_VERSION=${ZBX_VERSION} ZBX_SOURCES=${ZBX_SOURCES} \
    ZBX_TYPE=agent

RUN set -eux && \
    apk update && \
    apk add ${APK_FLAGS_DEV} --virtual build-dependencies \
            alpine-sdk \
            autoconf \
            automake \
            openssl-dev \
            openldap-dev \
            pcre-dev \
            git \
            coreutils && \
    cd /tmp/ && \
    git clone ${ZBX_SOURCES} --branch ${ZBX_VERSION} --depth 1 --single-branch zabbix-${ZBX_VERSION} && \
    cd /tmp/zabbix-${ZBX_VERSION} && \
    zabbix_revision=`git rev-parse --short HEAD` && \
    sed -i "s/{ZABBIX_REVISION}/$zabbix_revision/g" include/version.h && \
    ./bootstrap.sh && \
    export CFLAGS="-fPIC -pie -Wl,-z,relro -Wl,-z,now" && \
    ./configure \
            --datadir=/usr/lib \
            --libdir=/usr/lib/zabbix \
            --prefix=/usr \
            --sysconfdir=/etc/zabbix \
            --prefix=/usr \
            --enable-agent \
            --with-ldap \
            --with-openssl \
            --enable-ipv6 \
            --silent && \
    make -j"$(nproc)" -s

FROM arm32v7/alpine

ARG BUILD_DATE
ARG VCS_REF

ARG APK_FLAGS_COMMON=""
ARG APK_FLAGS_PERSISTENT="${APK_FLAGS_COMMON} --clean-protected --no-cache"

ARG MAJOR_VERSION=4.2
ARG ZBX_VERSION=${MAJOR_VERSION}.4
ARG ZBX_SOURCES=https://git.zabbix.com/scm/zbx/zabbix.git
ENV TERM=xterm ZBX_VERSION=${ZBX_VERSION} ZBX_SOURCES=${ZBX_SOURCES} ZBX_TYPE=agent ZBX_DB_TYPE=none ZBX_OPT_TYPE=none

STOPSIGNAL SIGTERM

COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_agent/zabbix_agentd /usr/sbin/zabbix_agentd
COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_get/zabbix_get /usr/bin/zabbix_get
COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_sender/zabbix_sender /usr/bin/zabbix_sender
COPY --from=builder  /tmp/zabbix-${ZBX_VERSION}/conf/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf

RUN set -eux && \
    addgroup zabbix && \
    adduser -S -D -G zabbix -h /var/lib/zabbix/ zabbix && \
    mkdir -p /etc/zabbix && \
    mkdir -p /etc/zabbix/zabbix_agentd.d && \
    mkdir -p /var/lib/zabbix && \
    mkdir -p /var/lib/zabbix/enc && \
    mkdir -p /var/lib/zabbix/modules && \
    chown --quiet -R zabbix:zabbix /var/lib/zabbix && \
    apk update && \
    apk add ${APK_FLAGS_PERSISTENT} \
            bash \
            coreutils \
            iputils \
            libldap \
            pcre && \
    rm -rf /var/cache/apk/*

EXPOSE 10050/TCP

WORKDIR /var/lib/zabbix

VOLUME ["/etc/zabbix/zabbix_agentd.d", "/var/lib/zabbix/enc", "/var/lib/zabbix/modules"]

COPY ["docker-entrypoint.sh", "/usr/bin/"]