
# ==================================================================================================================================================================================================================================
#Actions
# Create ssh config for mysql instance
# Host 10.0.0.163
#         Hostname 10.0.0.163
#         IdentityFile /home/ssm-user/.ssh/MySQLKeyPair.pem
#         User ssm-user
# chmod 600 ~/.ssh/config

# create /home/ssm-user/bench/ndb in mysql instance
# ensure /home/ssm-user/bench/mysql has unzipped data of binary
# ndb.sh needs ssh -n -l ssm-user. also in oltp_run.sh. Rather try adding --user to start_ndb.sh call in /home/ssm-user/bench/sysbench/src/dbt2-0.37.50.16/scripts/mgm_cluster.sh. Also tried adding env USER=ssm-user
# SSH_USER=;NDB_USER

# try adding --user in mgm_cluster.sh of dbt2.tar.gz seems FIXES PROBLEM
# install numactl in dbt2 machine
# install mysql client in mysql instance as well
# NOT REQ. Set this in autobench.conf - create soft link at mysql instance sudo ln -s /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/lib/libmysqlclient.so.21 /usr/lib/libmysqlclient.so.21
# place sysbench targz in /home/ssm-user/bench/mysql


#Trial 
#cd /home/ssm-user/bench
#./bench_run.sh --default-directory /home/ssm-user/bench/sysbench --init --generate-dbt2-data --skip-run --verbose 2>&1 | tee output.log
# TRX_ENGINE="yes" in autobench.conf

#######
#./bench_run.sh --default-directory /home/ssm-user/bench/sysbench --init --generate-dbt2-data --start --skip-run --verbose 2>&1 | tee output.log
#######
#./bench_run.sh --default-directory /home/ssm-user/bench/sysbench --skip-start --verbose 2>&1 | tee output.log

#kill $(lsof -t -i:3316)
#installing gnuplot in dbt2 machine

https://severalnines.com/blog/how-benchmark-performance-mysql-mariadb-using-sysbench/

Executing /home/ssm-user/bench/sysbench/src/dbt2-0.37.50.16/scripts/run_oltp.sh --default-directory /home/ssm-user/bench/sysbench --benchmark sysbench --verbose --skip-run --skip-stop

/home/ssm-user/bench/sysbench/sysbench.conf

Executing /home/ssm-user/bench/sysbench/src/dbt2-0.37.50.16/scripts/mgm_cluster.sh --default-directory /home/ssm-user/bench/sysbench --start --initial --mysqld --cluster_id 1 --conf-file /home/ssm-user/bench/sysbench/dis_config_c1.ini --verbose

/home/ssm-user/bench/sysbench/src/dbt2-0.37.50.16/scripts/start_ndb.sh --default-directory /home/ssm-user/bench/sysbench --verbose --ssh_port 22 --cluster_id 1 --home-base /home/ssm-user --mysql_install_db --mysql_no 1 --mysql_port 3316 10.0.0.198

ssh -p 22 -n -l  10.0.0.198 '/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/bin/mysqld --no-defaults --initialize-insecure --init-file=/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/bin/init_file.sql --basedir=/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64 --datadir=/home/ssm-user/bench/ndb/var_1 --pid-file=/tmp/mysqld_1.pid --bind-address=127.0.0.1 --port=3316 --user= --socket=/home/ssm-user/bench/ndb/var_1/mysql_1.sock --lc-messages=en_US;'


ssh -p 22 -n -l ssm-user 10.0.0.198 'MYSQLD="";if test -f /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/bin/mysqld ; then  MYSQLD="numactl --interleave=all --physcpubind=2-21 /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/bin/mysqld";  MYSQLD_SUBDIR="/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/bin";fi;if test -f /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/sbin/mysqld ; then  MYSQLD="numactl --interleave=all --physcpubind=2-21 /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/sbin/mysqld";  MYSQLD_SUBDIR="/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/sbin";fi;if test -f /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/libexec/mysqld ; then  MYSQLD="numactl --interleave=all --physcpubind=2-21 /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/libexec/mysqld";  MYSQLD_SUBDIR="/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/libexec";fi;if test "x${MYSQLD}" = "x" ; then  echo "No mysqld binary in path";  exit 1;fi; echo "Using binary from ${MYSQLD}"; LANG=""; if test -d /home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/share/mysql ; then   LANG="/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/share/mysql"; else   LANG="/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64/share"; fi; echo "Using error messages from ${LANG}"; LANG="--lc-messages-dir=$LANG"; ulimit -c unlimited;  $MYSQLD --no-defaults   --secure-file-priv= --mysqlx=0 --character-set-server=latin1 --collation-server=latin1_swedish_ci --performance_schema=off --max_connections=1000 --max_prepared_stmt_count=1048576 --sort_buffer_size=524288 --socket=/home/ssm-user/bench/ndb/var_1/mysql_1.sock $LANG   --log-error=/home/ssm-user/bench/ndb/var_1/error.log --bind-address=10.0.0.198 --table_open_cache=4000 --table_definition_cache=4000 --table_open_cache_instances=64 --tmp_table_size=100M --max_heap_table_size=1000M --key_buffer_size=50M --server-id=1 --disable-log-bin --join_buffer_size=1000000  --tmpdir=/tmp --datadir=/home/ssm-user/bench/ndb/var_1 --basedir=/home/ssm-user/bench/mysql/mysql-cluster-8.0.32-el7-x86_64 --pid-file=/tmp/mysqld_1.pid --port=3316'&