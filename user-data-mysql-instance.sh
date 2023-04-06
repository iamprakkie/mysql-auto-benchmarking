#!/bin/bash

# format volume /dev/sda1 and mount to /mysql-data
mkfs -t xfs /dev/sda1
mkdir /mysql-data
mount /dev/sda1 /mysql-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/mysql-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

yum update -y
yum install git jq -y
yum install wget gcc make cmake autoconf mysql-devel -y

# create new directory for benchmarking
mkdir -p /mysql-data/bench
chown -R ssm-user:ssm-user /mysql-data/bench
