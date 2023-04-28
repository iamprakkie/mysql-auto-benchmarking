#!/bin/python3

# This script is used to create env_vars files for every environment in the config file.
# The env_vars files are used to run the benchmarks.

import yaml
import os
import uuid
import subprocess
import sys

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

# Read environments config file
with open(os.path.join(os.path.dirname(__file__), configFileName), 'r') as f:
    config = yaml.load(f, Loader=yaml.Loader)

envs = config['environments']
    
for env in envs:
    print(f"{bcolors.HEADER}Working on environment: {env['name']}{bcolors.ENDC}")

    # Read env_vars file
    env_var_filename = env['name'].replace(' ', "-") + '.env_vars'

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

    cdk_command = "cdk destroy --force"

    process = subprocess.Popen(cdk_command, shell=True, env=env_vars, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(process.stdout.read().decode('utf-8'))
    print(f"{bcolors.OKGREEN}{env['name']} cleaned up.{bcolors.ENDC}")
