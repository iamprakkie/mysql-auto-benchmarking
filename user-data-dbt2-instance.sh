#!/bin/bash

# format volume /dev/sda1 and mount to /dbt2-data if you plan to use separate mount
# mkfs -t xfs /dev/sda1
# mkdir /dbt2-data
# mount /dev/sda1 /dbt2-data
# cp /etc/fstab /etc/fstab.orig
# echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/dbt2-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# install mysql client 8.0.32
yum update -y
rpm -Uvh https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
yum-config-manager --disable mysql57-community
yum-config-manager --enable mysql80-community
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install git tree jq -y
yum install mysql-community-client -y

#for dbt2
yum install wget gcc make cmake autoconf mysql-devel -y
yum install numactl -y
yum install gnuplot -y

#get token for IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# get region
MYREGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)
aws configure set region $MYREGION

# get instance id
MYINSTID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

#retrieve benchmark name from instance tag
BENCHMARK_NAME=$(aws ec2 describe-instances --region $MYREGION --instance-ids $MYINSTID --query "Reservations[*].Instances[*].Tags[?Key=='aws:cloudformation:stack-name'].Value" --output text)
echo "benchmark name is $BENCHMARK_NAME"

# aws cli v2
INST_ARCH=$(aws cloudformation describe-stacks --region $MYREGION --stack-name $BENCHMARK_NAME --query "Stacks[][].Outputs[?OutputKey=='instArch'].OutputValue" --output text)
echo "instance architecture is $INST_ARCH"

if [ $INST_ARCH == "x86_64" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
elif [ $INST_ARCH == "ARM_64" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
fi

echo "aws cli v2 installed"
aws --version

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

echo "created ssm-user"

#creating .ssh 
mkdir -p /home/ssm-user/.ssh
chmod 700 /home/ssm-user/.ssh

# get pem key
KP_ID=$(aws cloudformation describe-stacks --region $MYREGION --stack-name $BENCHMARK_NAME --query "Stacks[][].Outputs[?OutputKey=='keyPairId'].OutputValue" --output text)
aws ssm get-parameter --region $MYREGION --name /ec2/keypair/$KP_ID --with-decryption --query Parameter.Value --output text > /home/ssm-user/.ssh/MySQLKeyPair.pem
chmod 600 /home/ssm-user/.ssh/MySQLKeyPair.pem

# add ssh config entry for mysql instance
echo "Host $MYSQLINST" >> /home/ssm-user/.ssh/config
echo "  Hostname $MYSQLINST" >> /home/ssm-user/.ssh/config
echo "  IdentityFile /home/ssm-user/.ssh/MySQLKeyPair.pem" >> /home/ssm-user/.ssh/config
echo "  User ssm-user" >> /home/ssm-user/.ssh/config
chmod 600 /home/ssm-user/.ssh/config

# change ownership
chown -R ssm-user:ssm-user /home/ssm-user/.ssh

echo "ssh config entry added"

# set custom alias
echo "alias ll='ls -larth'" > /etc/profile.d/user-alias.sh

# create custom envs
echo "export BENCHMARK_NAME=$BENCHMARK_NAME" > /etc/profile.d/custom-envs.sh
echo "export INST_ARCH=$INST_ARCH" >> /etc/profile.d/custom-envs.sh
echo "export MYSQLINST=$MYSQLINST" >> /etc/profile.d/custom-envs.sh
echo "export MYDBT2INST=$MYDBT2INST" >> /etc/profile.d/custom-envs.sh
echo "export USER=ssm-user" >> /etc/profile.d/custom-envs.sh

echo "custom envs created"

#create required dirs
mkdir -p /home/ssm-user/bench /home/ssm-user/bench/mysql # benchmarking dir. Ensure autobench.conf reflects this configuration.
mkdir -p /home/ssm-user/bench/tarballs # Location where tar.gz of MySQL, DBT2 and Sysbench will be placed. Ensure autobench.conf and setup_dbt2.sh reflects this configuration.
mkdir -p /home/ssm-user/bench/sysbench # sysbench dir. This is also default-directory. Ensure autobench.conf reflects this configuration.

# Download env-file from S3 bucket
aws s3 cp --region $MYREGION s3://${BENCHMARK_NAME}-artifacts/ /home/ssm-user/bench/env-files/ --recursive

echo "downloaded env-files"

# change ownership
chown -R ssm-user:ssm-user /home/ssm-user/bench

#clone repo
git clone https://github.com/iamprakkie/mysql-auto-benchmarking.git /home/ssm-user/mysql-auto-benchmarking

# change ownership
chown -R ssm-user:ssm-user /home/ssm-user/mysql-auto-benchmarking

echo "cloned repo"

# Enable RPS
sudo sh -c 'for x in /sys/class/net/eth0/queues/rx-*; do echo ffffffff > $x/rps_cpus; done' 
sudo sh -c "echo 4096 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt"

sudo sh -c "echo 4096 > /sys/class/net/eth0/queues/rx-1/rps_flow_cnt"

# Enable RFS
sudo sh -c "echo 32768 > /proc/sys/net/core/rps_sock_flow_entries"

echo "User data script completed."