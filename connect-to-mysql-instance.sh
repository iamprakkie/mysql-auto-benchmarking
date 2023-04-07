#!/bin/bash
aws ssm start-session --target `aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLAutoBenchmarking'][].Outputs[?OutputKey=='mySQLInstId'].OutputValue" --output text`