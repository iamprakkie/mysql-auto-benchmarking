#!/bin/bash
aws ssm start-session \
--target `aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLAutoBenchmarking'][].Outputs[?OutputKey=='mySQLInstId'].OutputValue" --output text` \
--document-name AWS-StartInteractiveCommand \
--parameters command="cd /home/ssm-user && bash -l"  
