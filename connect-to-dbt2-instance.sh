#!/bin/bash
aws ssm start-session \
    --target `aws cloudformation describe-stacks --query "Stacks[?StackName=='$BENCHMARK_NAME'][].Outputs[?OutputKey=='dbt2InstId'].OutputValue" --output text` \
    --document-name AWS-StartInteractiveCommand \
    --parameters command="cd /home/ssm-user && bash -l"  
