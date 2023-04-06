export MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION
export MYSQL_REGION=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlRegion'].OutputValue" --output text)

expor MYSQL_HOST_IP=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)
export BENCHMARKER_SECRET_ID=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlBenchmarkerSecret'].OutputValue" --output text)
export BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

