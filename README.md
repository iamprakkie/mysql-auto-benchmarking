
# Auto benchmarking of MySQL 8 running on EC2 instance using DBT2. Create EC2 instance in new VPC using CDK and access them using SSM.

This example includes:

* Own VPC with public subnet (following AWS Defaults for new accounts)
* Based on latest Amazon Linux 2
* System Manager replaces SSH (Remote session available trough the AWS Console or the AWS CLI.)
* Userdata executed from script in S3.

## Useful commands

 * `virtualenv --python python3.7 venv` create python3.7 virtual environment
 * `source venv/bin/activate`   activate venv
 * `pip install -r requirements.txt`    install requirements
 * `cdk bootstrap`   initialize assets before deploy
 * `cdk synth`       emits the synthesized CloudFormation template
 * `cdk deploy`      deploy this stack to your default AWS account/region
 * `aws ssm start-session --target i-xxxxxxxxx` remote session for shell access
 * `deactivate` deactivate venv

## Usage

1. Clone this repository
    ```bash
    git clone https://github.com/iamprakkie/mysql-auto-benchmarking.git
    cd mysql-auto-benchmarking
    ```

1. Set below mentioned environment variables with required values
    ```bash
    export MYSQL_INST_TYPE="r5.8xlarge" # when not set, will use t3.medium as default value
    export MYSQL_VOL_SIZE=500 # when not set, will use 50 (GB) as default value
    export MYSQL_VOL_TYPE="io1" # when not set, will use gp3 as default value
    export MYSQL_VOL_IOPS=3000 # when not set, will use 150 as default value. This value will be used only for gp3, io1 and io2 volume types.
    ```
1. Verify and do required changes to user data of MySQL instance in `user-data-mysql-instance.sh`.

1. Deploy CDK to create MySQL instance using below mentioned commands. MySQL instance will be of type mentioned in `$MYSQL_INST_TYPE`. MySQL instance root volume will have 50GB GP3 storage and data volume (/dev/sda1) will be created with values as in env variables mentioned above.
    ```bash
    virtualenv --python python3.7 venv
    source venv/bin/activate
    pip install -r requirements.txt
    cdk bootstrap
    cdk deploy
    ```

1. Then, start SSM session to MySQL instance.
    ```bash
    sh ./connect-to-mysql-instance.sh
    ```

1. Run below script in MySQL instance to setup auto benchmarking
    ```bash
    cd /home/ssm-user
    git clone https://github.com/iamprakkie/mysql-auto-benchmarking.git
    sh /home/ssm-user/mysql-auto-benchmarking/setup-autobench.sh
    ```

## Clean up

* Cleanup all resources created by using cdk destroy from host.
    ```bash
    cdk destroy
    deactivate
    ```
