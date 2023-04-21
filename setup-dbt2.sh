#!/bin/bash
set -e

# This script need to be run in DBT2 machine.

source ./format_display.sh


CURRINST=$(http://169.254.169.254/latest/meta-data/local-ipv4)

if [[ $CURRINSTID != $MYDBT2INST]]; then
    log 'R' "This script need to be run only in DBT2 Instance ($MYDBT2INST)."
    exit 1
fi

#create required dirs
mkdir -p /home/ssm-user/bench /home/ssm-user/bench/mysql # benchmarking dir. Ensure autobench.conf reflects this configuration.
mkdir -p /home/ssm-user/bench/tarballs # Location where tar.gz of MySQL, DBT2 and Sysbench will be placed. Ensure autobench.conf and setup_dbt2.sh reflects this configuration.
mkdir -p /home/ssm-user/bench/sysbench # sysbench dir. This is also default-directory. Ensure autobench.conf reflects this configuration.

# Download MySQL, DBT2 and Sysbench tarballs
#wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.32-el7-x86_64.tar.gz -P /home/ssm-user/bench/tarballs/
wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-8.0/mysql-cluster-8.0.32-el7-x86_64.tar.gz -P /home/ssm-user/bench/tarballs/
wget https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz -P /home/ssm-user/bench/tarballs/
wget https://downloads.mysql.com/source/sysbench-0.4.12.16.tar.gz -P /home/ssm-user/bench/tarballs/

#unpacking DBT2
tar xfz /home/ssm-user/bench/tarballs/dbt2-0.37.50.16.tar.gz -C /home/ssm-user/bench/tarballs/

#copy required files
cp /home/ssm-user/bench/tarballs/dbt2-0.37.50.16/scripts/bench_run.sh /home/ssm-user/bench/
cp /home/ssm-user/bench/tarballs/dbt2-0.37.50.16/examples/sysbench_autobench.conf /home/ssm-user/bench/sysbench/autobench.conf

## AUTOBENCH CONF PENDING##

exit 11

# WAREHOUSE_COUNT=${1:-20}

# mkdir -p /home/ssm-user/dbt2
# cd /home/ssm-user/dbt2
# wget https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz
# tar -xvzf dbt2-0.37.50.16.tar.gz
# cd dbt2-0.37.50.16
# ./configure --with-mysql
# sudo make -j 8
# sudo make install

# #set envs for mysql connection
# source /home/ssm-user/mysql-dbt2-benchmarking/envs-for-mysql.sh

# cp /home/ssm-user/mysql-dbt2-benchmarking/altered_mysql_load_sp.sh /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_sp.sh
# cp /home/ssm-user/mysql-dbt2-benchmarking/altered_mysql_load_db.sh /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh

# log 'G-H' "Generating data..."
# mkdir -p /home/ssm-user/dbt2/data
# rm -fr /home/ssm-user/dbt2/data/*
# /home/ssm-user/dbt2/dbt2-0.37.50.16/src/datagen -w $WAREHOUSE_COUNT -d /home/ssm-user/dbt2/data --mysql

# # convert customer data to UTF-8 (utf8mb4 is the default in MySQL 8.0)
# log 'G-H' "Converting to UTF-8..."
# for filename in `find /home/ssm-user/dbt2/data  -type f -name \*.data`; do
#     echo $filename
#     mv $filename $filename.bak
#     iconv -f ISO-8859-1 -t UTF-8 $filename.bak -o $filename
#     rm $filename.bak
# done

# log 'G-H' "Loading data into dbt2 database"
# /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_db.sh --local --path /home/ssm-user/dbt2/data --mysql-path $MYSQL_PATH --database dbt2 --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD

# log 'G-H' "Loading stored procedures into dbt2 database"
# /home/ssm-user/dbt2/dbt2-0.37.50.16/scripts/mysql/mysql_load_sp.sh --client-path $MYSQL_DIR --sp-path /home/ssm-user/dbt2/dbt2-0.37.50.16/storedproc/mysql --host $MYSQL_HOST_IP --user benchmarker --password $BENCHMARKER_PWD
