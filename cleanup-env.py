#!/bin/python3

# This script is used to clean up environments created using deploy-env.py

import yaml
import os
import subprocess
import boto3

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

# Get config file name as command line argument
if len(os.sys.argv) > 1:
    configFileName = os.sys.argv[1]
else:
    configFileName = 'env-config.yaml'

choice = input(f"{bcolors.OKRED}{bcolors.BOLD}This script will CLEANUP environment(s) configured in {configFileName}.\nDo you want to proceed? (y/n) {bcolors.ENDC}")
if choice.lower() != 'y':
    print(f"{bcolors.OKRED}Exiting..{bcolors.ENDC}")
    exit()


# Read environments config file
with open(os.path.join(os.path.dirname(__file__), configFileName), 'r') as f:
    config = yaml.load(f, Loader=yaml.Loader)

envs = config['environments']
    
for env in envs:
    # Checking for supported architecture
    ec2 = boto3.client('ec2')
    response = ec2.describe_instance_types(InstanceTypes=[env['instancetype']])
    architecture = response['InstanceTypes'][0]['ProcessorInfo']['SupportedArchitectures'][0]

    if architecture != 'x86_64':
        print(f"{bcolors.FAIL}Unsupported architecture: {architecture} of instance type {env['instancetype']} in environment {env['name']}. Skipping..{bcolors.ENDC}")
        print('-'*100)
        continue

    print(f"{bcolors.HEADER}Cleaning environment: {env['name']}{bcolors.ENDC}")    

    # Read env_vars file
    env_var_filename = env['name'].replace(' ', "-") + '.env_vars'
    env_var_filename = env_var_filename.lower()

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

    env_vars = {
        'PATH': os.environ['PATH'],
        'BENCHMARK_NAME': existing_env['BENCHMARK_NAME'],
        'BENCHMARK_REGION': existing_env['BENCHMARK_REGION'],
        'MYSQL_INST_TYPE': existing_env['MYSQL_INST_TYPE'],
        'MYSQL_VOL_SIZE': existing_env['MYSQL_VOL_SIZE'],
        'MYSQL_VOL_IOPS': existing_env['MYSQL_VOL_IOPS'],
        'MYSQL_VOL_TYPE': existing_env['MYSQL_VOL_TYPE'],
        'MYSQL_AUTOBENCH_CONF': existing_env['MYSQL_AUTOBENCH_CONF'],
        'BENCHMARK_ENV_NAME': existing_env['BENCHMARK_ENV_NAME']
    }

    if 'AWS_PROFILE' in os.environ:
        cdk_command = "cdk destroy --force --color=always --profile " + os.environ['AWS_PROFILE']
        env_vars['AWS_PROFILE'] = os.environ['AWS_PROFILE']
    else:
        cdk_command = "cdk destroy --force --color=always"

    process = subprocess.Popen(cdk_command, shell=True, env=env_vars, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(process.stdout.read().decode('utf-8'))
    print(f"{bcolors.OKGREEN}{env['name']} cleaned up.{bcolors.ENDC}")
    print('-'*100)
