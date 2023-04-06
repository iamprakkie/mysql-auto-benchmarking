#!/bin/bash
set -e

log() {
  echo
  echo -e "\e[37;42m$1\e[0m"
}

WAREHOUSE_COUNT=${1:-20}
CONNECTIONS=${2:-20}

MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION
MYSQL_REGION=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlRegion'].OutputValue" --output text)

MYSQL_HOST_IP=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)
BENCHMARKER_SECRET_ID=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlBenchmarkerSecret'].OutputValue" --output text)
BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

log "Benchmarking.."
/home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/run_mysql.sh --connections $CONNECTIONS --time 300 --warehouses $WAREHOUSE_COUNT --zero-delay --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD