#!/bin/bash
set -e

log() {
  echo
  echo -e "\e[37;42m$1\e[0m"
}

WAREHOUSE_COUNT=${1:-20}
CONNECTIONS=${2:-20}

#set envs for mysql connection
source /home/ssm-user/mysql-dbt2-benchmarking/envs-for-mysql.sh

log "Benchmarking.."
/home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/run_mysql.sh --connections $CONNECTIONS --time 300 --warehouses $WAREHOUSE_COUNT --zero-delay --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD