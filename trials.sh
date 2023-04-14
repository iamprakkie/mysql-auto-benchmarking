#Actions
# Create ssh config for mysql instance
# Host 10.0.0.163
#         Hostname 10.0.0.163
#         IdentityFile /home/ssm-user/.ssh/MySQLKeyPair.pem
#         User ssm-user
# chmod 600 ~/.ssh/config

# create /home/ssm-user/bench/ndb in mysql instance

#Trial commands
./bench_run.sh --default-directory /home/ssm-user/bench/sysbench --init --generate-dbt2-data --skip-run --verbose