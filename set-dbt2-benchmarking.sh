#!/bin/bash
set -e

log() {
  echo
  echo -e "\e[37;42m$1\e[0m"
}

MYSQL_PATH=$(which mysql)
MYSQL_DIR=$(dirname $mysql_path)

MYSQL_HOST_IP=$(aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLBenchmarking'][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)
BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

#cp altered_mysql_load_sp.sh ~/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_sp.sh
#cp altered_mysql_load_db.sh ~/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh

log "Generating data..."
mkdir -p ~/dbt2/data
~/dbt2/dbt2-0.37.50.16/src/datagen -w 20 -d ~/dbt2/data --mysql

# convert customer data to UTF-8 (utf8mb4 is the default in MySQL 8.0)
log "Converting to UTF-8..."
for filename in `find ~/dbt2/data  -type f -name \*.data`; do
    echo $filename
    mv $filename $filename.bak
    iconv -f ISO-8859-1 -t UTF-8 $filename.bak -o $filename
    rm $filename.bak
done

log "Loading data into dbt2 database"
~/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh --local --path ~/dbt2/data --mysql-path $MYSQL_PATH --database dbt2 --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD

log "Loading stored procedures into dbt2 database"
~/dbt2/dbt2-0.37.50.16//mysql_load_sp.sh --client-path $MYSQL_DIR --sp-path ~/dbt2/dbt2-0.37.50.16/storedproc/mysql --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD

log "Benchmarking.."
./run_mysql.sh --connections 20 --time 300 --warehouses 20 --zero-delay --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD