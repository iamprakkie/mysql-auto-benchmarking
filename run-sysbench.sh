#!/bin/bash
set -e

# This script need to be run in DBT2 machine.

source ./format_display.sh

CURRINST=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

if [[ $CURRINST != $MYDBT2INST ]]; then
    log 'R' "This script need to be run only in DBT2 Instance ($MYDBT2INST)."
    exit 1
fi

log 'G-H' "Running sysbench..."

/home/ssm-user/bench/bench_run.sh --default-directory /home/ssm-user/bench/sysbench --skip-start --verbose > /home/ssm-user/bench/sysbench-run-output.log 2>&1

log 'G' "Sysbench run COMPLETE. Initilazation log is available at /home/ssm-user/bench/sysbench-run-output.log."