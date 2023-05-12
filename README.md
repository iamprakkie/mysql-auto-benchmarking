
# Auto Benchmarking of MySQL 8 running on EC2 instances using Sysbench. Create EC2 instances in new VPC using CDK, access them using SSM and run DBT2 sysbench auto benchmark.

## Usage

1. Clone this repository
    ```bash
    git clone https://github.com/iamprakkie/mysql-auto-benchmarking.git
    cd mysql-auto-benchmarking
    ```

1. Modify `autobench.conf` as required. You can refer to sample files `fine-tuned-sysbench-autobench.conf` or `basic-sysbench-autobench.conf`.

1. Configure required environments in `env-config.yaml`. Here is a sample configuration
    ```yaml
    environments:
      - name: "r5.8xlarge gp3 Environment" # give a unique name
        region: "us-west-2" # region where env need to be deployed
        instancetype: "r5.8xlarge" # type of instance
        volumetype: "gp3" # gp2, gp3, io1 or io2
        volumesize: 500 # volume size in GB
        iops: 3000 # iops will be used only for gp3, io1 and io2 volume types
        autobenchconf: "fine-tuned-sysbench-autobench.conf" # autobench conf file name        
    ```

    >**NOTE: Only X86_64 architecture is supported currently.**

1. Verify and do required changes to user data of MySQL and DBT2 instances. They are in `user-data-mysql-instance.sh` and `user-data-dbt2-instance.sh` respectively.


1. Deploy CDK to create MySQL instance and DBT2 instance using below mentioned commands. Both instances will be of type mentioned in `instancetype` in `env-cofig.yaml`. MySQL instance root volume will have 100GB GP3 storage and data volume (/dev/sda1) will be created with values as in env variables mentioned above. /var/lib/mysql will be in /dev/sda1 volume. DBT2 instance root volume will have 100GB GP3 storage. 
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    python3 -m pip install --upgrade pip
    pip install -r requirements.txt
    export MY_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    export AWS_REGION="us-east-2"
    cdk bootstrap aws://${MY_ACCOUNT_ID}/${AWS_REGION}
    python deploy-env.py
    # python deploy-env.py [basic-env-config.yaml] # optionally specify config file name. By default, it picks up env-config.yaml
    ```
    >**NOTE:** deploy-env script looks for .done files in env_files dir and when found, skips respective environment.

1. You can start SSM session to DBT2 instance using below mentioned commands:
    ```bash
    source env_file/<.env_vars file of required environment>
    sh ./connect-to-dbt2-instance.sh
    ```

1. In similar, you can connect to MYSQL instance `./connect-to-mysql-instance.sh` script.

1. Run autobenchmark using below mentioned command:
    ```bash
    python autobench-sysbench.py
    # python autobench-sysbench.py [basic-env-config.yaml] # optionally specify config file name. By default, it picks up env-config.yaml
    ```

## Clean up

Cleanup all environments using below mentioned commands:
    ```bash
    python cleanup-env.py
    # python cleanup-env.py [basic-env-config.yaml] # optionally specify config file name. By default, it picks up env-config.yaml
    python delete-artifacts-buckets.py
    deactivate
    ```
