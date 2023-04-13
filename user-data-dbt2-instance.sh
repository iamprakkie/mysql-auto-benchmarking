#!/bin/bash

# format volume /dev/sda1 and mount to /dbt2-data
mkfs -t xfs /dev/sda1
mkdir /dbt2-data
mount /dev/sda1 /dbt2-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/dbt2-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# get pem key
MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION

KP_ID=$(aws cloudformation describe-stacks --stack-name mySQLAutoBenchmarking --query "Stacks[][].Outputs[?OutputKey=='keyPairId'].OutputValue" --output text)

aws ssm get-parameter --name /ec2/keypair/$KP_ID --with-decryption --query Parameter.Value --output text > /tmp/MySQLKeyPair.pem
chmod 600 /tmp/MySQLKeyPair.pem

# export mysql instance private IP
MYSQLINST=$(aws cloudformation describe-stacks --stack-name mySQLAutoBenchmarking --query "Stacks[][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)

echo "export MYSQLINST=$MYSQLINST" > /etc/profile.d/env-mysqlinst.sh

#testing users
ls -larth /home > /tmp/homelist.log
cp /etc/passwd /tmp/passwd.bkp

# install mysql client 8.0.32
yum update -y
rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
yum-config-manager --disable mysql57-community
yum-config-manager --enable mysql80-community
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install git jq -y
yum install mysql-community-client -y

#for dbt2
yum install wget gcc make cmake autoconf mysql-devel -y
