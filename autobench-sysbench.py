#!/bin/python3

# This script is used to initialize sysbench on all environments created using deploy-env.py

import yaml
import os
import boto3
from botocore.exceptions import WaiterError

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    OKORANGE = '\033[33m'
    OKRED = '\033[31m'
    OKWHITE = '\033[37m'
    OKWHITE2 = '\033[97m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def run_ssm_command(ssm_command):
    ssm = boto3.client('ssm')
    reponse = ssm.send_command(
            InstanceIds=[dbt2InstId],
            DocumentName='AWS-RunShellScript',
            Parameters={"commands": [ssm_command]},
            CloudWatchOutputConfig={
                'CloudWatchOutputEnabled': True
                },
            TimeoutSeconds=172800
        )

    command_id = reponse['Command']['CommandId']

    waiter = ssm.get_waiter("command_executed")
    try:
        waiter.wait(
            CommandId=command_id,
            InstanceId=dbt2InstId,
            WaiterConfig={
                'Delay': 30,
                'MaxAttempts': 10000
            }
        )
    except WaiterError as err:
        print(err)

    command_output = ssm.get_command_invocation(
            CommandId=command_id,InstanceId=dbt2InstId)

    print()
    print(f"\t{bcolors.OKCYAN}CommandId: {command_output['CommandId']}{bcolors.ENDC}")
    print(f"\t{bcolors.OKCYAN}InstanceId: {command_output['InstanceId']}{bcolors.ENDC}")
    print(f"\t{bcolors.BOLD}Status: {command_output['Status']}{bcolors.ENDC}")

    print(f"\t{bcolors.OKWHITE2}StandardOutputContent: {command_output['StandardOutputContent']}{bcolors.ENDC}")
    
    if command_output['StandardErrorContent'] and not command_output['Status'] == 'Success':
        print(f"\t{bcolors.FAIL}StandardErrorContent: {command_output['StandardErrorContent']}{bcolors.ENDC}")
    print('-'*100)    

# Get config file name as command line argument
if len(os.sys.argv) > 1:
    configFileName = os.sys.argv[1]
else:
    configFileName = 'env-config.yaml'

# Read environments config file
with open(os.path.join(os.path.dirname(__file__), configFileName), 'r') as f:
    config = yaml.load(f, Loader=yaml.Loader)

envs = config['environments']
    
for env in envs:
    print(f"{bcolors.HEADER}WORKING ON ENVIRONMENT: {env['name']}{bcolors.ENDC}")

    # Read env_vars file
    env_var_filename = env['name'].replace(' ', "-") + '.env_vars'
    env_var_filename = env_var_filename.lower()
    autobench_conf_filename = env['name'].replace(' ', "-")+'-'+env['autobenchconf']
    autobench_conf_filename = autobench_conf_filename.lower()


    # dictionary for existing env
    existing_env={}

    with open(os.path.join(os.path.dirname(__file__), 'env_files', env_var_filename), 'r') as fenv:
        for line in fenv:
            if line.startswith('#'):
                continue
            
            # get value for an environment variable
            if line.startswith('export'):
                line = line.replace("export", "").strip()
                env_name, env_val = line.split('=')
                existing_env[env_name]=env_val
    
    print(f"\t{bcolors.OKORANGE}Benchmark name: {existing_env['BENCHMARK_NAME']}{bcolors.ENDC}")
    print(f"\t{bcolors.OKORANGE}env_vars file: {os.path.join(os.path.dirname(__file__), 'env_files', env_var_filename)}{bcolors.ENDC}")
    print(f"\t{bcolors.OKORANGE}autobench conf file: {os.path.join(os.path.dirname(__file__), 'env_files',  autobench_conf_filename)}{bcolors.ENDC}")

    # get DBT2 instance ID from a cloudformation stack
    cfn = boto3.client('cloudformation')
    stack_name = existing_env['BENCHMARK_NAME']
    stack_output = cfn.describe_stacks(StackName=stack_name)
    stack_outputs = stack_output['Stacks'][0]['Outputs']
    
    dbt2InstId = ''
    for output in stack_outputs:
        if output['OutputKey'] == 'dbt2InstId':
            dbt2InstId = output['OutputValue']


    # send command to DBT2 instance to setup sysbench
    print(f"\n{bcolors.OKBLUE}Setting up DBT2 instance: {dbt2InstId} for sysbench{bcolors.ENDC}")
    ssm_command = "su ssm-user --shell bash -c 'source /etc/profile.d/custom-envs.sh; source /home/ssm-user/bench/env-files/"+env_var_filename+"; cd /home/ssm-user/mysql-auto-benchmarking; bash ./setup-dbt2-instance-for-sysbench.sh'"
    run_ssm_command(ssm_command)

    # send command to DBT2 instance to initialize sysbench
    print(f"\n{bcolors.OKBLUE}Initialzing sysbench...{bcolors.ENDC}")
    # ssm_command = "su ssm-user --shell bash -c 'source /etc/profile.d/custom-envs.sh; source /home/ssm-user/bench/env-files/"+env_var_filename+"; cd /home/ssm-user/mysql-auto-benchmarking; ssh -o StrictHostKeyChecking=no $MYSQLINST'"
    # run_ssm_command(ssm_command)

    ssm_command = "su ssm-user --shell bash -c 'source /etc/profile.d/custom-envs.sh; source /home/ssm-user/bench/env-files/"+env_var_filename+"; cd /home/ssm-user/mysql-auto-benchmarking; bash ./init-sysbench.sh'"
    run_ssm_command(ssm_command)

    # send command to DBT2 instance to run sysbench
    print(f"\n{bcolors.OKBLUE}Running sysbench...{bcolors.ENDC}")
    ssm_command = "su ssm-user --shell bash -c 'source /etc/profile.d/custom-envs.sh; source /home/ssm-user/bench/env-files/"+env_var_filename+"; cd /home/ssm-user/mysql-auto-benchmarking; bash ./run-sysbench.sh'"
    run_ssm_command(ssm_command)
    

print(f"\n{bcolors.OKGREEN}AUTOBENCHMARKING COMPLETE!!{bcolors.ENDC}")