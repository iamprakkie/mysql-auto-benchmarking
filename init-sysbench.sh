#!/bin/bash
set -e

# This script need to be run in DBT2 machine.

source ./format_display.sh

CURRINST=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

if [[ $CURRINST != $MYDBT2INST ]]; then
    log 'R' "This script need to be run only in DBT2 Instance ($MYDBT2INST)."
    exit 1
fi

log 'G-H' "Initializing sysbench and generating sample data..."

/home/ssm-user/bench/bench_run.sh --default-directory /home/ssm-user/bench/sysbench --init --generate-dbt2-data --skip-run --verbose > /home/ssm-user/bench/sysbench-init-output.log 2>&1 

mkdir -p /home/ssm-user/bench/mysql/sysbench-0.4.12.16/bin
ln -sf /home/ssm-user/bench/sysbench/src/sysbench-0.4.12.16/sysbench/sysbench /home/ssm-user/bench/mysql/sysbench-0.4.12.16/bin/sysbench

log 'G' "Sysbench initialization COMPLETE. Initilazation log is available at /home/ssm-user/bench/sysbench-init-output.log."
