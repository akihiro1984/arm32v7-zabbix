# Zabbix Project for arm32v7

# Setting up

`docket-compose up`

# small problem

`zabbix_core` log after `docker-compose up`

At function create_db_schema_mysql , there is a problem that logs are not displayed after the zcat command.

## Primary

Since the process is expected to complete normally, it is recommended to monitor with `docker-compose logs -f` in another session.

## Secondary

Check with `docker-compose up -d` and then `docker-compose logs -f`.

# Reference
https://github.com/zabbix/zabbix-docker

# Respect
Alexey Pustovalov <alexey.pustovalov@zabbix.com>