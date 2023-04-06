
# Create EC2 Instance in new VPC with Systems Manager enabled and install mySQL v8.0.31

This example includes:

* Own VPC with public subnet (following AWS Defaults for new accounts)
* Based on latest Amazon Linux 2
* System Manager replaces SSH (Remote session available trough the AWS Console or the AWS CLI.)
* Userdata executed from script in S3 (`configure.sh`).

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
    git clone https://github.com/iamprakkie/my-cdk.git
    cd my-cdk
    ```

1. Set below mentioned environment variables with required values
    ```bash
    export MYSQL_INST_TYPE="r5.8xlarge" # when not set, will use t3.medium as default value
    export MYSQL_VOL_SIZE=500 # when not set, will use 50 (GB) as default value
    export MYSQL_VOL_TYPE="io1" # when not set, will use gp3 as default value
    export MYSQL_VOL_IOPS=3000 # when not set, will use 150 as default value. This value will be used only for gp3, io1 and io2 volume types.
    ```
1. Verify and do required changes to user data of MySQL and DBT2 instances. They are in `user-data-mysql-instance.sh` and `user-data-dbt2-instance.sh` respectively.

1. Deploy CDK to create MySQL instance and DBT2 instance using below mentioned commands. Both instances will be of type mentioned in `$MYSQL_INST_TYPE`. MySQL instance root volume will have 100GB GP3 storage and data volume (/dev/sda1) will be created with values as in env variables mentioned above. /var/lib/mysql will be in /dev/sda1 volume. DBT2 instance root volume will have 100GB GP3 storage. 
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

1. Change MySQL root user password and create new MySQL user benchmarker by running below commands in MySQL instance. Passwords are picked up from Secrets created as part of CDK deployment.
    ```bash
    cd /home/ssm-user
    git clone https://github.com/iamprakkie/my-cdk.git
    cd my-cdk
    sudo sh ./set-mysql-users.sh
    ```

1. Exit from MySQL instance's SSM session. Then, start SSM session to DBT2 instance.
    ```bash
    sh ./connect-to-dbt2-instance.sh
    ```

1. Run below commands to set DBT2 benchmarking.
    ```bash
    cd /home/ssm-user
    git clone https://github.com/iamprakkie/my-cdk.git
    cd my-cdk
    sh ./envs-for-mysql.sh
    sh ./set-dbt2.sh 50 # 1st parameter = number of warehouses.
    ```

1. Run DBT2 benchmarking using this script.
    ```bash
    sh /home/ssm-user/my-cdk/run-dbt2-benchmarking.sh 50 30 # 1st parameter = number of warehouses, 2nd parameter = number of connections. Both defaults to 20.
    ```

1. You can below script to connect to MySQL client as benchmaker user from MySQL or DBT2 instance.
    ```bash
    sh /home/ssm-user/my-cdk/mysql-benchmarker.sh
    ```

1. Cleanup all resources created by using cdk destroy from host.
    ```bash
    cdk destroy
    deactivate
    ```
