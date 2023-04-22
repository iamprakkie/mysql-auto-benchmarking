#!/bin/bash

source ./format_display.sh

# checking environment variables
if [ -z "${BENCHMARK_NAME}" ]; then
    log 'R' "env variable BENCHMARK_NAME not set"; exit 1
fi

aws ssm start-session \
    --target `aws cloudformation describe-stacks --query "Stacks[?StackName=='$BENCHMARK_NAME'][].Outputs[?OutputKey=='dbt2InstId'].OutputValue" --output text` \
    --document-name AWS-StartInteractiveCommand \
    --parameters command="cd /home/ssm-user && bash"  
