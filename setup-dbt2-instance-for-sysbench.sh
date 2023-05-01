#!/bin/bash
set -e

# This script need to be run in DBT2 machine.

source ./format_display.sh

#get token for IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

CURRINST=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

if [[ $CURRINST != $MYDBT2INST ]]; then
    log 'R' "This script need to be run only in DBT2 Instance ($MYDBT2INST)."
    exit 1
fi

log 'G-H' "Setting up DBT2 instance for running sysbench..."

#create required dirs
mkdir -p /home/ssm-user/bench /home/ssm-user/bench/mysql # benchmarking dir. Ensure autobench.conf reflects this configuration.
mkdir -p /home/ssm-user/bench/tarballs # Location where tar.gz of MySQL, DBT2 and Sysbench will be placed. Ensure autobench.conf and setup_dbt2.sh reflects this configuration.
mkdir -p /home/ssm-user/bench/sysbench # sysbench dir. This is also default-directory. Ensure autobench.conf reflects this configuration.

# Download MySQL, DBT2 and Sysbench tarballs
#wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.32-el7-x86_64.tar.gz -P /home/ssm-user/bench/tarballs/
wget -q https://dev.mysql.com/get/Downloads/MySQL-Cluster-8.0/mysql-cluster-8.0.32-el7-x86_64.tar.gz -P /home/ssm-user/bench/tarballs/
wget -q https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz -P /home/ssm-user/bench/tarballs/
wget -q https://downloads.mysql.com/source/sysbench-0.4.12.16.tar.gz -P /home/ssm-user/bench/tarballs/

#unpacking MySQL
tar xfz /home/ssm-user/bench/tarballs/mysql-cluster-8.0.32-el7-x86_64.tar.gz -C /home/ssm-user/bench/mysql/

#unpacking DBT2
tar xfz /home/ssm-user/bench/tarballs/dbt2-0.37.50.16.tar.gz -C /home/ssm-user/bench/tarballs/

#copy required files
cp /home/ssm-user/bench/tarballs/dbt2-0.37.50.16/scripts/bench_run.sh /home/ssm-user/bench/
cp /home/ssm-user/bench/env-files/`basename $BENCHMARK_ENV_FILENAME .env_vars`"-"${MYSQL_AUTOBENCH_CONF} /home/ssm-user/bench/sysbench/autobench.conf

log 'G' "DBT2 setup COMPLETE. Verify values in /home/ssm-user/bench/sysbench/autobench.conf"
