#!/bin/bash

#change ownership of bench dir
sudo chown -R ssm-user:ssm-user /mysql-data/bench

# download tarballs
mkdir -p /mysql-data/bench/mysql /mysql-data/bench/tarballs /mysql-data/bench/data
wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.32-el7-x86_64.tar.gz -P /mysql-data/bench/tarballs #mysql
wget https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz -P /mysql-data/bench/tarballs #dbt2
wget https://downloads.mysql.com/source/sysbench-0.4.12.16.tar.gz -P /mysql-data/bench/tarballs #sysbench

cp /home/ssm-user/mysql-auto-benchmarking/dbt2-autobench.conf /mysql-data/bench
ln -sf /mysql-data/bench/dbt2-autobench.conf /mysql-data/bench/autobench.conf

cp /home/ssm-user/mysql-auto-benchmarking/bench_run.sh /mysql-data/bench

#build for mysql
#sh /mysql-data/bench/bench_run.sh --default-directory /mysql-data/bench --build-mysql --generate-dbt2-data

sh ./bench_run.sh --default-directory /mysql-data/bench --verbose --init 2>&1 | tee output.log

sh ./bench_run.sh --default-directory /mysql-data/bench --verbose --build-mysql 2>&1 | tee output.log

sh ./bench_run.sh --default-directory /mysql-data/bench --verbose --generate-dbt2-data 2>&1 | tee output.log