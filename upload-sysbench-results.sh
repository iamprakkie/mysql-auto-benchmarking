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

log 'G-H' "Uploading sysbench logs and results to S3 bucket.."

# get region
MYREGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION

# check and upload files
if [[ -f /home/ssm-user/bench/sysbench-init-output.log ]]; then
    aws s3 cp /home/ssm-user/bench/sysbench-init-output.log s3://${S3_BUCKET_NAME}/sysbench-init-output.log
fi

if [[ -f /home/ssm-user/bench/sysbench-run-output.log ]]; then
    aws s3 cp /home/ssm-user/bench/sysbench-run-output.log s3://${S3_BUCKET_NAME}/sysbench-run-output.log
fi

if [[ -f /home/ssm-user/bench/sysbench/final_result_0.txt ]]; then
    aws s3 cp /home/ssm-user/bench/sysbench/final_result_0.txt s3://${S3_BUCKET_NAME}/final_result_0.txt
fi

if [[ -f /home/ssm-user/bench/sysbench/final_result.txt ]]; then
    aws s3 cp /home/ssm-user/bench/sysbench/final_result.txt s3://${S3_BUCKET_NAME}/final_result.txt
fi

if [[ -f /home/ssm-user/bench/sysbench/sysbench_results/oltp_rw_0_0.res ]]; then
    aws s3 cp /home/ssm-user/bench/sysbench/sysbench_results/oltp_rw_0_0.res s3://${S3_BUCKET_NAME}/'sysbench-result-'${BENCHMARK_NAME}'.res'
fi

log 'G' "Sysbench results upload COMPLETE. Check in respective S3 bucket."
