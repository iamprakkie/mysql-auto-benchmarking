#!/bin/bash

# format volume /dev/sda1 and mount to /mysql-data
mkfs -t xfs /dev/sda1
mkdir /mysql-data
mount /dev/sda1 /mysql-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/mysql-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# install mysql client 8.0.32
yum update -y
rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
yum-config-manager --disable mysql57-community
yum-config-manager --enable mysql80-community
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install git tree jq -y
yum install mysql-community-client -y


#for dbt2
yum install numactl -y

# get region
MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION

# get instance id
MYINSTID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

#retrieve benchmark name from instance tag
BENCHMARK_NAME=$(aws ec2 describe-instances --region $MYREGION --instance-ids $MYINSTID --query "Reservations[*].Instances[*].Tags[?Key=='aws:cloudformation:stack-name'].Value" --output text)

# get instance private IPs
MYSQLINST=$(aws cloudformation describe-stacks --region $MYREGION --stack-name $BENCHMARK_NAME --query "Stacks[][].Outputs[?OutputKey=='mySQLPrivIP'].OutputValue" --output text)
MYDBT2INST=$(aws cloudformation describe-stacks --region $MYREGION --stack-name $BENCHMARK_NAME --query "Stacks[][].Outputs[?OutputKey=='dbt2PrivIP'].OutputValue" --output text)

# create ssm-user
adduser -U -m ssm-user
tee /etc/sudoers.d/ssm-agent-users <<'EOF'
# User rules for ssm-user
ssm-user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/ssm-agent-users

#creating .ssh 
mkdir -p /home/ssm-user/.ssh

#copying .ssh from ec2-user to ssm-user
cp -r /home/ec2-user/.ssh /home/ssm-user

# set permissions
chown -R ssm-user:ssm-user /home/ssm-user/.ssh
chmod 700 /home/ssm-user/.ssh

# set custom alias
echo "alias ll='ls -larth'" > /etc/profile.d/user-alias.sh

# create custom envs
echo "export USER=ssm-user" > /etc/profile.d/custom-envs.sh
echo "export MYSQLINST=$MYSQLINST" > /etc/profile.d/custom-envs.sh
echo "export MYDBT2INST=$MYDBT2INST" >> /etc/profile.d/custom-envs.sh
echo "export BENCHMARK_NAME=$BENCHMARK_NAME" >> /etc/profile.d/custom-envs.sh

#create required dirs
mkdir -p /home/ssm-user/bench /home/ssm-user/bench/mysql # benchmarking dir
mkdir -p /mysql-data/mysql-data-dir # MySQL data directory. This is the location of mysql data-dir. If you change this, remember set the same value in DATA_DIR_BASE of autobench.conf

# create soft link
ln -s /mysql-data/mysql-data-dir /home/ssm-user/bench/mysql-data-dir

#change ownership
chown -R ssm-user:ssm-user /mysql-data/mysql-data-dir /home/ssm-user/bench

# ===================================================================================
# rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
# yum-config-manager --disable mysql57-community
# yum-config-manager --enable mysql80-community
# rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
# yum install mysql-community-server -y
# systemctl enable mysqld
# systemctl start mysqld

# changing mysql datadir
# stop MySQL before copying over files
# sleep 10
# systemctl stop mysqld

# create new directory for MySQL data
# mkdir -p /mysql-data/mysql

# set ownership of new directory to match existing one
# chown --reference=/var/lib/mysql /mysql-data/mysql

# set permissions on new directory to match existing one
# chmod --reference=/var/lib/mysql /mysql-data/mysql

# copy all files in default directory, to new one, retaining perms (-p)
# cp -rp /var/lib/mysql/* /mysql-data/mysql/
# rm -fr /var/lib/mysql

# create soft link
# ln -s /mysql-data/mysql /var/lib/mysql
# chown -h --reference=/mysql-data/mysql /var/lib/mysql

# set tmp dir
# mkdir -p /mysql-data/mysql-tmpdir

# set ownership of new directory to match existing one
# chown --reference=/var/lib/mysql /mysql-data/mysql-tmpdir

# set permissions on new directory to match existing one
# chmod --reference=/var/lib/mysql /mysql-data/mysql-tmpdir

#p opulate tmpdir in my.cnf
# echo "tmpdir = /mysql-data/mysql-tmpdir" >> /etc/my.cnf

# set bind address
# MYPRIVATEIP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
# echo "bind-address = $MYPRIVATEIP" >> /etc/my.cnf

# set local-infile
#echo "[client]" >> /etc/my.cnf
#echo "local-infile = 1" >> /etc/my.cnf
#echo "[server]" >> /etc/my.cnf
# echo "local_infile=ON" >> /etc/my.cnf
#echo "[client]" >> /etc/my.cnf
#echo "local_infile=ON" >> /etc/my.cnf

#start mysql
# systemctl start mysqld

# Setup mysql users

# MYREGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
# aws configure set region $MYREGION

#get required stack output
# MYSQL_REGION=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlRegion'].OutputValue" --output text)
# ROOT_SECRET_ID=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlRootSecret'].OutputValue" --output text)
# BENCHMARKER_SECRET_ID=$(aws cloudformation describe-stacks --stack-name 'mySQLBenchmarking' --query "Stacks[][].Outputs[?OutputKey=='mysqlBenchmarkerSecret'].OutputValue" --output text)

#get new passwords from secret
# ROOT_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $ROOT_SECRET_ID --query SecretString --output text)
# BENCHMARKER_PWD=$(aws secretsmanager get-secret-value --region $MYSQL_REGION --secret-id $BENCHMARKER_SECRET_ID --query SecretString --output text)

# export TEMP_PASS=`grep 'temporary password' /var/log/mysqld.log|awk '{print $13}'`
# echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PWD';" > /root/my.sql
# echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;" >> /root/my.sql
# echo "CREATE USER 'benchmarker'@'%' IDENTIFIED BY '$BENCHMARKER_PWD';" >> /root/my.sql
# echo "GRANT ALL PRIVILEGES ON *.* TO 'benchmarker'@'%' WITH GRANT OPTION;" >> /root/my.sql
# echo "FLUSH PRIVILEGES;" >> /root/my.sql
# sleep 3
# mysql --connect-expired-password -u root --password="$TEMP_PASS" mysql < /root/my.sql
# rm -fr /root/my.sql


