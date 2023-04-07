#!/bin/bash
aws ssm start-session --target `aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLBenchmarking'][].Outputs[?OutputKey=='dbt2InstId'].OutputValue" --output text`