#!/bin/bash
set -e

log() {
  echo
  echo -e "\e[37;42m$1\e[0m"
}

MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION
MYSQL_REGION=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlRegion'].OutputValue" --output text)

MYSQL_PATH=$(which mysql)
MYSQL_DIR=$(dirname $MYSQL_PATH)

MYSQL_HOST_IP=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)
BENCHMARKER_SECRET_ID=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlBenchmarkerSecret'].OutputValue" --output text)
BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

#cp altered_mysql_load_sp.sh /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_sp.sh
#cp altered_mysql_load_db.sh /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh

log "Generating data..."
mkdir -p /home/ssm-user/dbt2/data
/home/ssm-user/dbt2/dbt2-0.37.50.16/src/datagen -w 20 -d /home/ssm-user/dbt2/data --mysql

# convert customer data to UTF-8 (utf8mb4 is the default in MySQL 8.0)
log "Converting to UTF-8..."
for filename in `find /home/ssm-user/dbt2/data  -type f -name \*.data`; do
    echo $filename
    mv $filename $filename.bak
    iconv -f ISO-8859-1 -t UTF-8 $filename.bak -o $filename
    rm $filename.bak
done

log "Loading data into dbt2 database"
/home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh --local --path ~/dbt2/data --mysql-path $MYSQL_PATH --database dbt2 --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD

log "Loading stored procedures into dbt2 database"
/home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_sp.sh --client-path $MYSQL_DIR --sp-path ~/dbt2/dbt2-0.37.50.16/storedproc/mysql --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD

log "Benchmarking.."
/home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/run_mysql.sh --connections 20 --time 300 --warehouses 20 --zero-delay --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD