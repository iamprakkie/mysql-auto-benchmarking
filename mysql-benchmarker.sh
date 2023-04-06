#!/bin/bash
set -e

log() {
  echo
  echo -e "\e[37;42m$1\e[0m"
}

#set envs for mysql connection
source /home/ssm-user/mysql-dbt2-benchmarking/envs-for-mysql.sh

mysql -u benchmarker -h $MYSQL_HOST_IP --password=$BENCHMARKER_PWD
