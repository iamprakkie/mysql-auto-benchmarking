#!/bin/bash

# format volume /dev/sda1 and mount to /mysql-data
mkfs -t xfs /dev/sda1
mkdir /mysql-data
mount /dev/sda1 /mysql-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/mysql-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# install mysql 8.0.32
yum update -y
yum install jq -y
rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
yum-config-manager --disable mysql57-community
yum-config-manager --enable mysql80-community
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install mysql-community-server -y
systemctl enable mysqld
systemctl start mysqld

# changing mysql datadir
# stop MySQL before copying over files
sleep 10
systemctl stop mysqld

# create new directory for MySQL data
mkdir -p /mysql-data/mysql

# set ownership of new directory to match existing one
chown --reference=/var/lib/mysql /mysql-data/mysql

# set permissions on new directory to match existing one
chmod --reference=/var/lib/mysql /mysql-data/mysql

# copy all files in default directory, to new one, retaining perms (-p)
cp -rp /var/lib/mysql/* /mysql-data/mysql/
rm -fr /var/lib/mysql

# create soft link
ln -s /mysql-data/mysql /var/lib/mysql
chown -h --reference=/mysql-data/mysql /var/lib/mysql

# set tmp dir
mkdir -p /mysql-data/mysql-tmpdir

# set ownership of new directory to match existing one
chown --reference=/var/lib/mysql /mysql-data/mysql-tmpdir

# set permissions on new directory to match existing one
chmod --reference=/var/lib/mysql /mysql-data/mysql-tmpdir

#p opulate tmpdir in my.cnf
echo "tmpdir = /mysql-data/mysql-tmpdir" >> /etc/my.cnf

# set bind address
MYPRIVATEIP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
echo "bind-address = $MYPRIVATEIP" >> /etc/my.cnf

# set local-infile
#echo "[client]" >> /etc/my.cnf
#echo "local-infile = 1" >> /etc/my.cnf
#echo "[server]" >> /etc/my.cnf
echo "local_infile=ON" >> /etc/my.cnf
#echo "[client]" >> /etc/my.cnf
#echo "local_infile=ON" >> /etc/my.cnf

#start mysql
systemctl start mysqld
