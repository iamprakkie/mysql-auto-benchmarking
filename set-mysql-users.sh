#!/bin/bash
set -e

#get required stack output
MYSQL_REGION=$(aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLBenchmarking'][].Outputs[?OutputKey=='mysqlRegion'].OutputValue" --output text)
ROOT_SECRET_ID=$(aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLBenchmarking'][].Outputs[?OutputKey=='mysqlRootSecret'].OutputValue" --output text)
BENCHMARKER_SECRET_ID=$(aws cloudformation describe-stacks --query "Stacks[?StackName=='mySQLBenchmarking'][].Outputs[?OutputKey=='mysqlBenchmarkerSecret'].OutputValue" --output text)

#get new passwords from secret
ROOT_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $ROOT_SECRET_ID --query SecretString --output text)
BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

export TEMP_PASS=`grep 'temporary password' /var/log/mysqld.log|awk '{print $13}'`
echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PWD';" > /root/my.sql
#echo "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$ROOT_PWD';" > /root/my.sql
echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;" >> /root/my.sql
echo "CREATE USER 'benchmarker'@'%' IDENTIFIED BY '$BENCHMARKER_PWD';" >> /root/my.sql
echo "GRANT ALL PRIVILEGES ON *.* TO 'benchmarker'@'%' WITH GRANT OPTION;" >> /root/my.sql
echo "FLUSH PRIVILEGES;" >> /root/my.sql
sleep 3
mysql --connect-expired-password -u root --password="$TEMP_PASS" mysql < /root/my.sql
rm -fr /root/my.sql