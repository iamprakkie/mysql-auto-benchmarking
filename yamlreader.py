import yaml
import os
import uuid
import subprocess

with open(os.path.join(os.path.dirname(__file__), 'env-config.yaml'), 'r') as f:
    config = yaml.load(f, Loader=yaml.Loader)

envs = config['environments']
    
for env in envs:
#     print("Region for {}: {}".format(env['name'], env['region']))
#     print("Instance type for {}: {}".format(env['name'], env['instancetype']))
#     print("Volume type for {}: {}".format(env['name'], env['volumetype'] if not env['instancetype'].startswith('r5b') else 'io2' ))
#     print("Volume size for {}: {}".format(env['name'], env['volumesize']))
#     print("autobenchconf for {}: {}".format(env['name'], env['autobenchconf']))
#     print("===================================================================")
    volType = env['volumetype'] if not env['instancetype'].startswith('r5b') else 'io2'
    if volType == 'gp2':
        iops = '0'
    else:
        iops = str(env['iops'])
    benchmarkName = "autobench-" + env['instancetype'].replace(".", "-") + "-" + volType + "-" + iops + "-" +str(uuid.uuid1())
    print(benchmarkName)

    env_vars = {
        'BENCHMARK_NAME': benchmarkName,
        'BENCHMARK_REGION': env['region'],
        'MYSQL_INST_TYPE': env['instancetype'],
        'MYSQL_VOL_SIZE': str(env['volumesize']),
        'MYSQL_VOL_IOPS': iops,
        'MYSQL_VOL_TYPE': volType,
        'MYSQL_AUTOBENCH_CONF': env['autobenchconf']
    }

    # cdk_command = ['./venv/bin/cdk', 'synth']
    cdk_command = ['env']

    process = subprocess.run(cdk_command, env=env_vars, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print(process.stdout.decode('utf-8'))



