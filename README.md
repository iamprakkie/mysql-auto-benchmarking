
# Auto Benchmarking of MySQL 8 running on EC2 instances using Sysbench. Create EC2 instances in new VPC using CDK, access them using SSM and run DBT2 sysbench auto benchmark.

## Usage

1. Clone this repository
    ```bash
    git clone https://github.com/iamprakkie/mysql-auto-benchmarking.git
    cd mysql-auto-benchmarking
    ```

1. Set below mentioned environment variables with required values
    ```bash
    export BENCHMARK_NAME="mySQLAutoBenchmarking" # give unique name for your benchmarking. This will your CDK app name
    export MYSQL_INST_TYPE="r5.8xlarge" # when not set, will use t3.medium as default value
    export MYSQL_VOL_SIZE=500 # when not set, will use 50 (GB) as default value
    export MYSQL_VOL_TYPE="io1" # when not set, will use gp3 as default value
    export MYSQL_VOL_IOPS=3000 # when not set, will use 150 as default value. This value will be used only for gp3, io1 and io2 volume types.
    ```
1. Verify and do required changes to user data of MySQL and DBT2 instances. They are in `user-data-mysql-instance.sh` and `user-data-dbt2-instance.sh` respectively.

1. Deploy CDK to create MySQL instance and DBT2 instance using below mentioned commands. Both instances will be of type mentioned in `$MYSQL_INST_TYPE`. MySQL instance root volume will have 100GB GP3 storage and data volume (/dev/sda1) will be created with values as in env variables mentioned above. /var/lib/mysql will be in /dev/sda1 volume. DBT2 instance root volume will have 100GB GP3 storage. 
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    python3 -m pip install --upgrade pip
    pip install -r requirements.txt
    

    virtualenv --python python3.7 venv
    source venv/bin/activate
    pip install -r requirements.txt
    cdk bootstrap
    cdk deploy $BENCHMARK_NAME
    ```

1. Start SSM session to DBT2 instance.
    ```bash
    sh ./connect-to-dbt2-instance.sh
    ```

1. Setup DBT2 using below command.
    ```bash
    cd /home/ssm-user/mysql-auto-benchmarking
    sh ./setup-dbt2-instance-for-sysbench.sh
    ```

1. Initialize sysbench using below command.
    ```bash
    cd /home/ssm-user/mysql-auto-benchmarking
    sh ./init-sysbench.sh
    ```

1. Run sysbench below command.
    ```bash
    sh /home/ssm-user/mysql-auto-benchmarking/run-sysbench.sh
    ```

## Clean up

* Cleanup all resources created by using cdk destroy from host.
    ```bash
    cdk destroy $BENCHMARK_NAME
    deactivate
    ```
