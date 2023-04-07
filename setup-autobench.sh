#!/bin/bash

#change ownership of bench dir
sudo chown -R ssm-user:ssm-user /mysql-data/bench

# download tarballs
mkdir -p /mysql-data/bench/mysql /mysql-data/bench/tarballs /mysql-data/bench/dbt2_data
cd /mysql-data/bench/tarballs
wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.32-el7-x86_64.tar.gz #mysql
wget https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz #dbt2
wget https://downloads.mysql.com/source/sysbench-0.4.12.16.tar.gz #sysbench

cp /home/ssm-user/mysql-auto-benchmarking/dbt2-autobench.conf /mysql-data/bench
ln -sf /mysql-data/bench/dbt2-autobench.conf /mysql-data/bench/autobench.conf

cp /home/ssm-user/mysql-auto-benchmarking/bench_run.sh /mysql-data/bench
cd /mysql-data/bench
/mysql-data/bench/bench_run.sh --default-directory /mysql-data/bench --init


# --generate-dbt2-data