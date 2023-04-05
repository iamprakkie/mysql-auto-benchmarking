#!/bin/bash

# format volume /dev/sda1 and mount to /dbt2-data
mkfs -t xfs /dev/sda1
mkdir /dbt2-data
mount /dev/sda1 /dbt2-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/dbt2-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# install mysql client 8.0.32
yum update -y
rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
yum-config-manager --disable mysql57-community
yum-config-manager --enable mysql80-community
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install mysql-community-client -y

#dbt2 installation
yum install wget gcc make autoconf mysql-devel -y
mkdir -p ~/dbt2
cd ~/dbt2
wget https://downloads.mysql.com/source/dbt2-0.37.50.16.tar.gz
tar -xvzf dbt2-0.37.50.16.tar.gz
cd dbt2-0.37.50.16
./configure --with-mysql
make
make install
