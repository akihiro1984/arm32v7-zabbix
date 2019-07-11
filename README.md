# under construction project

# What's this?
arm32v7 Zabbix Project

# Setting up

`docket-compose up`

# small problem
Sometimes, create user or/and grant user may be unsuccessful on MariaDB.
fix by hand...
```
CREATE USER 'zabbix'@'%' IDENTIFIED BY 'zabbix';
CREATE DATABASE zabbix CHARACTER SET utf8 COLLATE utf8_bin;
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%'
```
I will fix it later...

# Reference
https://github.com/zabbix/zabbix-docker

# Respect
Alexey Pustovalov <alexey.pustovalov@zabbix.com>