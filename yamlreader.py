#!/bin/python3

# This script is used to create env_vars files for every environment in the config file.
# The env_vars files are used to run the benchmarks.

import yaml
import os
import uuid
import subprocess

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
    print(f"{bcolors.OKBLUE}Working on environment: {env['name']}{bcolors.ENDC}")
    # set iops for gp2    
    volType = env['volumetype'] if not env['instancetype'].startswith('r5b') else 'io2'
    if volType == 'gp2':
        iops = '0'
    else:
        iops = str(env['iops'])

    # Create benchmark name    
    benchmarkName = "autobench-" + env['instancetype'].replace(".", "-") + "-" + volType + "-" + iops + "-" +str(uuid.uuid1())[:8]
    print(f"\t{bcolors.OKORANGE}Benchmark name: {benchmarkName}{bcolors.ENDC}")

    # Create env export file for every environment
    os.makedirs(os.path.join(os.path.dirname(__file__), 'env_vars'), exist_ok=True)
    with open(os.path.join(os.path.dirname(__file__), 'env_vars', env['name'].replace(' ', "-")+'.env_vars'), 'w') as fw:
        fw.write('export BENCHMARK_NAME=' + benchmarkName + '\n')
        fw.write('export BENCHMARK_REGION=' + env['region'] + '\n')
        fw.write('export MYSQL_INST_TYPE=' + env['instancetype'] + '\n')
        fw.write('export MYSQL_VOL_SIZE=' + str(env['volumesize']) + '\n')
        fw.write('export MYSQL_VOL_IOPS=' + iops + '\n')
        fw.write('export MYSQL_VOL_TYPE=' + volType + '\n')
        fw.write('export MYSQL_AUTOBENCH_CONF=' + env['autobenchconf'] + '\n')
        fw.write('export BENCHMARK_ENV_NAME="' + env['name'] + '"\n')
    
    # Close the file
    fw.close()
    print(f"\t{bcolors.OKORANGE}env_vars file: {fw.name}{bcolors.ENDC}")

    env_vars = {
        'PATH': os.environ['PATH'],
        'BENCHMARK_NAME': str(benchmarkName),
        'BENCHMARK_REGION': str(env['region']),
        'MYSQL_INST_TYPE': str(env['instancetype']),
        'MYSQL_VOL_SIZE': str(env['volumesize']),
        'MYSQL_VOL_IOPS': iops,
        'MYSQL_VOL_TYPE': volType,
        'MYSQL_AUTOBENCH_CONF': str(env['autobenchconf']),
        'BENCHMARK_ENV_NAME': str(env['name'])
    }

    # cdk_command = "cdk diff"
    cdk_command = "cdk deploy --require-approval never"

    process = subprocess.run(cdk_command, shell=True, env=env_vars, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(process.stdout.decode('utf-8'))
    if process.returncode != 0:
        print(f"\t{bcolors.FAIL}PROCESS RETURN CODE: ",process.returncode,{bcolors.ENDC})
        exit("ERROR",process.returncode)



