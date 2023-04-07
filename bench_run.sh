#!/bin/bash
# ----------------------------------------------------------------------
# Copyright (C) 2007 iClaustron  AB
#   2008, 2019 Oracle Oracle and/or its affiliaties. All rights reserved.
# ----------------------------------------------------------------------
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; only version 2 of the License
#
# The GPL License is only valid with the above copyright notice retained.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

usage()
{
  cat <<EOF
  This program runs an automated benchmark with either sysbench or
  DBT2. It is driven by a configuration file autobench.conf which
  must be placed in the directory specified by the parameter
  --default-directory which is a mandatory parameter. The
  sysbench tarball, the MySQL tarball and the tarball with the
  scripts needed to run the test in the DBT2 tarball must be
  placed in the directory specified by the variable TARBALL_DIR in
  the autobench.conf file.

  There are 5 stages in this execution:
  1) Build the MySQL, sysbench and/or DBT2 tarballs locally and remotely
  2) Generate internal and external config files
  3) Start MySQL Cluster
  4) Run benchmark
  5) Stop MySQL Cluster
  6) Cleanup after test
  
  The default behaviour is to skip 1), 2), 3), 5) and 6). So by default we
  only run the benchmark.
  Normally one uses --init first time which enables phase 1), 2) and 3). 5)
  and 6) are still disabled.
  Phase 5) (stop) is only executed when --stop flag is provided.
  Phase 6) (cleanup) is only executed when --cleanup is provided
  Phase 4) (run) is always executed unless --skip-run is provided
  Phase 3) (start) is executed only if --init or --start is provided
           unless --skip-start is provided after --init
  Phase 2) (generate) is executed only if --init or --generate is provided
  Phase 1) (build) is executed only --init or --build is provided
           There are also parameters to build partial builds.

  Parameters:
  -----------
  --default-directory     : Directory where autobench.conf is placed, this
                            directory is also used to place builds, results
                            and other temporary storage needed to run the
                            test.
  --init                  : Perform the build phase and generate phase
  --build                 : Perform the build phase
  --build-mysql           : Build MySQL
  --build-remote          : Build also on remote hosts
  --windows-remote        : Build on remote Windows servers
  --generate              : Generate config files internal and external
  --start                 : Start cluster
  --start-no-initial      : Start cluster without initialising data
  --stop                  : Stop cluster
  --skip-run              : Don't run benchmark
  --skip-start            : Don't start up cluster
  --cleanup               : Perform cleanup
  --skip-init-innodb      : Skip initial InnoDB benchmark (only applicable when InnoDB is used)
  --skip-load-dbt2        : Assume DBT2 data is already loaded into cluster, so skip load phase
  --skip-generate-config-ini : Skip generating config.ini file
  --sysbench-instances    : Run this many parallel sysbench programs
  --generate-dbt2-data    : Generate load files for DBT2 benchmark, can only
                            be done in conjunction with build locally
  --kill-nodes            : Kill all nodes in the cluster after running
                            flexAsynch benchmark that failed in the middle
  --verbose               : Generate verbose output
EOF
}

check_support_programs()
{
  TAR=`which gtar`
  if test "x$?" != "x0" ; then
    TAR=`which tar`
  fi
  MAKE=`which gmake`
  if test "x$?" != "x0" ; then
    MAKE=`which make`
  fi
}

#Ensure all messages are sent both to the log file and to the terminal
msg_to_log()
{
  if test "x$LOG_FILE" != "x" ; then
    ${ECHO} "$MSG" >> ${LOG_FILE}
    if test "x$?" != "x0" ; then
      ${ECHO} "Failed to write to ${LOG_FILE}"
      exit 1
    fi
  fi
}

#Method used to write any output to log what script is doing
output_msg()
{
  ${ECHO} "$MSG"
  msg_to_log
}

#Method to execute any command and verify command was a success
#If PIPE_FILE is set we're doing it as background task
exec_command()
{
  if test "x$PIPE_FILE" = "x" ; then
    MSG="Executing $*"
    output_msg
    eval $*
  else
    LOC_CMD="$* >> ${PIPE_FILE} &"
    MSG="Executing $LOC_CMD"
    output_msg
    eval $LOC_CMD
  fi
  if test "x$?" != "x0" ; then
    MSG="Failed command $*"
    output_msg
    exit 1
  fi
}

create_dir()
{
  if ! test -d $CREATE_DIR ; then
    ${MKDIR} -p $CREATE_DIR
    if ! test -d $CREATE_DIR ; then
      if test "x$LOG_FILE_CREATED" = "xyes" ; then
        MSG="Failed to create $CREATE_DIR"
        output_msg
      else
        ${ECHO} "Failed to create $CREATE_DIR"
      fi
      exit 1
    fi
    if test "x$LOG_FILE_CREATED" = "xyes" ; then
      MSG="Successfully created $CREATE_DIR"
      output_msg
    else
      ${ECHO} "Successfully created $CREATE_DIR"
    fi
  fi
}

create_data_dir_in_all_nodes()
{
  for NODE in ${REMOTE_NODES}
  do
    create_remote_data_dir_base ${NODE}
  done
}

create_dirs()
{
  CREATE_DIR="${SRC_INSTALL_DIR}"
  create_dir
  CREATE_DIR="${BIN_INSTALL_DIR}"
  create_dir
  CREATE_DIR="${BIN_INSTALL_DIR}/bin"
  create_dir
}

# $1 is the node specification to which we are setting up SSH towards
setup_ssh_node()
{
  SSH_NODE="${1}"
  if test "x${SSH_USER}" = "x" ; then
    SSH_USER_HOST="${SSH_NODE}"
  else
    SSH_USER_HOST="${SSH_USER}@${SSH_NODE}"
  fi
  SSH_CMD="${SSH} -p ${SSH_PORT} ${SSH_USER_HOST}"
}

exec_ssh_command()
{
  LOCAL_CMD="$*"
  if test "x${SSH_NODE}" != "xlocalhost" && \
     test "x${SSH_NODE}" != "x127.0.0.1" ; then
    setup_ssh_node ${SSH_NODE}
    MSG="Executing $SSH_CMD '$LOCAL_CMD'"
    output_msg
    LOCAL_CMD="$SSH_CMD '$LOCAL_CMD'"
    eval $LOCAL_CMD
    if test "x$?" != "x0" && test "x$IGNORE_FAILURE" != "xyes"; then
      MSG="Failed command $*"
      output_msg
      exit 1
    fi
  else
    exec_command ${LOCAL_CMD}
  fi
}

create_remote_data_dir_base()
{
  SSH_NODE="${1}"
  echo "Create data dir on node $SSH_NODE"
  LOCAL_CMD="$CD $DATA_DIR_BASE; $MKDIR -p ndbd; mkdir -p ndb_mgmd; mkdir -p mysql-cluster"
  exec_ssh_command $LOCAL_CMD
}

unpack_tarball()
{
  TARBALL_NAME="$1"
  COMMAND="${CP} ${TARBALL_DIR}/${TARBALL_NAME}.tar.gz"
  COMMAND="${COMMAND} ${TARBALL_NAME}.tar.gz"
  exec_command ${COMMAND}
  COMMAND="${TAR} xfz ${TARBALL_NAME}.tar.gz"
  exec_command ${COMMAND}
  COMMAND="${RM} ${TARBALL_NAME}.tar.gz"
  exec_command ${COMMAND}
}

init_tarball_variables()
{
  if test "x${WINDOWS_REMOTE}" != "xyes" ; then
    if test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
      MYSQL_TARBALL="${MYSQL_VERSION}_binary.tar.gz"
    fi
    if test "x$PERFORM_BUILD_BENCH" = "xyes" ; then
      SYSBENCH_TARBALL="${SYSBENCH_VERSION}_binary.tar.gz"
    fi
  fi
}

unpack_bench_tarballs()
{
  CREATE_DIR="${SRC_INSTALL_DIR}"
  create_dir
  exec_command ${CD} ${SRC_INSTALL_DIR}
  if test "x$PERFORM_BUILD_BENCH" = "xyes" ; then
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      RMDIR="${SRC_INSTALL_DIR}/${SYSBENCH_VERSION}"
      exec_command ${RM} -rf ${RMDIR}
      unpack_tarball ${SYSBENCH_VERSION}
    fi
  fi
  RMDIR="${SRC_INSTALL_DIR}/${DBT2_VERSION}"
  exec_command ${RM} -rf ${RMDIR}
  unpack_tarball ${DBT2_VERSION}
  exec_command ${CD} ${DEFAULT_DIR}
}

#Unpack the source tarballs into the SRC_INSTALL_DIR
unpack_tarballs()
{
  CREATE_DIR="${SRC_INSTALL_DIR}"
  create_dir
  exec_command ${CD} ${SRC_INSTALL_DIR}
  if test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
    if test "x$USE_BINARY_MYSQL_TARBALL" = "xno" ; then
      RMDIR="${SRC_INSTALL_DIR}/${MYSQL_VERSION}"
      exec_command ${RM} -rf ${RMDIR}
      unpack_tarball ${MYSQL_VERSION}
    fi
  fi
  unpack_bench_tarballs
}

execute_build()
{
  BUILD_VERSION="$1"
  exec_command ${CD} ${SRC_INSTALL_DIR}/${BUILD_VERSION}
  exec_command ${COMMAND}
  exec_command ${MAKE} -j 8
  exec_command ${MAKE} install
  MSG="Successfully built and installed ${BUILD_VERSION}"
  output_msg
}

fix_origin()
{
  ${CAT} ${MYSQL_DIR}/bin/mysql_config | \
    ${SED} -e "s,-R['\\\$]*ORIGIN[/.]*lib[']*,," > ${MYSQL_DIR}/tmp_12345
  ${CP} ${MYSQL_DIR}/tmp_12345 ${MYSQL_DIR}/bin/mysql_config
  ${RM} ${MYSQL_DIR}/tmp_12345
}

set_up_init_file()
{
  if test "x$PERFORM_INIT" = "xyes" ; then
    if test "x${PERFORM_BUILD_MYSQL}" = "xyes" ; then
      exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/init_file.sql $MYSQL_INSTALL_DIR/bin/.
    fi
  fi
}

build_mysql()
{
  MSG="Building from source MySQL version: ${MYSQL_VERSION}"
  output_msg

  CREATE_DIR=${MYSQL_INSTALL_DIR}
  create_dir

  exec_command ${CD} ${SRC_INSTALL_DIR}/${MYSQL_VERSION}
  exec_command mkdir -p ${SRC_INSTALL_DIR}/${MYSQL_VERSION}/BUILD
  if test "x$DEBUG_FLAG" = "xyes" ; then
    DEBUG_FLAG="--debug"
  else
    DEBUG_FLAG=
  fi
  if test "x$COMPILER_PARALLELISM" != "x" ; then
    COMPILER_PARALLELISM="--parallelism ${COMPILER_PARALLELISM}"
  fi
  if test "x$USE_DBT2_BUILD" = "xyes" ||
     ! test -f BUILD/build_mccge.sh || \
     ! test -f BUILD/check-cpu ; then
    exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/build_mccge.sh BUILD/.
    exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/check-cpu BUILD/.
  fi
  if test "x$MYSQL_BASE" = "x8.0" ; then
    exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/cmake_configure.sh BUILD/.
    exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/configure.pl cmake/.
  fi
  exec_command BUILD/build_mccge.sh --prefix=${MYSQL_INSTALL_DIR} \
                                  ${WITH_DEBUG} \
                                  ${COMPILER_PARALLELISM} \
                                  ${DEBUG_FLAG} \
                                  ${PACKAGE} \
                                  ${FAST_FLAG} \
                                  ${COMPILER_FLAG} \
                                  ${LINK_TIME_OPTIMIZER_FLAG} \
                                  ${MSO_FLAG} \
                                  ${COMPILE_SIZE_FLAG} \
                                  ${WITH_PERFSCHEMA_FLAG} \
                                  ${FEEDBACK_FLAG} \
                                  ${WITH_NDB_TEST_FLAG}
  exec_command cd BUILD
  exec_command ${MAKE} install
  exec_command cd ..
  exec_command $CP $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/init_file.sql $MYSQL_INSTALL_DIR/bin/.
  MSG="Successfully built and installed ${MYSQL_VERSION}"
  output_msg
}

prepare_feedback_build()
{
  build_mysql
  exec_command ${CP} ${MYSQL_INSTALL_DIR}/bin/ndbmtd ${DEFAULT_DIR}/ndbmtd_no_feedback
  FEEDBACK_PREPARED="yes"
  clean_up_local_src_mysql
  clean_up_local_bin
  create_dirs
  exec_command ${CD} ${SRC_INSTALL_DIR}
  unpack_tarball ${MYSQL_VERSION}
}

feedback_final_phase()
{
  if test "x$FEEDBACK_PREPARED" = "xyes" ; then
    exec_command ${CP} ${DEFAULT_DIR}/ndbmtd_no_feedback ${MYSQL_INSTALL_DIR}/bin/ndbmtd
    exec_command ${RM} ${DEFAULT_DIR}/ndbmtd_no_feedback
  fi
}

build_local()
{
  if test "x${MYSQL_VERSION}" != "x${CLIENT_MYSQL_VERSION}" ; then
    MYSQL_DIR="$MYSQL_BIN_INSTALL_DIR/$CLIENT_MYSQL_VERSION"
  else
    if test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
      MYSQL_DIR="$BIN_INSTALL_DIR/$MYSQL_VERSION"
    else
      MYSQL_DIR="$MYSQL_BIN_INSTALL_DIR/$MYSQL_VERSION"
    fi
  fi
  if test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
    if test "x$USE_BINARY_MYSQL_TARBALL" = "xyes" ; then
      MSG="Building from binary MySQL version: ${MYSQL_VERSION}"
      output_msg
      exec_command ${CD} ${BIN_INSTALL_DIR}
      unpack_tarball ${MYSQL_VERSION}
      exec_command ${CP} $SRC_INSTALL_DIR/$DBT2_VERSION/scripts/init_file.sql ${BIN_INSTALL_DIR}/bin/.
    else
      build_mysql
    fi
    exec_command ${CD} ${DEFAULT_DIR}
    fix_origin
  fi
  if test "x$PERFORM_BUILD_BENCH" = "xyes" ; then
    unpack_bench_tarballs
    if test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
      MSG="Building DBT2 version: ${DBT2_VERSION}"
      output_msg
      exec_command cd ${SRC_INSTALL_DIR}/${DBT2_VERSION}
      exec_command ./configure --with-mysql=${MYSQL_DIR}
      exec_command ${MAKE} 
    fi
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      exec_command ${CD} ${DEFAULT_DIR}
      CREATE_DIR=${BIN_INSTALL_DIR}/${SYSBENCH_VERSION}
      SYSBENCH_INSTALL_DIR=${CREATE_DIR}
      create_dir
      CREATE_DIR=${SRC_INSTALL_DIR}/${SYSBENCH_VERSION}
      create_dir
      exec_command ${CD} ${SRC_INSTALL_DIR}
      exec_command ${RM} -rf ${SYSBENCH_VERSION}
      unpack_tarball ${SYSBENCH_VERSION}
      exec_command ${CD} ${SYSBENCH_VERSION}
      MSG="Building sysbench"
      output_msg
      COMMAND=
      if test "x$SB_SYSBENCH_64BIT_BUILD" = "xyes"; then
        COMMAND1='CFLAGS="-g -O2 -m64" '
        COMMAND2='CXXFLAGS="-g -O2 -m64" '
        COMMAND3='LDFLAGS="-m64" '
        COMMAND="$COMMAND1 $COMMAND2 $COMMAND3"
      fi
      COMMAND="$COMMAND ./configure --with-mysql=${MYSQL_DIR}"
      COMMAND="${COMMAND} --prefix=${SYSBENCH_INSTALL_DIR} ${WITH_DEBUG}"
      if test "x$FEEDBACK_COMPILATION" = "xyes" ; then
        COMMAND="$COMMAND --with-extra-ldflags=-lgcov"
      else
        COMMAND="$COMMAND --with-extra-ldflags=-all-static"
      fi
      execute_build ${SYSBENCH_VERSION}
    fi
  fi
  exec_command ${CD} ${DEFAULT_DIR}
}

create_binary_tarballs()
{
#
# Now that we've successfully built the MySQL source code and a potential
# DBT2 source code we'll create compressed tar-files of the binaries for later
# distribution to other dependent nodes, sysbench and DBT2 will always run on
# the client, so no need to build sysbench binaries for distribution.
#
  if test "x${WINDOWS_REMOTE}" != "xyes" ; then
# Verify that pwd works before using it
    exec_command ${CD} ${BIN_INSTALL_DIR}
    MSG="Create compressed tar files of the installed binaries"
    output_msg
    if test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
      COMMAND="${TAR} cfz ${MYSQL_TARBALL} ${MYSQL_VERSION}"
      exec_command ${COMMAND}
    fi
    if test "x$PERFORM_BUILD_BENCH" = "xyes" ; then
      if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
        COMMAND="${TAR} cfz ${SYSBENCH_TARBALL} ${SYSBENCH_VERSION}"
        exec_command ${COMMAND}
      fi
    fi
  fi
}

# $1 contains the NODE specification where to install the binaries
remote_install_binaries()
{
  LOCAL_NODE="$1"
  LOCAL_DIR="$MYSQL_BIN_INSTALL_DIR"

  MSG="Install binaries at $LOCAL_NODE in directory $LOCAL_DIR"
  output_msg

  if test "x$MYSQL_TARBALL" != "x" && \
     test "x$PERFORM_BUILD_MYSQL" = "xyes" ; then
    install_one_remote_binary ${MYSQL_TARBALL} ${MYSQL_VERSION}
  fi
  if test "x$PERFORM_BUILD_BENCH" = "xyes" ; then
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      install_one_remote_binary ${SYSBENCH_TARBALL} ${SYSBENCH_VERSION}
    fi
  fi
  remove_remote_binary_tar_files ${LOCAL_NODE}
}

remove_local_binary_tar_files()
{
  if test "x${MYSQL_TARBALL}" != "x" ; then
    MSG="Remove tar files with binaries"
    output_msg
    exec_command ${RM} ${BIN_INSTALL_DIR}/${MYSQL_TARBALL}
  fi
  if test "x${SYSBENCH_TARBALL}" != "x" ; then
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      exec_command ${RM} ${BIN_INSTALL_DIR}/${SYSBENCH_TARBALL}
    fi
  fi
}

init_clean_up()
{
  SSH_NODE="$1"
  if test "x${USE_DOCKER}" = "xyes" ; then
    exec_ssh_command sudo rm -rf ${DATA_DIR_BASE}/*
  else
    exec_ssh_command rm -rf ${DATA_DIR_BASE}/ndb
    exec_ssh_command rm -rf ${DATA_DIR_BASE}/ndbd
    exec_ssh_command rm -rf ${DATA_DIR_BASE}/ndb_mgmd
    exec_ssh_command rm -rf ${DATA_DIR_BASE}/mysql-cluster
    exec_ssh_command rm -rf ${DATA_DIR_BASE}/var*
  fi
}

clean_up_local_bin()
{
  exec_command ${RM} -rf ${BIN_INSTALL_DIR}
}

clean_up_remote_bin()
{
  SSH_NODE="$1"
  COMMAND="cd ${MYSQL_BIN_INSTALL_DIR} &&"
  COMMAND="${COMMAND} rm -rf ${MYSQL_VERSION}"
  exec_ssh_command $COMMAND
  init_clean_up ${SSH_NODE}
}

clean_up_local_src()
{
  exec_command ${RM} -rf ${SRC_INSTALL_DIR}
}

clean_up_local_src_mysql()
{
  exec_command ${RM} -rf ${SRC_INSTALL_DIR}/${MYSQL_VERSION}
}

clean_up_local_src_sysbench()
{
  exec_command ${RM} -rf ${SRC_INSTALL_DIR}/${SYSBENCH_VERSION}
}

build_mysql_binaries()
{
  MYSQL_INSTALL_DIR=${BIN_INSTALL_DIR}/${MYSQL_VERSION}
  if test "x${PERFORM_BUILD_LOCAL}" = "xyes" ; then
    if test "x${PERFORM_BUILD_MYSQL}" = "xyes" ; then
      export WITH_NDB_JAVA_DEFAULT="0"
      export WITH_NDB_NODEJS_DEFAULT="0"
      if test "x$BOOST_VERSION" = "x" ; then
        if test "x$MYSQL_BASE" = "x8.0" ; then
          BOOST_VERSION="boost_1_72_0"
        else
          BOOST_VERSION="boost_1_59_0"
        fi
      fi
      export BOOST_ROOT="${TARBALL_DIR}/${BOOST_VERSION}"
      MYSQL_INSTALL_DIR=${BIN_INSTALL_DIR}/${MYSQL_VERSION}
      unpack_tarballs
      if test "x${FEEDBACK_COMPILATION}" = "xyes" && \
         test "x${USE_BINARY_MYSQL_TARBALL}" = "xno" ; then
        prepare_feedback_build
        FEEDBACK_FLAG="--generate-feedback $DEFAULT_DIR/feedback_dir"
        build_local
        create_binary_tarballs
        remote_install_binaries ${FIRST_SERVER_HOST}
        remove_local_binary_tar_files
        exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
             --default-directory ${DEFAULT_DIR} \
             --benchmark sysbench --skip-run --only-initial ${SKIP_INITIAL}
        FEEDBACK_FLAG="--use-feedback $DEFAULT_DIR/feedback_dir"
        for NODE in ${REMOTE_NODES}
        do
          init_clean_up ${NODE}
        done
        clean_up_local_bin
        clean_up_remote_bin ${FIRST_SERVER_HOST}
        clean_up_local_src_mysql
        clean_up_local_src_sysbench
        create_dirs
        unpack_tarballs
        build_local
        feedback_final_phase
      else
        build_local
      fi
    else
      MYSQL_DIR="$MYSQL_BIN_INSTALL_DIR"
      build_local
    fi
  else
    unpack_tarballs
  fi
}

create_remote_src()
{
  SSH_NODE="${LOCAL_NODE}"
  exec_ssh_command $MKDIR -p ${LOCAL_DIR}
}

remote_copy()
{
  COPY_VERSION="$1"
  if test "x${LOCAL_NODE}" != "xlocalhost" && \
     test "x${LOCAL_NODE}" != "x127.0.0.1" ; then
    COMMAND="${SCP} -P $SSH_PORT ${TARBALL_DIR}/${COPY_VERSION}.tar.gz"
    if test "x${SSH_USER}" = "x" ; then
      COMMAND="$COMMAND ${LOCAL_NODE}:${LOCAL_DIR}"
    else
      COMMAND="$COMMAND ${SSH_USER}@${LOCAL_NODE}:${LOCAL_DIR}"
    fi
    exec_command $COMMAND
  else
    exec_command ${CP} ${TARBALL_DIR}/${COPY_VERSION}.tar.gz ${LOCAL_DIR}
  fi
}

build_remote_unix()
{
  LOCAL_NODE="$1"
  SSH_NODE="$LOCAL_NODE"
  LOCAL_DIR="$REMOTE_SRC_INSTALL_DIR"
  if test "x$REMOTE_SRC_INSTALL_DIR" = "x" ; then
    MSG="REMOTE_SRC_INSTALL_DIR is mandatory to set"
    output_msg
    exit 1
  fi
  MSG="Build binaries at $LOCAL_NODE in directory $LOCAL_DIR"
  output_msg

  create_remote_src

  remote_copy ${MYSQL_VERSION}

  if test "x${USE_FAST_MYSQL}" = "xyes" ; then
    FAST_FLAG="--fast"
  else
    FAST_FLAG=""
  fi
 
# Generate build command on remote Unix machine
  SSH_NODE="$LOCAL_NODE"
  COMMAND="cd $LOCAL_DIR &&"
  COMMAND="${COMMAND} mkdir -p ${TMP_BASE} &&"
  COMMAND="${COMMAND} rm -rf ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} gtar xfz ${MYSQL_VERSION}.tar.gz &&"
  COMMAND="${COMMAND} rm ${MYSQL_VERSION}.tar.gz &&"
  COMMAND="${COMMAND} cd ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} export WITH_NDB_JAVA_DEFAULT=0 &&"
  COMMAND="${COMMAND} export WITH_NDB_NODEJS_DEFAULT=0 &&"
  COMMAND="${COMMAND} BUILD/build_mccge.sh"
  COMMAND="${COMMAND} --prefix=${MYSQL_BIN_INSTALL_DIR}/${MYSQL_VERSION}"
  COMMAND="${COMMAND} ${WITH_DEBUG}"
  COMMAND="${COMMAND} ${FAST_FLAG}"
  COMMAND="${COMMAND} ${COMPILER_FLAG}"
  COMMAND="${COMMAND} ${LINK_TIME_OPTIMIZER_FLAG}"
  COMMAND="${COMMAND} ${MSO_FLAG}"
  COMMAND="${COMMAND} ${COMPILE_SIZE_FLAG}"
  COMMAND="${COMMAND} ${WITH_PERFSCHEMA_FLAG}"
  COMMAND="${COMMAND} ${PACKAGE}"
  COMMAND="${COMMAND} ${WITH_NDB_TEST_FLAG} &&"
  if test "x$PERFORM_CLEANUP" = "xyes" ; then
    COMMAND="${COMMAND} gmake install &&"
    COMMAND="${COMMAND} rm -rf ${LOCAL_DIR}/${MYSQL_VERSION}"
  else
    COMMAND="${COMMAND} gmake install"
  fi
  exec_ssh_command ${COMMAND}
  return 0
}

# $1 contains the NODE specification where to install the binaries
build_remote_windows()
{
  LOCAL_NODE="$1"
  LOCAL_DIR="$REMOTE_SRC_INSTALL_DIR"
  if test "x$REMOTE_SRC_INSTALL_DIR" = "x" ; then
    MSG="REMOTE_SRC_INSTALL_DIR is mandatory to set on Windows"
    output_msg
    exit 1
  fi
  MSG="Build binaries at $LOCAL_NODE in directory $LOCAL_DIR"
  output_msg

  create_remote_src
  remote_copy ${MYSQL_VERSION}

#Replace ; by spaces in CMAKE Generator
  CMAKE_GENERATOR=`${ECHO} ${CMAKE_GENERATOR} | ${SED} -e 's!\;! !g'`
# Generate build command on Windows
  COMMAND="cd $LOCAL_DIR &&"
  COMMAND="${COMMAND} mkdir -p ${TMP_BASE} &&"
  COMMAND="${COMMAND} rm -rf ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} tar xfz ${MYSQL_VERSION}.tar.gz &&"
  COMMAND="${COMMAND} rm ${MYSQL_VERSION}.tar.gz &&"
  COMMAND="${COMMAND} cd ${MYSQL_VERSION} &&"

  COMMAND="${COMMAND} cscript win/configure.js"
  COMMAND="${COMMAND} WITH_INNOBASE_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_PARTITION_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_ARCHIVE_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_BLACKHOLE_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_EXAMPLE_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_FEDERATED_STORAGE_ENGINE"
  COMMAND="${COMMAND} WITH_NDBCLUSTER_STORAGE_ENGINE"
  COMMAND="${COMMAND} __NT__"
  COMMAND="${COMMAND} \"COMPILATION_COMMENT=${MYSQL_VERSION}\" &&"

  COMMAND="${COMMAND} cmake -G \"${CMAKE_GENERATOR}\" &&"
  COMMAND="${COMMAND} devenv.com mysql.sln /Build Release &&"
  COMMAND="${COMMAND} scripts/make_win_bin_dist ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} cp ${MYSQL_VERSION}.zip ${MYSQL_BIN_INSTALL_DIR} &&"
  COMMAND="${COMMAND} cd ..; rm -rf ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} cd ${MYSQL_BIN_INSTALL_DIR} &&"
  COMMAND="${COMMAND} rm -rf ${MYSQL_VERSION} &&"
  COMMAND="${COMMAND} unzip ${MYSQL_VERSION}.zip &&"
  COMMAND="${COMMAND} rm ${MYSQL_VERSION}.zip"
  SSH_NODE="${LOCAL_NODE}"
  exec_ssh_command ${COMMAND}
}

install_one_remote_binary()
{
  TARBALL_NAME="$1"
  TARBALL_VERSION="$2"
  SSH_NODE="${LOCAL_NODE}"
  exec_ssh_command $MKDIR -p ${LOCAL_DIR}

  exec_command cd $BIN_INSTALL_DIR
  if test "x${LOCAL_NODE}" != "xlocalhost" && \
     test "x${LOCAL_NODE}" != "x127.0.0.1" ; then
    COMMAND="${SCP} -P $SSH_PORT $TARBALL_NAME"
    COMMAND="$COMMAND ${SSH_USER_HOST}:${LOCAL_DIR}"
  else
    COMMAND="${CP} ${TARBALL_NAME} ${LOCAL_DIR}"
  fi
  exec_command $COMMAND

# Remove directory to avoid mixing old and new data
  COMMAND="cd ${LOCAL_DIR}; rm -rf ${TARBALL_VERSION}"
  SSH_NODE="${LOCAL_NODE}"
  exec_ssh_command $COMMAND

  COMMAND="$TAR xfz ${LOCAL_DIR}/${TARBALL_NAME} -C ${LOCAL_DIR}"
  SSH_NODE="${LOCAL_NODE}"
  exec_ssh_command $COMMAND
}

# $1 is the node specification where to remove remote tarballs
remove_remote_binary_tar_files()
{
  LOCAL_NODE="$1"
  MSG="Remove remote tar files with binaries"
  output_msg
  SSH_NODE="${LOCAL_NODE}"
  if test "x$MYSQL_TARBALL" != "x" ; then
    exec_ssh_command rm ${MYSQL_BIN_INSTALL_DIR}/${MYSQL_TARBALL}
  fi
  if test "x$SYSBENCH_TARBALL" != "x" ; then
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      exec_ssh_command rm ${MYSQL_BIN_INSTALL_DIR}/${SYSBENCH_TARBALL}
    fi
  fi
}

handle_remote_build()
{
  if test "x${PERFORM_BUILD_REMOTE}" = "xyes" ; then
    if test "x${WINDOWS_REMOTE}" = "xyes" ; then
      for NODE in ${REMOTE_NODES}
      do
        build_remote_windows ${NODE}
      done
    elif test "x${BUILD_REMOTE}" = "xyes" ; then
      for NODE in ${REMOTE_NODES}
      do
        build_remote_unix ${NODE}
      done
    else
      create_binary_tarballs
      for NODE in ${REMOTE_NODES}
      do
        remote_install_binaries ${NODE}
      done
      remove_local_binary_tar_files
    fi
  fi
}

set_compiler_flags()
{
#   Compiler directives, which compiler to use and which optimizations
  if test "x${USE_FAST_MYSQL}" = "xyes" ; then
    FAST_FLAG="--fast"
  fi
  if test "x${LINK_TIME_OPTIMIZER_FLAG}" = "xyes" ; then
    LINK_TIME_OPTIMIZER_FLAG="--with-link-time-optimizer"
  fi
  if test "x$COMPILER" != "x" ; then
    COMPILER_FLAG="--compiler=$COMPILER"
  fi
  if test "x$MSO_FLAG" = "xyes" ; then
    MSO_FLAG="--with-mso"
  else
    MSO_FLAG=
  fi
  if test "x$WITH_PERFSCHEMA_FLAG" = "xno" ; then
    if test "x$MYSQL_BASE" = "x5.1" ; then
      WITH_PERFSCHEMA_FLAG=
    else
      WITH_PERFSCHEMA_FLAG="--without-perfschema"
    fi
  else
    WITH_PERFSCHEMA_FLAG=
  fi
  if test "x$ENGINE" != "xndb" ; then
    PACKAGE="--package=pro"
  fi
  if test "x$BENCHMARK_TO_RUN" = "xflexAsynch" ; then
    WITH_NDB_TEST_FLAG="--with-flags --with-ndb-test"
  fi
  if test "x$COMPILE_SIZE_FLAG" = "x32" ; then
    COMPILE_SIZE_FLAG="--32"
  elif test "x$COMPILE_SIZE_FLAG" = "x64" ; then
    COMPILE_SIZE_FLAG="--64"
  else
    COMPILE_SIZE_FLAG=
  fi
}

read_autobench_conf()
{
  if test "x${CONFIG_FILE}" = "x" ; then
    ${ECHO} "No autobench.conf provided, cannot continue"
    exit 1
  fi
  ${ECHO} "Sourcing defaults from ${CONFIG_FILE}"
  . ${CONFIG_FILE}
}

write_conf()
{
  if test "x${VERBOSE}" = "xyes" ; then
    ${ECHO} "$*"
  fi
  ${ECHO} "$*" >> ${CONF_FILE}
  if test "x$?" != "x0" ; then
    ${ECHO} "Failed to write $* to ${CONF_FILE}"
    exit 1
  fi
}

remove_generated_files()
{
  CONF_FILE="${DEFAULT_DIR}/iclaustron.conf"
  exec_command ${RM} ${CONF_FILE}

  CONF_FILE="${DEFAULT_DIR}/dbt2.conf"
  exec_command ${RM} ${CONF_FILE}

  if test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
    CONF_FILE="${DEFAULT_DIR}/dbt2_run_1.conf"
    exec_command ${RM} ${CONF_FILE}
  fi

  if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
    CONF_FILE="${DEFAULT_DIR}/sysbench.conf"
    exec_command ${RM} ${CONF_FILE}
  fi

  CONF_FILE="${DEFAULT_DIR}/dis_config_c1.ini"
  exec_command ${RM} ${CONF_FILE}
}

write_iclaustron_conf()
{
  MSG="Writing iclaustron.conf"
  output_msg
  CONF_FILE="${DEFAULT_DIR}/iclaustron.conf"
  ${ECHO} "#iClaustron configuration file used to drive start/stop of MySQL programs" \
          > ${CONF_FILE}
  write_conf "MYSQL_SERVER_PATH=\"${MYSQL_BIN_INSTALL_DIR}/${MYSQL_SERVER_VERSION}\""
  write_conf "MYSQL_NDB_PATH=\"${MYSQL_BIN_INSTALL_DIR}/${MYSQL_NDB_VERSION}\""
  if test "x$DATA_DIR_BASE" = "x" ; then
    write_conf "DATA_DIR_BASE=\"${DEFAULT_DIR}/data\""
  else
    write_conf "DATA_DIR_BASE=\"${DATA_DIR_BASE}\""
  fi
  if test "x$MALLOC_LIB" != "x" ; then
    write_conf "MALLOC_LIB=\"${MALLOC_LIB}\""
  fi
  if test "x$SUPERSOCKET_LIB" != "x" ; then
    write_conf "SUPERSOCKET_LIB=\"${SUPERSOCKET_LIB}\""
  fi
  if test "x$INFINIBAND_LIB" != "x" ; then
    write_conf "INFINIBAND_LIB=\"${INFINIBAND_LIB}\""
  fi
  if test "x$PERFSCHEMA_FLAG" = "xyes" ; then
    if test "x$MYSQL_SERVER_BASE" = "x5.6" || \
       test "x$MYSQL_SERVER_BASE" = "x5.7" || \
       test "x$MYSQL_SERVER_BASE" = "x8.0" ; then
      write_conf "PERFSCHEMA_FLAG=\"--performance_schema --performance_schema_instrument='%=on'\""
    else
      write_conf "PERFSCHEMA_FLAG=\"--performance_schema\""
    fi
  else
    if test "x$MYSQL_SERVER_BASE" = "x5.6" || \
       test "x$MYSQL_SERVER_BASE" = "x5.7" || \
       test "x$MYSQL_SERVER_BASE" = "x8.0" ; then
      write_conf "PERFSCHEMA_FLAG=\"--performance_schema=off\""
    fi
  fi
  if test "x$WINDOWS_REMOTE" = "xyes" ; then
    write_conf "WINDOWS_INSTALL=\"yes\""
  fi
  write_conf "NDB_INDEX_STAT_ENABLE=\"${NDB_INDEX_STAT_ENABLE}\""
  write_conf "USE_DOCKER=\"${USE_DOCKER}\""
  write_conf "USE_SUDO_DOCKER=\"${USE_SUDO_DOCKER}\""
  write_conf "USE_SELINUX=\"${USE_SELINUX}\""
  write_conf "NDB_USE_ROW_CHECKSUM=\"${NDB_USE_ROW_CHECKSUM}\""
  write_conf "CLUSTER_HOME=\"${CLUSTER_HOME}\""
  write_conf "USE_INFINIBAND=\"${USE_INFINIBAND}\""
  write_conf "USE_SUPERSOCKET=\"${USE_SUPERSOCKET}\""
  write_conf "LOG_FILE=\"${LOG_FILE}\""
  write_conf "TMP_BASE=\"${TMP_BASE}\""
  write_conf "MYSQL_SERVER_BASE=\"${MYSQL_SERVER_BASE}\""
  write_conf "MYSQL_SERVER_BASE=\"${MYSQL_SERVER_BASE}\""
  write_conf "TRANSACTION_ISOLATION=\"${TRANSACTION_ISOLATION}\""
  write_conf "TABLE_CACHE_SIZE=\"${TABLE_CACHE_SIZE}\""
  write_conf "META_DATA_CACHE_SIZE=\"${META_DATA_CACHE_SIZE}\""
  write_conf "TABLE_CACHE_INSTANCES=\"${TABLE_CACHE_INSTANCES}\""
  write_conf "USE_LARGE_PAGES=\"${USE_LARGE_PAGES}\""
  write_conf "LOCK_ALL=\"${LOCK_ALL}\""
  write_conf "USE_BINARY_MYSQL_TARBALL=\"${USE_BINARY_MYSQL_TARBALL}\""
  write_conf "RUN_AS_ROOT=\"${RUN_AS_ROOT}\""

  write_conf "ENGINE=\"${ENGINE}\""
  if test "x${ENGINE}" = "xinnodb" ; then
    write_conf "INNODB_OPTION=\"--innodb\""
    write_conf "INNODB_BUFFER_POOL_INSTANCES=\"${INNODB_BUFFER_POOL_INSTANCES}\""
    write_conf "INNODB_BUFFER_POOL_SIZE=\"${INNODB_BUFFER_POOL_SIZE}\""
    write_conf "INNODB_READ_IO_THREADS=\"${INNODB_READ_IO_THREADS}\""
    write_conf "INNODB_WRITE_IO_THREADS=\"${INNODB_WRITE_IO_THREADS}\""
    write_conf "INNODB_THREAD_CONCURRENCY=\"${INNODB_THREAD_CONCURRENCY}\""
    write_conf "INNODB_LOG_FILE_SIZE=\"${INNODB_LOG_FILE_SIZE}\""
    write_conf "INNODB_LOG_BUFFER_SIZE=\"${INNODB_LOG_BUFFER_SIZE}\""
    write_conf "INNODB_LOG_FILES_IN_GROUP=\"${INNODB_LOG_FILES_IN_GROUP}\""
    write_conf "INNODB_USE_NATIVE_AIO=\"${INNODB_USE_NATIVE_AIO}\""
    write_conf "INNODB_PAGE_CLEANERS=\"${INNODB_PAGE_CLEANERS}\""
    write_conf "INNODB_FLUSH_LOG_AT_TRX_COMMIT=\"${INNODB_FLUSH_LOG_AT_TRX_COMMIT}\""
    write_conf "INNODB_ADAPTIVE_HASH_INDEX=\"${INNODB_ADAPTIVE_HASH_INDEX}\""
    write_conf "INNODB_READ_AHEAD_THRESHOLD=\"${INNODB_READ_AHEAD_THRESHOLD}\""
    write_conf "INNODB_IO_CAPACITY=\"${INNODB_IO_CAPACITY}\""
    write_conf "INNODB_MAX_IO_CAPACITY=\"${INNODB_MAX_IO_CAPACITY}\""
    write_conf "INNODB_LOG_DIR=\"${INNODB_LOG_DIR}\""
    write_conf "INNODB_MAX_PURGE_LAG=\"${INNODB_MAX_PURGE_LAG}\""
    write_conf "INNODB_SUPPORT_XA=\"${INNODB_SUPPORT_XA}\""
    write_conf "INNODB_FLUSH_METHOD=\"${INNODB_FLUSH_METHOD}\""
    write_conf "INNODB_NUM_PURGE_THREAD=\"${INNODB_NUM_PURGE_THREAD}\""
    write_conf "INNODB_FILE_PER_TABLE=\"${INNODB_FILE_PER_TABLE}\""
    write_conf "INNODB_DIRTY_PAGES_PCT=\"${INNODB_DIRTY_PAGES_PCT}\""
    write_conf "INNODB_OLD_BLOCKS_PCT=\"${INNODB_OLD_BLOCKS_PCT}\""
    write_conf "INNODB_SPIN_WAIT_DELAY=\"${INNODB_SPIN_WAIT_DELAY}\""
    write_conf "INNODB_SYNC_SPIN_LOOPS=\"${INNODB_SYNC_SPIN_LOOPS}\""
    write_conf "INNODB_STATS_ON_METADATA=\"${INNODB_STATS_ON_METADATA}\""
    write_conf "INNODB_STATS_ON_MUTEXES=\"${INNODB_STATS_ON_MUTEXES}\""
    write_conf "INNODB_CHANGE_BUFFERING=\"${INNODB_CHANGE_BUFFERING}\""
    write_conf "INNODB_DOUBLEWRITE=\"${INNODB_DOUBLEWRITE}\""
    write_conf "INNODB_FILE_FORMAT=\"${INNODB_FILE_FORMAT}\""
    write_conf "INNODB_MONITOR=\"${INNODB_MONITOR}\""
    write_conf "INNODB_FLUSH_NEIGHBOURS=\"${INNODB_FLUSH_NEIGHBOURS}\""
  fi

  if test "x${ENGINE}" = "xndb" ; then
    write_conf "NDB_ENABLED=\"yes\""
    NDB_CONFIG_FILE="$DEFAULT_DIR/config_c1.ini"
    write_conf "NDB_AUTOINCREMENT_OPTION=\"${NDB_AUTOINCREMENT_OPTION}\""
    write_conf "NDB_READ_BACKUP=\"${NDB_READ_BACKUP}\""
    write_conf "NDB_FULLY_REPLICATED=\"${NDB_FULLY_REPLICATED}\""
    write_conf "NDB_DEFAULT_COLUMN_FORMAT=\"${NDB_DEFAULT_COLUMN_FORMAT}\""
    write_conf "NDB_DATA_NODE_NEIGHBOUR=\"${NDB_DATA_NODE_NEIGHBOUR}\""
    write_conf "NDB_CONFIG_FILE=\"${NDB_CONFIG_FILE}\""
    write_conf "USE_NDBMTD=\"${USE_NDBMTD}\""
    write_conf "NDB_START_MAX_WAIT=\"${NDB_START_MAX_WAIT}\""
    write_conf "NUM_NDB_NODES=\"${NUM_NDB_NODES}\""
    write_conf "NDB_RESTART_TEST=\"${NDB_RESTART_TEST}\""
    write_conf "NDB_RESTART_NODE=\"${NDB_RESTART_NODE}\""
    write_conf "NDB_RESTART_NODE2=\"${NDB_RESTART_NODE2}\""
    write_conf "NDB_RESTART_NODE3=\"${NDB_RESTART_NODE3}\""
    write_conf "NDB_RESTART_NODE4=\"${NDB_RESTART_NODE4}\""
    write_conf "NDB_RESTART_NODE5=\"${NDB_RESTART_NODE5}\""
    write_conf "NDB_RESTART_NODE6=\"${NDB_RESTART_NODE6}\""
    write_conf "NDB_RESTART_NODE7=\"${NDB_RESTART_NODE7}\""
    write_conf "NDB_RESTART_NODE8=\"${NDB_RESTART_NODE8}\""
    write_conf "NDB_RESTART_TEST_INITIAL=\"${NDB_RESTART_TEST_INITIAL}\""
    write_conf "NDB_MAX_START_WAIT=\"${NDB_MAX_START_WAIT}\""
    write_conf "NDB_MULTI_CONNECTION=\"${NDB_MULTI_CONNECTION}\""
    write_conf "NDB_REALTIME_SCHEDULER=\"${NDB_REALTIME_SCHEDULER}\""
    write_conf "NDB_RECV_THREAD_ACTIVATION_THRESHOLD=\"${NDB_RECV_THREAD_ACTIVATION_THRESHOLD}\""
    write_conf "NDB_RECV_THREAD_CPU_MASK=\"${NDB_RECV_THREAD_CPU_MASK}\""

    NUM_NDB_MGMD_NODES="0"
    NDB_MGMD_NODES_LOC=`${ECHO} ${NDB_MGMD_NODES} | ${SED} -e 's!\;! !g'`
    for NDB_MGMD_NODE in $NDB_MGMD_NODES_LOC
    do
      ((NUM_NDB_MGMD_NODES+= 1))
      if test "x$NUM_NDB_MGMD_NODES" = "x1" ; then
        write_conf "NDB_CONNECTSTRING=\"${NDB_MGMD_NODE}:$NDB_MGMD_PORT\""
      fi
    done
    write_conf "NUM_NDB_MGMD_NODES=\"${NUM_NDB_MGMD_NODES}\""
  else
    write_conf "NDB_ENABLED=\"no\""
  fi
  write_conf "NDB_MGMD_PORT=\"${NDB_MGMD_PORT}\""
  write_conf "USE_MALLOC_LIB=\"${USE_MALLOC_LIB}\""
  write_conf "PREPARE_JEMALLOC=\"${PREPARE_JEMALLOC}\""
  write_conf "KEY_BUFFER_SIZE=\"${KEY_BUFFER_SIZE}\""
  write_conf "GRANT_TABLE_OPTION=\"${GRANT_TABLE_OPTION}\""
  write_conf "MAX_HEAP_TABLE_SIZE=\"${MAX_HEAP_TABLE_SIZE}\""
  write_conf "SORT_BUFFER_SIZE=\"${SORT_BUFFER_SIZE}\""
  write_conf "TMP_TABLE_SIZE=\"${TMP_TABLE_SIZE}\""
  write_conf "MAX_TMP_TABLES=\"${MAX_TMP_TABLES}\""
  write_conf "THREAD_REGISTER_CONFIG=\"${THREAD_REGISTER_CONFIG}\""
  write_conf "THREADPOOL_SIZE=\"${THREADPOOL_SIZE}\""
  write_conf "THREADPOOL_ALGORITHM=\"${THREADPOOL_ALGORITHM}\""
  write_conf "THREADPOOL_STALL_LIMIT=\"${THREADPOOL_STALL_LIMIT}\""
  write_conf "THREADPOOL_PRIO_KICKUP_TIMER=\"${THREADPOOL_PRIO_KICKUP_TIMER}\""
  write_conf "SSH_PORT=\"${SSH_PORT}\""
  write_conf "MAX_CONNECTIONS=\"${MAX_CONNECTIONS}\""
  write_conf "CORE_FILE_USED=\"${CORE_FILE_USED}\""
  write_conf "RELAY_LOG=\"${RELAY_LOG}\""
  write_conf "BINLOG=\"${BINLOG}\""
  write_conf "SYNC_BINLOG=\"${SYNC_BINLOG}\""
  write_conf "BINLOG_ORDER_COMMITS=\"${BINLOG_ORDER_COMMITS}\""
  write_conf "BINLOG_GROUP_COMMIT_DELAY=\"${BINLOG_GROUP_COMMIT_DELAY}\""
  write_conf "BINLOG_GROUP_COMMIT_COUNT=\"${BINLOG_GROUP_COMMIT_COUNT}\""
  write_conf "SLAVE_HOST=\"${SLAVE_HOST}\""
  write_conf "SLAVE_PORT=\"${SLAVE_PORT}\""
  write_conf "SLAVE_PARALLEL_TYPE=\"${SLAVE_PARALLEL_TYPE}\""
  write_conf "SLAVE_PARALLEL_WORKERS=\"${SLAVE_PARALLEL_WORKERS}\""
  write_conf "ENGINE_CONDITION_PUSHDOWN_OPTION=\"${ENGINE_CONDITION_PUSHDOWN_OPTION}\""
  write_conf "WAIT_STOP=\"${WAIT_STOP}\""
  write_conf "CHARACTER_SET_SERVER=\"${CHARACTER_SET_SERVER}\""
  write_conf "COLLATION_SERVER=\"${COLLATION_SERVER}\""
}

write_dbt2_conf()
{
  MSG="Writing dbt2.conf"
  output_msg
  export DBT2_DEFAULT_FILE="${DEFAULT_DIR}/dbt2.conf"
  CONF_FILE="${DEFAULT_DIR}/dbt2.conf"
  ${ECHO} "#DBT2 configuration used to drive DBT2 benchmarks" > ${CONF_FILE}
  write_conf "MYSQL_SERVER_BASE=\"${MYSQL_SERVER_BASE}\""
  write_conf "DBT3_USE_BOTH_NDB_AND_INNODB=\"${DBT3_USE_BOTH_NDB_AND_INNODB}\""
  write_conf "DBT3_DATA_PATH=\"${DBT3_DATA_PATH}\""
  write_conf "DBT3_ONLY_CREATE=\"${DBT3_ONLY_CREATE}\""
  write_conf "DBT3_PARALLEL_LOAD=\"${DBT3_PARALLEL_LOAD}\""
  write_conf "DBT3_USE_PARTITION_KEY=\"${DBT3_USE_PARTITION_KEY}\""
  write_conf "DBT3_PARTITION_BALANCE=\"${DBT3_PARTITION_BALANCE}\""
  write_conf "DBT3_READ_BACKUP=\"${DBT3_READ_BACKUP}\""
  write_conf "DBT2_PATH=\"${SRC_INSTALL_DIR}/${DBT2_VERSION}\""
  write_conf "BASE_DIR=\"${SRC_INSTALL_DIR}/${DBT2_VERSION}\""
  write_conf "DIS_CONFIG_FILE=\"${DEFAULT_DIR}/dis_config_c1.ini\""
  write_conf "MYSQL_VERSION=\"${MYSQL_VERSION}\""
  write_conf "DBT2_LOADERS=\"${DBT2_LOADERS}\""
  write_conf "DBT2_GENERATE_FILES=\"${DBT2_GENERATE_FILES}\""
  write_conf "DBT2_DATA_DIR=\"${DBT2_DATA_DIR}\""
  write_conf "DBT2_WAREHOUSES=\"${DBT2_WAREHOUSES}\""
  write_conf "DBT2_RESULTS_DIR=\"${DEFAULT_DIR}/dbt2_results\""
  write_conf "DBT2_OUTPUT_DIR=\"${DEFAULT_DIR}/dbt2_output\""
  write_conf "DBT2_LOG_BASE=\"${DEFAULT_DIR}/dbt2_logs\""
  write_conf "DBT2_RUN_CONFIG_FILE=\"${DEFAULT_DIR}/dbt2_run_1.conf\""
  write_conf "DBT2_PARTITION_TYPE=\"${DBT2_PARTITION_TYPE}\""
  write_conf "DBT2_NUM_PARTITIONS=\"${DBT2_NUM_PARTITIONS}\""
  write_conf "DBT2_TABLESPACE_SIZE=\"${DBT2_TABLESPACE_SIZE}\""
  write_conf "DBT2_LOGFILE_SIZE=\"${DBT2_LOGFILE_SIZE}\""
  write_conf "DBT2_LOG_BUFFER_SIZE=\"${DBT2_LOG_BUFFER_SIZE}\""
  write_conf "DBT2_USE_ALTERED_MODE=\"${DBT2_USE_ALTERED_MODE}\""
  write_conf "NDB_USE_DISK_DATA=\"${NDB_USE_DISK_DATA}\""
  write_conf "DBT2_INTERMEDIATE_TIMER_RESOLUTION=\"${DBT2_INTERMEDIATE_TIMER_RESOLUTION}\""
  write_conf "USING_HASH_FLAG=\"${DBT2_PK_USING_HASH}\""
  write_conf "FIRST_CLIENT_PORT=\"${FIRST_CLIENT_PORT}\""
  write_conf "SERVER_HOST=\"${FIRST_SERVER_HOST}\""
  write_conf "SERVER_PORT=\"${FIRST_SERVER_PORT}\""
  write_conf "BETWEEN_RUNS=\"${BETWEEN_RUNS}\""
  write_conf "AFTER_INITIAL_RUN=\"${AFTER_INITIAL_RUN}\""
  write_conf "AFTER_SERVER_START=\"${AFTER_SERVER_START}\""
  write_conf "BETWEEN_CREATE_DB_TEST=\"${BETWEEN_CREATE_DB_TEST}\""
  write_conf "NUM_CREATE_DB_ATTEMPTS=\"${NUM_CREATE_DB_ATTEMPTS}\""
  write_conf "NUM_CHANGE_MASTER_ATTEMPTS=\"${NUM_CHANGE_MASTER_ATTEMPTS}\""
  write_conf "BETWEEN_CHANGE_MASTER_TEST=\"${BETWEEN_CHANGE_MASTER_TEST}\""
  write_conf "AFTER_SERVER_STOP=\"${AFTER_SERVER_STOP}\""
  write_conf "TEST_DESCRIPTION=\"${TEST_DESCRIPTION}\""
  write_conf "USE_MALLOC_LIB=\"${USE_MALLOC_LIB}\""
  write_conf "PREPARE_JEMALLOC=\"${PREPARE_JEMALLOC}\""
  if test "x$MALLOC_LIB" != "x" ; then
    write_conf "MALLOC_LIB=\"${MALLOC_LIB}\""
  fi
  write_conf "BENCH_TASKSET=\"${BENCH_TASKSET}\""
  write_conf "BENCHMARK_CPUS=\"${BENCHMARK_CPUS}\""
  write_conf "LOG_FILE=\"${LOG_FILE}\""
  write_conf "ENGINE=\"${ENGINE}\""
  if test "x${ENGINE}" = "xinnodb" ; then
    write_conf "STORAGE_ENGINE=\"INNODB\""
  elif test "x${ENGINE}" = "xndb" ; then
    write_conf "STORAGE_ENGINE=\"NDB\""
  elif test "x${ENGINE}" = "myisam" ; then
    write_conf "STORAGE_ENGINE=\"MYISAM\""
  fi
  write_conf "MYSQL_PATH=\"${MYSQL_BIN_INSTALL_DIR}/${MYSQL_CLIENT_VERSION}\""
  write_conf "MYSQL_SOCKET=\"${TMP_BASE}/mysql_1.sock\""
  if test "x${DBT2_SPREAD}" != "x" ; then
    DBT2_SPREAD="--spread ${DBT2_SPREAD}"
  fi
  if test "x${DBT2_SCI}" != "x" ; then
    DBT2_SCI="--sci"
  fi
  if test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
    write_conf "DBT2_NUM_SERVERS=\"${DBT2_NUM_SERVERS}\""
    write_conf "DBT2_SCI=\"${DBT2_SCI}\""
    write_conf "DBT2_SPREAD=\"${DBT2_SPREAD}\""
    write_conf "DBT2_TIME=\"${DBT2_TIME}\""
    write_conf "NUM_MYSQL_SERVERS=\"${NUM_MYSQL_SERVERS}\""
    write_conf "USE_MYISAM_FOR_ITEM=\"${USE_MYISAM_FOR_ITEM}\""
    CONF_FILE="${DEFAULT_DIR}/dbt2_run_1.conf"
    if ! test -f $CONF_FILE ; then
      ${ECHO} "#DBT2 run configuration, number of servers, wares and terminals" > ${CONF_FILE}
      DBT2_RUN_WAREHOUSES=`${ECHO} ${DBT2_RUN_WAREHOUSES} | ${SED} -e 's!\;! !g'`
      write_conf "#NUM_SERVERS NUM_WAREHOUSES NUM_TERMINALS"
      for RUN_WAREHOUSES in ${DBT2_RUN_WAREHOUSES}
      do
        if test ${RUN_WAREHOUSES} -gt ${DBT2_WAREHOUSES} ; then
          ${ECHO} "Not allowed to use more in DBT2_RUN_WAREHOUSES than DBT2_WAREHOUSES"
          exit 1
        fi
        CONFIG_LINE="1 ${RUN_WAREHOUSES} ${DBT2_TERMINALS}"
        write_conf ${CONFIG_LINE}
      done
    fi
  else
    write_conf "FLEX_ASYNCH_API_NODES=\"${FLEX_ASYNCH_API_NODES}\""
    write_conf "FLEX_ASYNCH_NUM_THREADS=\"${FLEX_ASYNCH_NUM_THREADS}\""
    write_conf "FLEX_ASYNCH_NUM_PARALLELISM=\"${FLEX_ASYNCH_NUM_PARALLELISM}\""
    write_conf "FLEX_ASYNCH_NUM_OPS_PER_TRANS=\"${FLEX_ASYNCH_NUM_OPS_PER_TRANS}\""
    write_conf "FLEX_ASYNCH_EXECUTION_ROUNDS=\"${FLEX_ASYNCH_EXECUTION_ROUNDS}\""
    write_conf "FLEX_ASYNCH_NUM_ATTRIBUTES=\"${FLEX_ASYNCH_NUM_ATTRIBUTES}\""
    write_conf "FLEX_ASYNCH_ATTRIBUTE_SIZE=\"${FLEX_ASYNCH_ATTRIBUTE_SIZE}\""
    write_conf "FLEX_ASYNCH_NO_LOGGING=\"${FLEX_ASYNCH_NO_LOGGING}\""
    write_conf "FLEX_ASYNCH_FORCE_FLAG=\"${FLEX_ASYNCH_FORCE_FLAG}\""
    write_conf "FLEX_ASYNCH_USE_WRITE=\"${FLEX_ASYNCH_USE_WRITE}\""
    write_conf "FLEX_ASYNCH_USE_LOCAL=\"${FLEX_ASYNCH_USE_LOCAL}\""
    write_conf "FLEX_ASYNCH_NO_HINT=\"${FLEX_ASYNCH_NO_HINT}\""
    write_conf "FLEX_ASYNCH_NUM_MULTI_CONNECTIONS=\"${FLEX_ASYNCH_NUM_MULTI_CONNECTIONS}\""
    write_conf "FLEX_ASYNCH_WARMUP_TIMER=\"${FLEX_ASYNCH_WARMUP_TIMER}\""
    write_conf "FLEX_ASYNCH_EXECUTION_TIMER=\"${FLEX_ASYNCH_EXECUTION_TIMER}\""
    write_conf "FLEX_ASYNCH_COOLDOWN_TIMER=\"${FLEX_ASYNCH_COOLDOWN_TIMER}\""
    write_conf "FLEX_ASYNCH_NEW=\"${FLEX_ASYNCH_NEW}\""
    write_conf "FLEX_ASYNCH_DEF_THREADS=\"${FLEX_ASYNCH_DEF_THREADS}\""
    write_conf "FLEX_ASYNCH_NO_HINT=\"${FLEX_ASYNCH_NO_HINT}\""
    write_conf "FLEX_ASYNCH_MAX_INSERTERS=\"${FLEX_ASYNCH_MAX_INSERTERS}\""
    write_conf "FLEX_ASYNCH_END_AFTER_CREATE=\"${FLEX_ASYNCH_END_AFTER_CREATE}\""
    write_conf "FLEX_ASYNCH_END_AFTER_INSERT=\"${FLEX_ASYNCH_END_AFTER_INSERT}\""
    write_conf "FLEX_ASYNCH_END_AFTER_UPDATE=\"${FLEX_ASYNCH_END_AFTER_UPDATE}\""
    write_conf "FLEX_ASYNCH_END_AFTER_READ=\"${FLEX_ASYNCH_END_AFTER_READ}\""
    write_conf "FLEX_ASYNCH_END_AFTER_DELETE=\"${FLEX_ASYNCH_END_AFTER_DELETE}\""
    write_conf "FLEX_ASYNCH_NUM_TABLES=\"${FLEX_ASYNCH_NUM_TABLES}\""
    write_conf "FLEX_ASYNCH_NUM_INDEXES=\"${FLEX_ASYNCH_NUM_INDEXES}\""
    write_conf "FLEX_ASYNCH_NO_UPDATE=\"${FLEX_ASYNCH_NO_UPDATE}\""
    write_conf "FLEX_ASYNCH_NO_DELETE=\"${FLEX_ASYNCH_NO_DELETE}\""
    write_conf "FLEX_ASYNCH_NO_READ=\"${FLEX_ASYNCH_NO_READ}\""
    write_conf "FLEX_ASYNCH_NO_DROP=\"${FLEX_ASYNCH_NO_DROP}\""
    write_conf "FLEX_ASYNCH_RECV_CPUS=\"${FLEX_ASYNCH_RECV_CPUS}\""
    write_conf "FLEX_ASYNCH_DEF_CPUS=\"${FLEX_ASYNCH_DEF_CPUS}\""
    write_conf "FLEX_ASYNCH_EXEC_CPUS=\"${FLEX_ASYNCH_EXEC_CPUS}\""
    CONF_FILE="${DEFAULT_DIR}/dbt2_run_1.conf"
    write_conf "#Empty set of MySQL Servers to start"
  fi
}

write_sysbench_conf()
{
  MSG="Writing sysbench.conf"
  output_msg
  CONF_FILE="${DEFAULT_DIR}/sysbench.conf"
  ${ECHO} "#Sysbench configuration used to drive sysbench benchmarks" > ${CONF_FILE}
  write_conf "MYSQL_SERVER_BASE=\"${MYSQL_SERVER_BASE}\""
  write_conf "SYSBENCH=\"${MYSQL_BIN_INSTALL_DIR}/${SYSBENCH_VERSION}/bin/sysbench\""
  write_conf "DBT2_PATH=\"${SRC_INSTALL_DIR}/${DBT2_VERSION}\""
  write_conf "SERVER_HOST=\"${FIRST_SERVER_HOST}\""
  write_conf "SERVER_PORT=\"${FIRST_SERVER_PORT}\""
  write_conf "MYSQL_PATH=\"${MYSQL_BIN_INSTALL_DIR}/${MYSQL_CLIENT_VERSION}\""
  write_conf "MYSQL_SOCKET=\"${TMP_BASE}/mysql_1.sock\""
  write_conf "NDB_USE_DISK_DATA=\"${NDB_USE_DISK_DATA}\""
  write_conf "RUN_RW=\"${RUN_RW}\""
  write_conf "RUN_RW_WRITE_INT=\"${RUN_RW_WRITE_INT}\""
  write_conf "RUN_RW_LESS_READ=\"${RUN_RW_LESS_READ}\""
  write_conf "RUN_RO=\"${RUN_RO}\""
  write_conf "RUN_RO_PS=\"${RUN_RO_PS}\""
  write_conf "RUN_WRITE=\"${RUN_WRITE}\""
  write_conf "RUN_NONTRX=\"${RUN_NONTRX}\""
  write_conf "SB_USE_SECONDARY_INDEX=\"${SB_USE_SECONDARY_INDEX}\""
  write_conf "SB_USE_MYSQL_HANDLER=\"${SB_USE_MYSQL_HANDLER}\""
  write_conf "SB_USE_RANGE=\"${SB_USE_RANGE}\""
  write_conf "SB_NUM_PARTITIONS=\"${SB_NUM_PARTITIONS}\""
  write_conf "SB_NUM_TABLES=\"${SB_NUM_TABLES}\""
  write_conf "THREAD_COUNTS_TO_RUN=\"${THREAD_COUNTS_TO_RUN}\""
  write_conf "ENGINE=\"${ENGINE}\""
  write_conf "SB_AVOID_DEADLOCKS=\"${SB_AVOID_DEADLOCKS}\""
  write_conf "SB_MAX_REQUESTS=\"${SB_MAX_REQUESTS}\""
  write_conf "SB_PARTITION_BALANCE=\"${SB_PARTITION_BALANCE}\""
  write_conf "SB_NONTRX_MODE=\"${SB_NONTRX_MODE}\""
  write_conf "SB_VERBOSITY=\"${SB_VERBOSITY}\""
  write_conf "SYSBENCH_DB=\"${SYSBENCH_DB}\""
  if test "x$ENGINE" = "xndb" ; then
    TRX_ENGINE="yes"
  fi
  if test "x$ENGINE" = "xinnodb" ; then
    TRX_ENGINE="yes"
  fi
  if test "x$ENGINE" = "xmyisam" ; then
    TRX_ENGINE="no"
  fi
  if test "x$ENGINE" = "xheap" ; then
    TRX_ENGINE="no"
  fi
  if test "x$ENGINE" = "xmemory" ; then
    TRX_ENGINE="no"
  fi
  if test "x$SB_USE_TRX" = "x" ; then
    SB_USE_TRX="$TRX_ENGINE"
  fi
  write_conf "SB_USE_TRX=\"${SB_USE_TRX}\""
  write_conf "SB_DIST_TYPE=\"${SB_DIST_TYPE}\""
  write_conf "TRX_ENGINE=\"${TRX_ENGINE}\""
  if test "x$SB_USE_AUTO_INC" = "xyes" ; then
    SB_USE_AUTO_INC="on"
  else
    if test "x$SB_USE_FILTER" = "xyes" ; then
      SB_USE_FILTER="on"
    else
      SB_USE_FILTER="off"
    fi
    SB_USE_AUTO_INC="off"
  fi
  write_conf "SB_USE_FILTER=\"${SB_USE_FILTER}\""
  write_conf "SB_POINT_SELECTS=\"${SB_POINT_SELECTS}\""
  write_conf "SB_RANGE_SIZE=\"${SB_RANGE_SIZE}\""
  write_conf "SB_SIMPLE_RANGES=\"${SB_SIMPLE_RANGES}\""
  write_conf "SB_SUM_RANGES=\"${SB_SUM_RANGES}\""
  write_conf "SB_ORDER_RANGES=\"${SB_ORDER_RANGES}\""
  write_conf "SB_DISTINCT_RANGES=\"${SB_DISTINCT_RANGES}\""
  write_conf "SB_USE_IN_STATEMENT=\"${SB_USE_IN_STATEMENT}\""
  write_conf "SB_USE_AUTO_INC=\"${SB_USE_AUTO_INC}\""
  write_conf "MAX_TIME=\"${MAX_TIME}\""
  write_conf "NUM_TEST_RUNS=\"${NUM_TEST_RUNS}\""
  write_conf "SB_TX_RATE=\"${SB_TX_RATE}\""
  write_conf "SB_TX_JITTER=\"${SB_TX_JITTER}\""
  write_conf "SYSBENCH_ROWS=\"${SYSBENCH_ROWS}\""
  write_conf "TEST_DESCRIPTION=\"${TEST_DESCRIPTION}\""
  write_conf "USE_MALLOC_LIB=\"${USE_MALLOC_LIB}\""
  write_conf "PREPARE_JEMALLOC=\"${PREPARE_JEMALLOC}\""
  if test "x$MALLOC_LIB" != "x" ; then
    write_conf "MALLOC_LIB=\"${MALLOC_LIB}\""
  fi
  write_conf "BENCH_TASKSET=\"${BENCH_TASKSET}\""
  write_conf "BENCHMARK_CPUS=\"${BENCHMARK_CPUS}\""
  write_conf "BETWEEN_RUNS=\"${BETWEEN_RUNS}\""
  write_conf "AFTER_INITIAL_RUN=\"${AFTER_INITIAL_RUN}\""
  write_conf "AFTER_SERVER_START=\"${AFTER_SERVER_START}\""
  write_conf "BETWEEN_CREATE_DB_TEST=\"${BETWEEN_CREATE_DB_TEST}\""
  write_conf "NUM_CREATE_DB_ATTEMPTS=\"${NUM_CREATE_DB_ATTEMPTS}\""
  write_conf "NUM_CHANGE_MASTER_ATTEMPTS=\"${NUM_CHANGE_MASTER_ATTEMPTS}\""
  write_conf "BETWEEN_CHANGE_MASTER_TEST=\"${BETWEEN_CHANGE_MASTER_TEST}\""
  write_conf "AFTER_SERVER_STOP=\"${AFTER_SERVER_STOP}\""
  write_conf "LOG_FILE=\"${LOG_FILE}\""
  if test "x${MYSQL_CREATE_OPTIONS}" != "x" ; then
    write_conf "MYSQL_CREATE_OPTIONS=\"${MYSQL_CREATE_OPTIONS}\""
  fi
}

add_remote_node()
{
  LOCAL_ADD_NODE="$1"
  LOCAL_FLAG="0"
  for LOCAL_NODE in $REMOTE_NODES
  do
    if test "x$LOCAL_NODE" = "x$LOCAL_ADD_NODE" ; then
      LOCAL_FLAG="1"
    fi
  done
  if test "x$LOCAL_FLAG" = "x0" ; then
    ${ECHO} "Added $LOCAL_ADD_NODE to list of remote nodes"
    REMOTE_NODES="$REMOTE_NODES $LOCAL_ADD_NODE"
  fi
}

set_up_ndb_execute_cpu()
{
  if test "x${NDB_EXECUTE_CPU}" != "x" ; then
    NDB_EXECUTE_CPU_LOC=(`${ECHO} ${NDB_EXECUTE_CPU} | ${SED} -e 's!\;! !g'`)
    if test "x${#NDB_EXECUTE_CPU_LOC[*]}" = "x1" ; then
      for ((i_sunec = 0; i_sunec < NUM_NDB_NODES; i_sunec += 1))
      do
        NDB_EXECUTE_CPU_LOC[${i_sunec}]=$NDB_EXECUTE_CPU
      done
    else
      if test "x${#NDB_EXECUTE_CPU_LOC[*]}" != "x$NUM_NDB_NODES" ; then
        echo "NDB_EXECUTE_CPU need as many parameters as there are NDB nodes or 1 parameter"
        exit 1
      fi
    fi
  fi
}

set_up_ndb_maint_cpu()
{
  if test "x${NDB_MAINT_CPU}" != "x" ; then
    NDB_MAINT_CPU_LOC=(`${ECHO} ${NDB_MAINT_CPU} | ${SED} -e 's!\;! !g'`)
    if test "x${#NDB_MAINT_CPU_LOC[*]}" = "x1" ; then
      for ((i_sunmc = 0; i_sunmc < NUM_NDB_NODES; i_sunmc += 1))
      do
        NDB_MAINT_CPU_LOC[${i_sunmc}]=$NDB_MAINT_CPU
      done
    else
      if test "x${#NDB_MAINT_CPU_LOC[*]}" != "x$NUM_NDB_NODES" ; then
        echo "NDB_MAINT_CPU need as many parameters as there are NDB nodes or 1 parameter"
        exit 1
      fi
    fi
  fi
}

set_up_ndb_thread_config()
{
  if test "x${NDB_THREAD_CONFIG}" != "x" ; then
    NDB_THREAD_CONFIG_LOC=(`${ECHO} ${NDB_THREAD_CONFIG} | ${SED} -e 's!\;! !g'`)
    if test "x${#NDB_THREAD_CONFIG_LOC[*]}" = "x1" ; then
      for ((i_suntc = 0; i_suntc < NUM_NDB_NODES; i_suntc += 1))
      do
        NDB_THREAD_CONFIG_LOC[${i_suntc}]=${NDB_THREAD_CONFIG}
      done
    else
      if test "x${#NDB_THREAD_CONFIG_LOC[*]}" != "x$NUM_NDB_NODES" ; then
        echo "NDB_THREAD_CONFIG need as many parameters as there are NDB nodes or 1 parameter"
        exit 1
      fi
    fi
  fi
}

set_up_ndb_max_no_of_execution_threads()
{
  if test "x${NDB_MAX_NO_OF_EXECUTION_THREADS}" != "x" ; then
    NDB_MAX_NO_OF_EXECUTION_THREADS_LOC=(`${ECHO} ${NDB_MAX_NO_OF_EXECUTION_THREADS} | ${SED} -e 's!\;! !g'`)
    if test "x${#NDB_MAX_NO_OF_EXECUTION_THREADS_LOC[*]}" = "x1" ; then
      for ((i_sunmnoet = 0; i_sunmnoet < NUM_NDB_NODES; i_sunmnoet += 1))
      do
        NDB_MAX_NO_OF_EXECUTION_THREADS_LOC[${i_sunmnoet}]=$NDB_MAX_NO_OF_EXECUTION_THREADS
      done
    else
      if test "x${#NDB_MAX_NO_OF_EXECUTION_THREADS_LOC[*]}" != "x$NUM_NDB_NODES" ; then
        echo "NDB_MAX_NO_OF_EXECUTION_THREADS need as many parameters as there are NDB nodes or 1 parameter"
        exit 1
      fi
    fi
  fi
}

write_tcp_default()
{
  CONFIG_LINE="[TCP DEFAULT]"
  write_conf $CONFIG_LINE
  CONFIG_LINE="SendBufferMemory=$NDB_SEND_BUFFER_MEMORY"
  write_conf $CONFIG_LINE
  if test "x$NDB_TCP_SEND_BUFFER_MEMORY" != "x" ; then
    CONFIG_LINE="TCP_SND_BUF_SIZE=$NDB_TCP_SEND_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_TCP_RECEIVE_BUFFER_MEMORY" != "x" ; then
    CONFIG_LINE="TCP_RCV_BUF_SIZE=$NDB_TCP_RECEIVE_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
  fi
  CONFIG_LINE="ReceiveBufferMemory=$NDB_RECEIVE_BUFFER_MEMORY"
  write_conf $CONFIG_LINE
}

write_mysqld_default()
{
  CONFIG_LINE="[MYSQLD DEFAULT]"
  write_conf $CONFIG_LINE
  CONFIG_LINE="BatchSize=128"
  write_conf $CONFIG_LINE
  CONFIG_LINE="DefaultOperationRedoProblemAction=abort"
  write_conf $CONFIG_LINE
}

write_ndbd_default()
{
  CONFIG_LINE="[NDBD DEFAULT]"
  write_conf $CONFIG_LINE
  if test "x$USE_SHM" = "xyes" ; then
    CONFIG_LINE="UseShm=1"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_PARTITIONS_PER_NODE" != "x0" ; then
    CONFIG_LINE="PartitionsPerNode=$NDB_PARTITIONS_PER_NODE"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_USE_DISK_DATA" = "xyes" ; then
    CONFIG_LINE="InitialLogfileGroup=undo_buffer_size=$NDB_UNDO_BUFFER_SIZE;lg1.dat:$NDB_UNDO_LOGFILE_SIZE"
    write_conf $CONFIG_LINE
    CONFIG_LINE="InitialTablespace=name=ts1;extent_size=$NDB_EXTENT_SIZE;ts1.dat:$NDB_TABLESPACE_SIZE"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_DATA_FILES" != "x" ; then
    CONFIG_LINE="FileSystemPathDataFiles=$NDB_DATA_FILES"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_UNDO_FILES" != "x" ; then
    CONFIG_LINE="FileSystemPathUndoFiles=$NDB_UNDO_FILES"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_DISK_FILE_PATH" != "x" ; then
    CONFIG_LINE="FileSystemPathDD=$NDB_DISK_FILE_PATH"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_DISK_PAGE_BUFFER_MEMORY" != "x" ; then
    CONFIG_LINE="DiskPageBufferMemory=$NDB_DISK_PAGE_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_SERVER_PORT" != "x" ; then
    CONFIG_LINE="ServerPort=$NDB_SERVER_PORT"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_COLOCATED_LDM_AND_TC" != "x" ; then
    CONFIG_LINE="ColocateLdmAndTcThreads=$NDB_COLOCATED_LDM_AND_TC"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_NODE_GROUP_TRANSPORTERS" != "x" ; then
    CONFIG_LINE="NodeGroupTransporters=$NDB_NODE_GROUP_TRANSPORTERS"
    write_conf $CONFIG_LINE
  fi
  CONFIG_LINE="BatchSizePerLocalScan=128"
  write_conf $CONFIG_LINE
  CONFIG_LINE="MaxNoOfConcurrentTransactions=$NDB_MAX_NO_OF_CONCURRENT_TRANSACTIONS"
  write_conf $CONFIG_LINE
  CONFIG_LINE="MaxNoOfConcurrentOperations=$NDB_MAX_NO_OF_CONCURRENT_OPERATIONS"
  write_conf $CONFIG_LINE
  CONFIG_LINE="MaxNoOfConcurrentScans=$NDB_MAX_NO_OF_CONCURRENT_SCANS"
  write_conf $CONFIG_LINE
  CONFIG_LINE="MaxNoOfLocalScans=$NDB_MAX_NO_OF_LOCAL_SCANS"
  write_conf $CONFIG_LINE
  CONFIG_LINE="NoOfFragmentLogFiles=$NDB_NO_OF_FRAGMENT_LOG_FILES"
  write_conf $CONFIG_LINE
  CONFIG_LINE="MaxBufferedEpochs=500"
  write_conf $CONFIG_LINE
  CONFIG_LINE="FragmentLogFileSize=$NDB_FRAGMENT_LOG_FILE_SIZE"
  write_conf $CONFIG_LINE
  CONFIG_LINE="DiskSyncSize=32M"
  write_conf $CONFIG_LINE
  if test "x$MYSQL_NDB_BASE" != "x8.0" ; then
    CONFIG_LINE="BackupWriteSize=512k"
    write_conf $CONFIG_LINE
    CONFIG_LINE="BackupMaxWriteSize=1M"
    write_conf $CONFIG_LINE
    CONFIG_LINE="BackupDataBufferSize=2M"
    write_conf $CONFIG_LINE
  fi
  CONFIG_LINE="BackupLogBufferSize=4M"
  write_conf $CONFIG_LINE
  CONFIG_LINE="SharedGlobalMemory=$NDB_SHARED_GLOBAL_MEMORY"
  write_conf $CONFIG_LINE
#  CONFIG_LINE="IndexStatAutoCreate=$NDB_INDEX_STAT_AUTO_CREATE"
#  write_conf $CONFIG_LINE
#  CONFIG_LINE="IndexStatAutoUpdate=$NDB_INDEX_STAT_AUTO_UPDATE"
#  write_conf $CONFIG_LINE
  CONFIG_LINE="CompressedBackup=$NDB_COMPRESSED_BACKUP"
  write_conf $CONFIG_LINE
  CONFIG_LINE="CompressedLcp=$NDB_COMPRESSED_LCP"
  write_conf $CONFIG_LINE
  if test "x${NDB_RECOVERY_WORK}" != "x" ; then
    CONFIG_LINE="RecoveryWork=${NDB_RECOVERY_WORK}"
    write_conf $CONFIG_LINE
  fi
  if test "x${NDB_INSERT_RECOVERY_WORK}" = "xyes" ; then
    CONFIG_LINE="InsertRecoveryWork=${NDB_INSERT_RECOVERY_WORK}"
    write_conf $CONFIG_LINE
  fi
  if test "x${NDB_ENABLE_REDO_CONTROL}" = "xyes" ; then
    CONFIG_LINE="EnableRedoControl=1"
    write_conf $CONFIG_LINE
  fi
  if test "x${NDB_REALTIME_SCHEDULER}" = "xyes" ; then
    CONFIG_LINE="RealtimeScheduler=1"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_TIME_BETWEEN_LOCAL_CHECKPOINTS" != "x" ; then
    CONFIG_LINE="TimeBetweenLocalCheckpoints=$NDB_TIME_BETWEEN_LOCAL_CHECKPOINTS"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_TIME_BETWEEN_GLOBAL_CHECKPOINTS" != "x" ; then
    CONFIG_LINE="TimeBetweenGlobalCheckpoints=$NDB_TIME_BETWEEN_GLOBAL_CHECKPOINTS"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_MIN_DISK_WRITE_SPEED" != "x" ; then
    CONFIG_LINE="MinDiskWriteSpeed=$NDB_MIN_DISK_WRITE_SPEED"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_MAX_DISK_WRITE_SPEED" != "x" ; then
    CONFIG_LINE="MaxDiskWriteSpeed=$NDB_MAX_DISK_WRITE_SPEED"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_MAX_DISK_WRITE_SPEED_OTHER_NODE_RESTART" != "x" ; then
    CONFIG_LINE="MaxDiskWriteSpeedOtherNodeRestart=$NDB_MAX_DISK_WRITE_SPEED_OTHER_NODE_RESTART"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_MAX_DISK_WRITE_SPEED_OWN_RESTART" != "x" ; then
    CONFIG_LINE="MaxDiskWriteSpeedOwnRestart=$NDB_MAX_DISK_WRITE_SPEED_OWN_RESTART"
    write_conf $CONFIG_LINE
  fi
  if test "x$DISK_CHECKPOINT_SPEED" = "x" ; then
    CONFIG_LINE="DiskCheckpointSpeed=$DISK_CHECKPOINT_SPEED"
    write_conf $CONFIG_LINE
    CONFIG_LINE="DiskCheckpointSpeedInRestart=100M"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_SCHEDULER_RESPONSIVENESS" != "x" ; then
    CONFIG_LINE="SchedulerResponsiveness=$NDB_SCHEDULER_RESPONSIVENESS"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_SCHED_SCAN_PRIORITY" != "x" ; then
    CONFIG_LINE="__sched_scan_priority=$NDB_SCHED_SCAN_PRIORITY"
    write_conf $CONFIG_LINE
  fi
  if test "x$USE_DOCKER" = "xyes" ; then
    CONFIG_LINE="DataDir=/var/lib/mysql"
    write_conf $CONFIG_LINE
  else
    CONFIG_LINE="DataDir=$DATA_DIR_BASE/ndbd"
    write_conf $CONFIG_LINE
  fi
  CONFIG_LINE="RedoBuffer=$NDB_REDO_BUFFER"
  write_conf $CONFIG_LINE
  CONFIG_LINE="TransactionDeadlockDetectionTimeout=10000"
  write_conf $CONFIG_LINE
  CONFIG_LINE="LongMessageBuffer=128M"
  write_conf $CONFIG_LINE
  CONFIG_LINE="InitFragmentLogFiles=full"
  write_conf $CONFIG_LINE
  CONFIG_LINE="RedoOverCommitLimit=45"
  write_conf $CONFIG_LINE
  CONFIG_LINE="Numa=$NDB_NUMA"
  write_conf $CONFIG_LINE
  if test "x$NDB_MAX_SEND_DELAY" != "x" ; then
    CONFIG_LINE="MaxSendDelay=$NDB_MAX_SEND_DELAY"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_LOG_LEVEL" != "x" ; then
    CONFIG_LINE="LogLevelCheckpoint=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelCongestion=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelConnection=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelError=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelInfo=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelNodeRestart=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelShutdown=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelStartup=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
    CONFIG_LINE="LogLevelStatistic=${NDB_LOG_LEVEL}"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_DISKLESS" = "xyes" ; then
    CONFIG_LINE="Diskless=1"
    write_conf $CONFIG_LINE
  fi
  if test "x$USE_NDB_O_DIRECT" = "xyes" ; then
    CONFIG_LINE="ODirect=1"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_DISK_IO_THREADPOOL" != "x" ; then
    CONFIG_LINE="DiskIOThreadPool=$NDB_DISK_IO_THREADPOOL"
    write_conf $CONFIG_LINE
  fi
  if test "x$MYSQL_NDB_BASE" = "x5.5" || \
     test "x$MYSQL_NDB_BASE" = "x5.6" || \
     test "x$MYSQL_NDB_BASE" = "x5.7" || \
     test "x$MYSQL_NDB_BASE" = "x8.0" ; then
    CONFIG_LINE="ExtraSendBufferMemory=$NDB_EXTRA_SEND_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
    if test "x$NDB_NO_OF_FRAGMENT_LOG_PARTS" != "x" ; then
      CONFIG_LINE="NoOfFragmentLogParts=$NDB_NO_OF_FRAGMENT_LOG_PARTS"
      write_conf $CONFIG_LINE
    fi
  fi
  NUM_NDB_NODES="0"
  for NDBD_NODE in $NDBD_NODES
  do
    ((NUM_NDB_NODES+= 1))
  done
  if test "x$NUM_NDB_NODES" = "x1" ; then
    NDB_REPLICAS="1"
  fi
  CONFIG_LINE="NoOfReplicas=$NDB_REPLICAS"
  write_conf $CONFIG_LINE
  CONFIG_LINE="DataMemory=$NDB_DATA_MEMORY"
  write_conf $CONFIG_LINE
  if test "x$MYSQL_NDB_BASE" != "x8.0" ; then
    CONFIG_LINE="IndexMemory=$NDB_INDEX_MEMORY"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_TOTAL_SEND_BUFFER_MEMORY" != "x" ; then
    CONFIG_LINE="TotalSendBufferMemory=$NDB_TOTAL_SEND_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
  fi
  CONFIG_LINE="TimeBetweenWatchDogCheckInitial=$NDB_TIME_BETWEEN_WATCHDOG_CHECK_INITIAL"
  write_conf $CONFIG_LINE
  if test "x$NDB_SCHEDULER_SPIN_TIMER" != "x" ; then
    CONFIG_LINE="SchedulerSpinTimer=$NDB_SCHEDULER_SPIN_TIMER"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_SPINTIME_PER_CALL" != "x" ; then
    CONFIG_LINE="SpinTimePerCall=$NDB_SPINTIME_PER_CALL"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_ENABLE_ADAPTIVE_SPINNING" = "xno" ; then
    CONFIG_LINE="EnableAdaptiveSpinning=false"
    write_conf $CONFIG_LINE
  fi
  if test "x$NDB_ALLOWED_SPIN_OVERHEAD" != "x" ; then
    CONFIG_LINE="AllowedSpinOverhead=$NDB_ALLOWED_SPIN_OVERHEAD"
    write_conf $CONFIG_LINE
  fi
}

write_mgmd_nodes()
{
  NODEID="0"
  for NDB_MGMD_NODE in $NDB_MGMD_NODES
  do
    ((NODEID+= 1))
    CONFIG_LINE="[NDB_MGMD]"
    write_conf $CONFIG_LINE
    if test "x$USE_DOCKER" = "xyes" ; then
      CONFIG_LINE="DataDir=/var/lib/mysql"
      write_conf $CONFIG_LINE
    else
      CONFIG_LINE="DataDir=$DATA_DIR_BASE/ndb_mgmd"
      write_conf $CONFIG_LINE
    fi
    CONFIG_LINE="HostName=$NDB_MGMD_NODE"
    write_conf $CONFIG_LINE
    CONFIG_LINE="PortNumber=$NDB_MGMD_PORT"
    write_conf $CONFIG_LINE
    CONFIG_LINE="NodeId=$NODEID"
    write_conf $CONFIG_LINE
  done
}

write_ndbd_nodes()
{
  NUM_NDB_NODES="0"
  for NDBD_NODE in $NDBD_NODES
  do
    ((NUM_NDB_NODES+= 1))
  done
  set_up_ndb_execute_cpu
  set_up_ndb_maint_cpu
  set_up_ndb_thread_config
  set_up_ndb_max_no_of_execution_threads
  INDEX="0"
  for NDBD_NODE in $NDBD_NODES
  do
    ((NODEID+= 1))
    NDBMTD_NODE_ID="$NODEID"
    CONFIG_LINE="[NDBD]"
    write_conf $CONFIG_LINE
    CONFIG_LINE="NodeId=$NODEID"
    write_conf $CONFIG_LINE
    if test "x${NDB_EXECUTE_CPU}" != "x" ; then
      CONFIG_LINE="LockExecuteThreadToCPU=${NDB_EXECUTE_CPU_LOC[${INDEX}]}"
      write_conf $CONFIG_LINE
    fi
    if test "x${NDB_MAINT_CPU}" != "x" ; then
      CONFIG_LINE="LockMaintThreadsToCPU=${NDB_MAINT_CPU_LOC[${INDEX}]}"
      write_conf $CONFIG_LINE
    fi
    if test "x$USE_NDBMTD" != "x" ; then
      if test "x$NDB_THREAD_CONFIG" != "x" ; then
        CONFIG_LINE="ThreadConfig=${NDB_THREAD_CONFIG_LOC[${INDEX}]}"
        write_conf $CONFIG_LINE
      elif test "x${NDB_MAX_NO_OF_EXECUTION_THREADS}" != "x" ; then
        CONFIG_LINE="MaxNoOfExecutionThreads=${NDB_MAX_NO_OF_EXECUTION_THREADS_LOC[${INDEX}]}"
        write_conf $CONFIG_LINE
      fi
    fi
    CONFIG_LINE="HostName=$NDBD_NODE"
    write_conf $CONFIG_LINE
    if test "x$NDBD_DOMAIN_ID" != "x" ; then
      LOC_DOMAIN_ID="${NDBD_DOMAIN_IDS[${INDEX}]}"
      CONFIG_LINE="LocationDomainId: $LOC_DOMAIN_ID"
      write_conf $CONFIG_LINE
    fi
    ((INDEX+= 1))
  done
}

write_api_nodes()
{
  if test "x$BENCHMARK_TO_RUN" = "xflexAsynch" ; then
    if test "x${FLEX_ASYNCH_NUM_MULTI_CONNECTIONS}" = "x" ; then
      ((NUM_MULTI_CONNECTIONS=1))
    else
      ((NUM_MULTI_CONNECTIONS=FLEX_ASYNCH_NUM_MULTI_CONNECTIONS))
    fi
    FLEX_API_HOSTS=`$ECHO $FLEX_ASYNCH_API_NODES | $SED -e 's!\;! !g'`
    for LOCAL_API_NODE in $FLEX_API_HOSTS
    do
      ((FIRST_MYSQL_SERVER_NODE_ID=NODEID+1))
      for ((i_wan = 0; i_wan < NUM_MULTI_CONNECTIONS; i_wan += 1))
      do
        ((NODEID+= 1))
        CONFIG_LINE="[MYSQLD]"
        write_conf $CONFIG_LINE
        CONFIG_LINE="NodeId: $NODEID"
        write_conf $CONFIG_LINE
        CONFIG_LINE="Hostname: $LOCAL_API_NODE"
        write_conf $CONFIG_LINE
      done
      if test "x$API_DOMAIN_ID" != "x" ; then
        LOC_DOMAIN_ID="${API_DOMAIN_IDS[${ii}]}"
        CONFIG_LINE="LocationDomainId: $LOC_DOMAIN_ID"
        write_conf $CONFIG_LINE
      fi
      ((LAST_MYSQL_SERVER_NODE_ID=NODEID))
    done
  else
    if test "x${NDB_MULTI_CONNECTION}" = "x" ; then
      ((NUM_MULTI_CONNECTIONS=1))
    else
      ((NUM_MULTI_CONNECTIONS=NDB_MULTI_CONNECTION))
    fi
    ((FIRST_MYSQL_NODE_ID=NODEID+1))
    ((ii = 0))
    for MYSQL_SERVER in $SERVER_HOST
    do
      ((FIRST_MYSQL_SERVER_NODE_ID=NODEID+1))
      for ((i_wan = 0; i_wan < NUM_MULTI_CONNECTIONS; i_wan += 1))
      do
        ((NODEID+= 1))
        CONFIG_LINE="[MYSQLD]"
        write_conf $CONFIG_LINE
        CONFIG_LINE="NodeId: $NODEID"
        write_conf $CONFIG_LINE
        CONFIG_LINE="Hostname: $MYSQL_SERVER"
        write_conf $CONFIG_LINE
      done
      if test "x$SERVER_DOMAIN_ID" != "x" ; then
        LOC_DOMAIN_ID="${SERVER_DOMAIN_IDS[${ii}]}"
        CONFIG_LINE="LocationDomainId: $LOC_DOMAIN_ID"
        write_conf $CONFIG_LINE
      fi
      ((LAST_MYSQL_SERVER_NODE_ID=NODEID))
      ((ii += 1))
    done
  fi
  #Provide extra API node ids for debug usage
  for ((i_extra = 0; i_extra < NDB_EXTRA_CONNECTIONS; i_extra += 1))
  do
    CONFIG_LINE="[MYSQLD]"
    write_conf $CONFIG_LINE
  done
}

write_shm_default()
{
  if test "x$USE_SHM" = "xyes" ; then
    CONFIG_FILE="[SHM DEFAULT]"
    write_conf $CONFIG_FILE
    CONFIG_LINE="ShmSize=$NDB_SHM_SIZE"
    write_conf $CONFIG_LINE
    CONFIG_LINE="SendBufferMemory=$NDB_SHM_SEND_BUFFER_MEMORY"
    write_conf $CONFIG_LINE
    CONFIG_LINE="ShmSpintime=$NDB_SHM_SPINTIME"
    write_conf $CONFIG_LINE
  fi
}

write_ndb_config()
{
  set_up_server_domain_id
  set_up_ndbd_domain_id
  write_tcp_default
  write_shm_default
  write_mysqld_default
  write_ndbd_default
  write_mgmd_nodes
  write_ndbd_nodes
  write_api_nodes
}

set_up_bind_cpus_config()
{
  if test "x$USE_DOCKER" = "xyes" ; then
    if test "x$SERVER_CPUS" != "x" ; then
      CONFIG_LINE="${CONFIG_LINE} --docker_cpus"
      CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_CPUS[${INDEX}]}"
    fi
    if test "x$SERVER_BIND" != "x" ; then
      CONFIG_LINE="${CONFIG_LINE} --docker_bind"
      CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_BIND[${INDEX}]}"
    fi
  elif test "x${TASKSET}" = "xtaskset" ; then
    if test "x${SERVER_CPUS}" != "x" ; then
      CONFIG_LINE="${CONFIG_LINE} --taskset"
      CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_CPUS[${INDEX}]}"
    fi
  elif test "x${TASKSET}" = "xnumactl" ; then
    if test "x${SERVER_BIND}" != "x"; then
      if test "x$SERVER_MEM_POLICY" = "xinterleaved" ; then
        if test "x$SERVER_CPUS" = "x" ; then
          CONFIG_LINE="${CONFIG_LINE} --numactl_interleave_bind"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_BIND[${INDEX}]}"
        else
          CONFIG_LINE="${CONFIG_LINE} --numactl_interleave_cpus"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_BIND[${INDEX}]}"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_CPUS[${INDEX}]}"
        fi
      else
        if test "x$SERVER_CPUS" = "x" ; then
          CONFIG_LINE="${CONFIG_LINE} --numactl_bind"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_BIND[${INDEX}]}"
        else
          CONFIG_LINE="${CONFIG_LINE} --numactl_cpus"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_BIND[${INDEX}]}"
          CONFIG_LINE="${CONFIG_LINE} ${MYSQL_SERVER_CPUS[${INDEX}]}"
        fi
      fi
    fi
  elif test "x${TASKSET}" != "x"; then
    echo "TASKSET set to $TASKSET not supported"
    exit 1
  fi
}

set_up_server_cpus()
{
  if test "x$SERVER_CPUS" != "x" ; then
    SERVER_CPUS=`${ECHO} ${SERVER_CPUS} | ${SED} -e 's!\;! !g'`
    NUM_CPU_SETS="0"
    for CPU_SET in $SERVER_CPUS
    do
      MYSQL_SERVER_CPUS[${NUM_CPU_SETS}]=${CPU_SET}
      ((NUM_CPU_SETS+=1))
    done 
    if test "x$NUM_CPU_SETS" = "x1" ; then
      for ((i_susc= 0; i_susc < $NUM_MYSQL_SERVERS ; i_susc += 1))
      do
        MYSQL_SERVER_CPUS[${i_susc}]=$CPU_SET
      done
    else
      if test "x$NUM_CPU_SETS" != "x$NUM_MYSQL_SERVERS" ; then
        echo "Error number of SERVER_CPUS's must be either 1 or same as number of SERVER_HOST's"
        exit 1
      fi
    fi
  fi
}

set_up_server_bind()
{
  if test "x$SERVER_BIND" != "x" ; then
    SERVER_BIND=`${ECHO} ${SERVER_BIND} | ${SED} -e 's!\;! !g'`
    NUM_CPU_SETS="0"
    for CPU_SET in $SERVER_BIND
    do
      MYSQL_SERVER_BIND[${NUM_CPU_SETS}]=${CPU_SET}
      ((NUM_CPU_SETS+=1))
    done 
    if test "x$NUM_CPU_SETS" = "x1" ; then
      for ((i_susb= 0; i_susb < $NUM_MYSQL_SERVERS ; i_susb += 1))
      do
        MYSQL_SERVER_BIND[${i_susb}]=$CPU_SET
      done
    else
      if test "x$NUM_CPU_SETS" != "x$NUM_MYSQL_SERVERS" ; then
        echo "Error number of SERVER_BIND's must be either 1 or same as number of SERVER_HOST's"
        exit 1
      fi
    fi
  fi
}

set_up_server_domain_id()
{
  if test "x$BENCHMARK_TO_RUN" = "xflexAsynch" ; then
    if test "x$API_DOMAIN_ID" != "x" ; then
      API_DOMAIN_ID=`${ECHO} ${API_DOMAIN_ID} | ${SED} -e 's!\;! !g'`
      NUM_API_DOMAINS="0"
      for DOMAIN_ID in $API_DOMAIN_ID
      do
        API_DOMAIN_IDS[${NUM_API_DOMAINS}]=${DOMAIN_ID}
        ((NUM_API_DOMAINS+=1))
      done
      NUM_FLEX_ASYNCH_API_NODES="0"
      LOC_FLEX_API_HOSTS=`$ECHO $FLEX_ASYNCH_API_NODES | $SED -e 's!\;! !g'`
      for LOCAL_API_NODE in $FLEX_API_HOSTS
      do
        ((NUM_FLEX_ASYNCH_API_NODES+= 1))
      done
      if test "x$NUM_API_DOMAINS" != "x$NUM_FLEX_ASYNCH_API_NODES" ; then
        echo "Error number of API_DOMAIN_ID's must be same as number of FLEX_ASYNCH_API_NODES's"
        exit 1
      fi
    fi
  else
    if test "x$SERVER_DOMAIN_ID" != "x" ; then
      SERVER_DOMAIN_ID=`${ECHO} ${SERVER_DOMAIN_ID} | ${SED} -e 's!\;! !g'`
      NUM_SERVER_DOMAINS="0"
      for DOMAIN_ID in $SERVER_DOMAIN_ID
      do
        SERVER_DOMAIN_IDS[${NUM_SERVER_DOMAINS}]=${DOMAIN_ID}
        ((NUM_SERVER_DOMAINS+=1))
      done 
      if test "x$NUM_SERVER_DOMAINS" != "x$NUM_MYSQL_SERVERS" ; then
        echo "Error number of SERVER_DOMAIN_ID's must be same as number of SERVER_HOST's"
        exit 1
      fi
    fi
  fi
}

set_up_ndbd_domain_id()
{
  if test "x$NDBD_DOMAIN_ID" != "x" ; then
    NDBD_DOMAIN_ID=`${ECHO} ${NDBD_DOMAIN_ID} | ${SED} -e 's!\;! !g'`
    NUM_NDBD_DOMAINS="0"
    for DOMAIN_ID in $NDBD_DOMAIN_ID
    do
      NDBD_DOMAIN_IDS[${NUM_NDBD_DOMAINS}]=${DOMAIN_ID}
      ((NUM_NDBD_DOMAINS+=1))
    done 
    if test "x$NUM_NDBD_DOMAINS" != "x$NUM_NDBD_NODES" ; then
      echo "Error number of NDBD_DOMAIN_ID's must be same as number of NDBD_NODES's"
      exit 1
    fi
    if test "x$BENCHMARK_TO_RUN" = "xflexAsynch" ; then
      if test "x$API_DOMAIN_ID" = "x" ; then
        echo "Must set both NDBD_DOMAIN_ID and API_DOMAIN_ID if one of them is set"
        exit 1
      fi
    else
      if test "x$SERVER_DOMAIN_ID" = "x" ; then
        echo "Must set both NDBD_DOMAIN_ID and SERVER_DOMAIN_ID if one of them is set"
        exit 1
      fi
    fi
  else
    if test "x$BENCHMARK_TO_RUN" = "xflexAsynch" ; then
      if test "x$API_DOMAIN_ID" != "x" ; then
        echo "Must set both NDBD_DOMAIN_ID and API_DOMAIN_ID if one of them is set"
        exit 1
      fi
    else
      if test "x$SERVER_DOMAIN_ID" != "x" ; then
        echo "Must set both NDBD_DOMAIN_ID and SERVER_DOMAIN_ID if one of them is set"
        exit 1
      fi
    fi
  fi
}

set_up_benchmark_servers()
{
  if test "x$BENCHMARK_SERVERS" != "x" ; then
    NUM_BENCH_INSTANCES="0"
    for LOCAL_SERVER in $BENCHMARK_SERVERS
    do
      BENCHMARK_SERVER[$NUM_BENCH_INSTANCES]=$LOCAL_SERVER
      ((NUM_BENCH_INSTANCES+=1))
    done
    if test "x$BENCHMARK_TO_RUN" = "xsysbench" ; then
      if test "x$NUM_BENCH_INSTANCES" != "x$SYSBENCH_INSTANCES" ; then
        echo "Wrong number of BENCHMARK_SERVERS compared to SYSBENCH_INSTANCES"
        exit 1
      fi
    fi
  fi
}

set_up_server_host()
{
  NUM_MYSQL_SERVERS="0"
  for MYSQL_SERVER in $SERVER_HOST
  do
    MYSQL_SERVER_HOST[$NUM_MYSQL_SERVERS]=${MYSQL_SERVER}
    ((NUM_MYSQL_SERVERS+= 1))
  done
}

set_up_server_port()
{
  NUM_PORTS="0"
  for PORT_NUMBER in $SERVER_PORT
  do
    MYSQL_SERVER_PORT[$NUM_PORTS]=${PORT_NUMBER}
    ((NUM_PORTS+=1))
  done
  if test "x${NUM_PORTS}" = "x1" ; then
    for ((i_susp= 0; i_susp < $NUM_MYSQL_SERVERS ; i_susp += 1))
    do
      MYSQL_SERVER_PORT[${i_susp}]=${PORT_NUMBER}
    done
  else
    if test "x$NUM_PORTS" != "x$NUM_MYSQL_SERVERS" ; then
      echo "Error number of SERVER_PORT's must be either 1 or same as number of SERVER_HOST's"
      exit 1
    fi
  fi
}

set_up_ndb_recv_thread_cpu_mask()
{
  if test "x$NDB_RECV_THREAD_CPU_MASK" != "x" ; then
    NDB_RECV_THREAD_CPU_MASK=`${ECHO} ${NDB_RECV_THREAD_CPU_MASK} | ${SED} -e 's!\;! !g'`
    NUM_CPU_MASKS="0"
    for CPU_MASK in $NDB_RECV_THREAD_CPU_MASK
    do
      MYSQL_NDB_RECV_THREAD_CPU_MASK[${NUM_CPU_MASKS}]=${CPU_MASK}
      ((NUM_CPU_MASKS+=1))
    done 
    if test "x$NUM_CPU_MASKS" = "x1" ; then
      for ((i_sunrtcm= 0; i_sunrtcm < $NUM_MYSQL_SERVERS ; i_sunrtcm += 1))
      do
        MYSQL_NDB_RECV_THREAD_CPU_MASK[${i_sunrtcm}]=${CPU_MASK}
      done
    else
      if test "x$NUM_CPU_MASKS" != "x$NUM_MYSQL_SERVERS" ; then
        echo "Error number of NDB_RECV_THREAD_CPU_MASK's must be either 1 or same as number of SERVER_HOST's"
        exit 1
      fi
    fi
  fi
}

write_mgmd_lines()
{
  NODEID="0"
  NUM_NDB_MGMD_NODES="0"
  NDB_MGMD_NODES=`${ECHO} ${NDB_MGMD_NODES} | ${SED} -e 's!\;! !g'`
  for NDB_MGMD_NODE in $NDB_MGMD_NODES
  do
    ((NODEID+= 1))
    ((NUM_NDB_MGMD_NODES+= 1))
    CONFIG_LINE="$NODEID NDB_MGMD  $NDB_MGMD_NODE 0"
    write_conf $CONFIG_LINE
    add_remote_node $NDB_MGMD_NODE
  done
}

write_ndbd_lines()
{
    NDBD_NODES=`${ECHO} ${NDBD_NODES} | ${SED} -e 's!\;! !g'`
    NUM_NDBD_NODES="0"
    for NDBD_NODE in $NDBD_NODES
    do
      ((NODEID+= 1))
      ((NUM_NDBD_NODES+= 1))
      CONFIG_LINE="$NODEID NDBD      $NDBD_NODE 0"
      write_conf $CONFIG_LINE
      add_remote_node $NDBD_NODE
    done
}

write_mysqld_lines()
{
  set_up_server_host
  set_up_server_port
  set_up_server_cpus
  set_up_server_bind
  set_up_ndb_recv_thread_cpu_mask
  INDEX="0"
  for MYSQL_SERVER in $SERVER_HOST
  do
    ((NODEID+= 1))
    CONFIG_LINE="$NODEID       MYSQLD   "
    CONFIG_LINE="$CONFIG_LINE ${MYSQL_SERVER_HOST[${INDEX}]}"
    CONFIG_LINE="$CONFIG_LINE ${MYSQL_SERVER_PORT[${INDEX}]}"
    if test "x$MYSQL_SERVER_BASE" = "x5.6" || \
       test "x$MYSQL_SERVER_BASE" = "x5.7" || \
       test "x$MYSQL_SERVER_BASE" = "x8.0" ; then
      if test "x$NDB_RECV_THREAD_CPU_MASK" != "x" ; then
        CONFIG_LINE="${CONFIG_LINE} --ndb_recv_thread_cpu_mask"
        CONFIG_LINE="${CONFIG_LINE} ${MYSQL_NDB_RECV_THREAD_CPU_MASK[${INDEX}]}"
      fi
    fi
    if test "x$NDB_FORCE_SEND" != "xyes" ; then
      CONFIG_LINE="${CONFIG_LINE} --no-force-send"
    fi
    set_up_bind_cpus_config
    write_conf $CONFIG_LINE
    add_remote_node ${MYSQL_SERVER_HOST[${INDEX}]}
    ((INDEX+=1))
  done
}

write_dis_config_ini()
{
  MSG="Writing dis_config_c1.ini"
  output_msg
  CONF_FILE="${DEFAULT_DIR}/dis_config_c1.ini"
  ${ECHO} "#NODE_ID NODE_TYPE HOSTNAME PORT FLAGS" > ${CONF_FILE}
  if test "x${ENGINE}" = "xndb" ; then
    write_mgmd_lines
    write_ndbd_lines
    write_mysqld_lines
    if test "x$PERFORM_GENERATE_CONFIG_INI" = "xyes" ; then
# Also write NDB configuration file
      CONF_FILE="${DEFAULT_DIR}/config_c1.ini"
      echo "#Auto-generated config" > $CONF_FILE
      write_ndb_config
    fi
  else
# Non-NDB storage engine => 1 MySQL Server only, no other nodes"
    if test "x$SLAVE_HOST" != "x" ; then
      NUM_MYSQL_SERVERS="2"
    else
      NUM_MYSQL_SERVERS="1"
    fi
    set_up_server_cpus
    set_up_server_bind
    CONFIG_LINE="1       MYSQLD   "
    CONFIG_LINE="${CONFIG_LINE} ${SERVER_HOST}"
    CONFIG_LINE="${CONFIG_LINE} ${SERVER_PORT}"
    INDEX="0"
    set_up_bind_cpus_config
    write_conf ${CONFIG_LINE}
    add_remote_node ${SERVER_HOST}
    if test "x$SLAVE_HOST" != "x" ; then
#We run with replication enabled, so need a slave host as well
      CONFIG_LINE="2       MYSQLD_SLAVE   "
      CONFIG_LINE="${CONFIG_LINE} ${SLAVE_HOST}"
      CONFIG_LINE="${CONFIG_LINE} ${SLAVE_PORT}"
      INDEX="1"
      set_up_bind_cpus_config
      write_conf ${CONFIG_LINE}
      add_remote_node ${SLAVE_HOST}
    fi
  fi
}

set_up_taskset()
{
#Set-up BENCH_TASKSET
  if test "x$BENCH_TASKSET" = "x" ; then
    BENCH_TASKSET="$TASKSET"
  fi
  if test "x${BENCH_TASKSET}" != "x" && \
     test "x$BENCHMARK_TO_RUN" = "xsysbench" ; then
    if test "x${BENCH_TASKSET}" = "xtaskset" ; then
      if test "x${BENCHMARK_CPUS}" != "x" ; then
        BENCH_TASKSET="${BENCH_TASKSET} ${BENCHMARK_CPUS}"
      fi
    elif test "x${BENCH_TASKSET}" = "xnumactl" ; then
#Set-up TASKSET variable properly for start_ndb.sh-script
      if test "x${BENCHMARK_BIND}" != "x" ; then
        if test "x${SERVER_MEM_POLICY}" = "xinterleaved" ; then
          BENCH_TASKSET="${BENCH_TASKSET} --interleave=${BENCHMARK_BIND}"
        else
          BENCH_TASKSET="${BENCH_TASKSET} --membind=${BENCHMARK_BIND}"
        fi
        if test "x${BENCHMARK_CPUS}" != "x" ; then
          BENCH_TASKSET="${BENCH_TASKSET} --physcpubind=${BENCHMARK_CPUS}"
        else
          BENCH_TASKSET="${BENCH_TASKSET} --cpunodebind=${BENCHMARK_BIND}"
        fi
      fi
    else
      echo "TASKSET supports taskset and numactl only at the moment"
      exit 1
    fi
  fi
}

kill_nodes()
{
  IGNORE_FAILURE="yes"
  SSH_NODE="$1"
  exec_ssh_command killall -q flexAsynch mysqld ndbd ndbmtd ndb_mgm ndb_mgmd
}

check_kill_nodes()
{
  if test "x$KILL_NODES" = "xyes" ; then
    for NODE in ${REMOTE_NODES}
    do
      kill_nodes ${NODE}
    done
    if test "x${BENCHMARK_TO_RUN}" = "xflexAsynch" ; then
      FLEX_API_HOSTS=`$ECHO $FLEX_ASYNCH_API_NODES | $SED -e 's!\;! !g'`
      for LOCAL_API_NODE in $FLEX_API_HOSTS
      do
        kill_nodes ${LOCAL_API_NODE}
      done
    fi
    exit 0
  fi
}

clean_up_before_start()
{
  if test "x$SKIP_START" = "x" ; then
    if test "x$SKIP_INITIAL" = "x" ; then
      for NODE in ${REMOTE_NODES}
      do
        init_clean_up ${NODE}
      done
    fi
  fi
}

create_dbt2_test_files()
{
  if test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
    if test "x${PERFORM_GENERATE_DBT2_DATA}" = "xyes" ; then
      COMMAND="${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/create_dbt2_files.sh"
      COMMAND="${COMMAND} --default-directory ${DEFAULT_DIR}"
      COMMAND="${COMMAND} --data_dir ${DBT2_DATA_DIR}"
      COMMAND="${COMMAND} --base_dir ${SRC_INSTALL_DIR}/${DBT2_VERSION}"
      COMMAND="${COMMAND} --num_warehouses ${DBT2_WAREHOUSES}"
      COMMAND="${COMMAND} --first-warehouse 1"
      exec_command ${COMMAND}
    fi
  fi
}

clean_up_output()
{
  exec_command ${RM} -rf ${DEFAULT_DIR}/dbt2_output
}

fix_server_port()
{
  SERVER_PORT=`${ECHO} ${SERVER_PORT} | ${SED} -e 's!\;! !g'`
}

fix_server_host()
{
  SERVER_HOST=`${ECHO} ${SERVER_HOST} | ${SED} -e 's!\;! !g'`
}

fix_benchmark_servers()
{
  BENCHMARK_SERVERS=`${ECHO} ${BENCHMARK_SERVERS} | ${SED} -e 's!\;! !g'`
}

calc_num_server_instances()
{
  calc_num_server_hosts
  calc_num_server_ports
  if test "x$NUM_SERVER_HOSTS" != "x$NUM_SERVER_PORTS" ; then
    if test "x$NUM_SERVER_PORTS" = "x1" ; then
      NUM_SERVER_INSTANCES="$NUM_SERVER_HOSTS"
    elif test "x$NUM_SERVER_HOSTS" = "x1" ; then
      NUM_SERVER_INSTANCES="$NUM_SERVER_PORTS"
    else
      echo "Inconsistent number of SERVER_HOSTs and SERVER_PORTs"
      exit 1
    fi
  else
    NUM_SERVER_INSTANCES="$NUM_SERVER_PORTS"
  fi
}

calc_num_server_hosts()
{
  NUM_SERVER_HOSTS="0"
  for LOC_SERVER_HOST in ${SERVER_HOST}
  do
    ((NUM_SERVER_HOSTS += 1))
  done
}

calc_num_server_ports()
{
  NUM_SERVER_PORTS="0"
  for LOC_SERVER_PORT in ${SERVER_PORT}
  do
    ((NUM_SERVER_PORTS += 1))
  done
}

set_first_server_host()
{
  FIRST_SERVER_HOST=
  LOC_SERVER_INSTANCE="0"
  for LOC_SERVER_HOST in ${SERVER_HOST}
  do
    if test "x${LOC_SERVER_INSTANCE}" = "x${SERVER_INSTANCE}" ; then
      FIRST_SERVER_HOST=""
    fi
    if test "x${FIRST_SERVER_HOST}" = "x" ; then
      FIRST_SERVER_HOST="${LOC_SERVER_HOST}"
    fi
    ((LOC_SERVER_INSTANCE = LOC_SERVER_INSTANCE + 1))
  done
}

set_first_server_port()
{
  FIRST_SERVER_PORT=
  LOC_SERVER_INSTANCE="0"
  for LOC_SERVER_PORT in ${SERVER_PORT}
  do
    if test "x${LOC_SERVER_INSTANCE}" = "x${SERVER_INSTANCE}" ; then
      FIRST_SERVER_PORT=""
    fi
    if test "x${FIRST_SERVER_PORT}" = "x" ; then
      FIRST_SERVER_PORT="${LOC_SERVER_PORT}"
    fi
    ((LOC_SERVER_INSTANCE = LOC_SERVER_INSTANCE + 1))
  done
}

run_sysbench_step()
{
  for ((i_rss = 0; i_rss < SYSBENCH_INSTANCES; i_rss += 1))
  do
    ((SERVER_INSTANCE = i_rss % NUM_SERVER_INSTANCES))
    set_first_server_host
    set_first_server_port
    if test "x$SYSBENCH_INSTANCES" != "x1" && \
       test "x$PARALLELIZE" = "xyes" ; then
      PIPE_FILE="$DEFAULT_DIR/run_${i_rss}.log"
    fi
    BENCHMARK_SERVER_CMD=
    if test "x$BENCHMARK_SERVERS" != "x" ; then
      BENCHMARK_SERVER_CMD="--benchmark-server ${BENCHMARK_SERVER[${i_rss}]}"
    fi
    DB_USED="${SYSBENCH_DB}_${i_rss}"
    exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
      --default-directory ${DEFAULT_DIR} \
      --benchmark sysbench \
      --sysbench-test ${SYSBENCH_TEST} \
      --thread-count ${THREAD_COUNT} \
      --benchmark-instance ${i_rss} \
      --sysbench-test-number ${SYSBENCH_TEST_NUMBER} \
      ${VERBOSE_FLAG} --skip-start --skip-stop \
      --server-host ${FIRST_SERVER_HOST} \
      --server-port ${FIRST_SERVER_PORT} \
      --database ${DB_USED} \
      --benchmark-step ${SYSBENCH_STEP} \
      $BENCHMARK_SERVER_CMD
    PIPE_FILE=
  done
  if test "x$SYSBENCH_INSTANCES" != "x1" && \
     test "x$PARALLELIZE" = "xyes" ; then
    wait
  fi
}

set_up_ndb_index_stat()
{
  if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
    NDB_INDEX_STAT_ENABLE="0"
  elif test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
    NDB_INDEX_STAT_ENABLE="0"
  elif test "x${BENCHMARK_TO_RUN}" = "xdbt3" ; then
    NDB_INDEX_STAT_ENABLE="1"
  fi
}

generate_configs()
{
  if test "x$PERFORM_GENERATE" = "xyes" ; then
    write_dis_config_ini
    write_iclaustron_conf
    write_dbt2_conf
    if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
      write_sysbench_conf
    fi
  else
    REMOTE_NODES="${FIRST_SERVER_HOST}"
  fi
}

create_innodb_log_dir()
{
  if test "x$INNODB_LOG_DIR" != "x" ; then
    $MKDIR -p $INNODB_LOG_DIR
  fi
}

check_parameters()
{
  if test "x$MYSQL_SERVER_BASE" != "x5.1" && \
     test "x$MYSQL_SERVER_BASE" != "x5.5" && \
     test "x$MYSQL_SERVER_BASE" != "x5.6" && \
     test "x$MYSQL_SERVER_BASE" != "x5.7" && \
     test "x$MYSQL_SERVER_BASE" != "x8.0"; then
    ${ECHO} "Only support MYSQL_SERVER_BASE equal to any of 5.1, 5.5, 5.6, 5.7 or 8.0"
    exit 1
  fi
  if test "x${MYSQL_BIN_INSTALL_DIR}" = "x" ; then
    ${ECHO} "MYSQL_BIN_INSTALL_DIR is mandatory to set"
    ${ECHO} "MYSQL_BIN_INSTALL_DIR is mandatory to set" > ${LOG_FILE}
    exit 1
  fi
}

check_client_mysql_version()
{
#For non-gcc compilers it's a good idea to still use gcc-compiled library
#for benchmark programs
# CLIENT_MYSQL_VERSION was introduced for slave MySQL Servers.
#
  if test "x$CLIENT_MYSQL_VERSION" = "x" ; then
    CLIENT_MYSQL_VERSION="$MYSQL_VERSION"
  fi
#
# MYSQL_CLIENT_VERSION is pointing to MySQL installation used by benchmark
# programs
# MYSQL_VERSION is pointing to MySQL installation used by MySQL Server,
# NDB data nodes and NDB management programs
# It is also possible to point MySQL Server and clients to use MYSQL_SERVER_VERSION
# and NDB programs to use MYSQL_NDB_VERSION.
#
  if test "x$MYSQL_CLIENT_VERSION" = "x" ; then
    MYSQL_CLIENT_VERSION="$MYSQL_VERSION"
  fi
  if test "x$MYSQL_NDB_VERSION" = "x" ; then
    MYSQL_NDB_VERSION="$MYSQL_VERSION"
  fi
  if test "x$MYSQL_SERVER_VERSION" = "x" ; then
    MYSQL_SERVER_VERSION="$MYSQL_VERSION"
  fi
  if test "x$MYSQL_SERVER_BASE" = "x" ; then
    MYSQL_SERVER_BASE="$MYSQL_BASE"
  fi
  if test "x$MYSQL_NDB_BASE" = "x" ; then
    MYSQL_NDB_BASE="$MYSQL_BASE"
  fi
}

run_sysbench()
{
#
#-----------------------------
#Run Sysbench execution script
#-----------------------------
#
  if test "x$SKIP_START" = "x" ; then
    exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
       --default-directory ${DEFAULT_DIR} \
       --benchmark sysbench \
       ${VERBOSE_FLAG} --skip-run --skip-stop ${SKIP_INITIAL}
  fi
  if test "x$SKIP_RUN" = "x" ; then
#
# We execute parallel sysbench programs in lock-step mode. We start by all
# sysbench instances doing the prepare stage. Next we move on to running the
# actual benchmark stage for all instances. Next we move on to the cleanup
# stage where all tables and data is removed. Finally we run the analysis
# of the benchmark data for all steps. After this we have produced a set of
# final_result_NUM.txt files that contains the result of each sysbench
# instance.
#
    for ((i1 = 0; i1 < SYSBENCH_INSTANCES; i1++))
    do
      PIPE_FILE="$DEFAULT_DIR/run_${i1}.log"
      ${ECHO} "Start log file" > ${PIPE_FILE}
    done
    PIPE_FILE=
    THREAD_COUNTS_TO_RUN=`${ECHO} $THREAD_COUNTS_TO_RUN | sed -e 's!\;! !g'`
    for ((i1 = 0; i1 < NUM_TEST_RUNS; i1 += 1))
    do
      for ((i2 = 0; i2 < SYSBENCH_INSTANCES; i2++))
      do
        RESULT_DIR="${DEFAULT_DIR}/sysbench_results"
        TEST_FILE_NAME="${RESULT_DIR}/${SYSBENCH_TEST}_${i2}_${i1}.res"
        ${ECHO} "Running ${SYSBENCH_TEST} in instance ${i2} and in run ${i1}" > ${TEST_FILE_NAME}
      done

      for THREAD_COUNT in ${THREAD_COUNTS_TO_RUN}
      do
        SYSBENCH_TEST_NUMBER="${i1}"
# Perform prepare step (Create tables and fill them)
        calc_num_server_instances
        SYSBENCH_STEP="prepare"
        PARALLELIZE="no"
        run_sysbench_step
        ${SLEEP} ${BETWEEN_RUNS}
# Perform benchmark step (Run actual benchmark)
        calc_num_server_instances
        SYSBENCH_STEP="run"
        PARALLELIZE="yes"
        run_sysbench_step
# Perform cleanup step (Delete tables)
        calc_num_server_instances
        SYSBENCH_STEP="cleanup"
        PARALLELIZE="no"
        run_sysbench_step
      done
    done
    SAVE_SYSBENCH_INSTANCES="${SYSBENCH_INSTANCES}"
    SYSBENCH_TEST_NUMBER="$SYSBENCH_INSTANCES"
    SYSBENCH_INSTANCES="1"
# Analyse benchmark data and produce benchmark results
    calc_num_server_instances
    SYSBENCH_STEP="analyze"
    run_sysbench_step
    SYSBENCH_INSTANCES="${SAVE_SYSBENCH_INSTANCES}"
  fi
  if test "x$SKIP_STOP" = "x" ; then
    echo "Stop cluster from bench_run.sh"
    exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
       --default-directory ${DEFAULT_DIR} \
       --benchmark sysbench \
       ${VERBOSE_FLAG} --skip-start --skip-run
  fi
}

run_dbt2()
{
#
#-------------------------
#Run DBT2 execution script
#-------------------------
#
  $MKDIR -p $DEFAULT_DIR/dbt2_output
  exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
       --default-directory ${DEFAULT_DIR} \
       --benchmark dbt2 \
       ${VERBOSE_FLAG} ${SKIP_RUN} ${SKIP_START} ${SKIP_STOP}\
       ${SKIP_LOAD_DBT2} ${SKIP_INITIAL}
}

run_dbt3()
{
#
#-------------------------
#Run DBT2 execution script
#-------------------------
#
  $MKDIR -p $DEFAULT_DIR/dbt2_output
  exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
       --default-directory ${DEFAULT_DIR} \
       --benchmark dbt3 \
       ${VERBOSE_FLAG} ${SKIP_RUN} ${SKIP_START} ${SKIP_STOP}
}

run_flexAsynch()
{
#
#-------------------------------
#Run flexAsynch execution script
#-------------------------------
#
  exec_command ${SRC_INSTALL_DIR}/${DBT2_VERSION}/scripts/run_oltp.sh \
       --default-directory ${DEFAULT_DIR} \
       --benchmark flexAsynch \
       ${VERBOSE_FLAG} ${SKIP_RUN} ${SKIP_START} ${SKIP_STOP} \
       ${SKIP_LOAD_DBT2} ${SKIP_INITIAL}
}

handle_cleanup()
{
  if test "x${PERFORM_CLEANUP}" = "xyes" ; then
    clean_up_local_bin
    for NODE in ${REMOTE_NODES}
    do
      clean_up_remote_bin ${NODE}
    done
    if test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
      clean_up_output
    fi
    clean_up_local_src
    remove_generated_files
  fi
}

PWD=pwd
CD=cd
RM=rm
SCP=scp
MKDIR=mkdir
SSH=ssh
TAR=
ECHO=echo
SLEEP=sleep
CP=cp
SED=sed
CAT=cat
MAKE=
FEEDBACK_PREPARED="no"
COMPILER_PARALLELISM="16"

#Sleep parameters for sysbench
BETWEEN_RUNS="1"              # Time between runs to avoid checkpoints
AFTER_INITIAL_RUN="30"        # Time after initial run
AFTER_SERVER_START="10"       # Wait for MySQL Server to start
BETWEEN_CREATE_DB_TEST="5"    # Time between each attempt to create DB
NUM_CREATE_DB_ATTEMPTS="40"   # Max number of attempts before giving up
AFTER_SERVER_STOP="5"         # Time to wait after stopping MySQL Server

#Parameters for replication setup
NUM_CHANGE_MASTER_ATTEMPTS="12"
BETWEEN_CHANGE_MASTER_TEST="15"

#NDB Default Config values
NDB_INDEX_STAT_AUTO_CREATE="1"
NDB_INDEX_STAT_AUTO_UPDATE="1"
NDB_MAX_NO_OF_CONCURRENT_TRANSACTIONS="131072"
NDB_MAX_NO_OF_CONCURRENT_OPERATIONS="131072"
NDB_MAX_NO_OF_CONCURRENT_SCANS="500"
NDB_MAX_NO_OF_LOCAL_SCANS="8000"
NDB_NO_OF_FRAGMENT_LOG_FILES="8"
NDB_FRAGMENT_LOG_FILE_SIZE="256M"
NDB_TIME_BETWEEN_LOCAL_CHECKPOINTS=
NDB_TIME_BETWEEN_GLOBAL_CHECKPOINTS=
NDB_READ_BACKUP="no"
NDB_FULLY_REPLICATED="no"
NDB_DEFAULT_COLUMN_FORMAT="FIXED"
NDB_DATA_NODE_NEIGHBOUR=
NDB_COMPRESSED_LCP="0"
NDB_COMPRESSED_BACKUP="0"
NDB_SHARED_GLOBAL_MEMORY="200M"
NDB_USE_ROW_CHECKSUM="yes"
DISK_CHECKPOINT_SPEED="10M"
NDB_MIN_DISK_WRITE_SPEED=
NDB_MAX_DISK_WRITE_SPEED=
NDB_MAX_DISK_WRITE_SPEED_OTHER_NODE_RESTART=
NDB_MAX_DISK_WRITE_SPEED_OWN_RESTART=
NDB_SCHEDULER_RESPONSIVENESS=
NDB_SCHED_SCAN_PRIORITY=
NDB_REPLICAS="2"
NDB_DATA_MEMORY="3G"
NDB_INDEX_MEMORY="300M"
NDB_DISK_PAGE_BUFFER_MEMORY=
USE_NDBMTD="yes"
NDB_RESTART_TEST="no"
NDB_RESTART_TEST_INITIAL="no"
NDB_RESTART_NODE="1"
NDB_RESTART_NODE2=
NDB_RESTART_NODE3=
NDB_RESTART_NODE4=
NDB_RESTART_NODE5=
NDB_RESTART_NODE6=
NDB_RESTART_NODE7=
NDB_RESTART_NODE8=
NDB_EXECUTE_CPU=
NDB_MAINT_CPU=
NDB_TIME_BETWEEN_WATCHDOG_CHECK_INITIAL="180000"
NDB_SCHEDULER_SPIN_TIMER=
NDB_SPINTIME_PER_CALL=
NDB_ENABLE_ADAPTIVE_SPINNING="yes"
NDB_ALLOWED_SPIN_OVERHEAD=
NDB_EXTRA_SEND_BUFFER_MEMORY="16M"
NDB_SEND_BUFFER_MEMORY="2M"
NDB_SHM_SIZE="2M"
NDB_SHM_SPINTIME="0"
NDB_SHM_SEND_BUFFER_MEMORY="2M"
NDB_TCP_SEND_BUFFER_MEMORY=
NDB_RECEIVE_BUFFER_MEMORY="2M"
NDB_TOTAL_SEND_BUFFER_MEMORY=
NDB_TCP_RECEIVE_BUFFER_MEMORY=
NDB_REDO_BUFFER="64M"
NDB_NUMA="1"
NDB_MAX_START_WAIT="10000"
NDB_EXTRA_CONNECTIONS="4"
NDB_THREAD_CONFIG=
NDB_MAX_NO_OF_EXECUTION_THREADS=""
NDB_REALTIME_SCHEDULER=
NDB_ENABLE_REDO_CONTROL=
NDB_RECOVERY_WORK=
NDB_INSERT_RECOVERY_WORK=
CLUSTER_HOME=
NDB_DISK_IO_THREADPOOL=
NDB_NO_OF_FRAGMENT_LOG_PARTS=
USE_NDB_O_DIRECT=
CORE_FILE_USED="no"
NDB_MULTI_CONNECTION=
NDB_RECV_THREAD_ACTIVATION_THRESHOLD=
NDB_RECV_THREAD_CPU_MASK=
NDB_FORCE_SEND="yes"
NDB_START_MAX_WAIT="100"
NDB_MGMD_PORT="1186"
NDB_AUTOINCREMENT_OPTION="256"
ENGINE_CONDITION_PUSHDOWN_OPTION="yes"
NDB_SERVER_PORT=
NDB_COLOCATED_LDM_AND_TC=
NDB_NODE_GROUP_TRANSPORTERS=
NDB_USE_DISK_DATA="no"
NDB_DISK_FILE_PATH=
NDB_TABLESPACE_SIZE="12G"
NDB_EXTENT_SIZE="16M"
NDB_UNDO_LOGFILE_SIZE="4G"
NDB_UNDO_BUFFER_SIZE="256M"
NDB_PARTITIONS_PER_NODE="0"
NDB_INDEX_STAT_ENABLE="1"

#Sysbench parameters
SYSBENCH_RESULTS=
SYSBENCH_TEST="oltp_rw" # Which sysbench test should we run
NUM_TEST_RUNS="1" # Number of loops to run tests in
MAX_TIME="60"    # Time to run each test
ENGINE="ndb"   # Engine used to run test
THREAD_COUNTS_TO_RUN="1" #Thread counts to use in runs
SYSBENCH_ROWS="1000000" # Number of rows per sysbench table
SB_USE_TRX=             # Use transaction or not
SB_DIST_TYPE="uniform"  # Distribution type of data
TRX_ENGINE=             # Transaction engine
SB_USE_AUTO_INC=        # Use auto increment on sysbench tables
SB_SYSBENCH_64BIT_BUILD="no"
SB_USE_SECONDARY_INDEX="no" # Use secondary index in Sysbench test
SB_USE_MYSQL_HANDLER="no" # Use MySQL Handler statements for point selects
SB_NUM_PARTITIONS="0"    # Number of partitions to use in Sysbench test table
SB_USE_RANGE="no"        # If number of partitions set, use range otherwise key
SB_NUM_TABLES="1"        # Number of test tables
SB_USE_FAST_GCC="yes"    # If set to "y" will use -O3 and -m64 in compiling
SB_TX_RATE=              # Use fixed transaction rate
SB_TX_JITTER=            # Use jitter of transaction rate
SB_AVOID_DEADLOCKS="yes" # Avoid update orders that can cause deadlocks
SB_POINT_SELECTS="10"    # Default 10 PK lookups per transaction
SB_USE_FILTER="no"       # Use filters in range queries to only return 1 row
SB_RANGE_SIZE="100"      # Default 100 rows per scan
SB_SIMPLE_RANGES="1"     # Default 1 simple range scan per transaction
SB_SUM_RANGES="1"        # Default 1 sum range scan per transaction
SB_ORDER_RANGES="1"      # Default 1 order range scan per transaction
SB_DISTINCT_RANGES="1"   # Default 1 distinct range scan per transaction
SB_USE_IN_STATEMENT="0"  # If set use IN-statement to do 10 PK lookup per SQL
SB_MAX_REQUESTS="0"      # Max requests != 0 => #requests instead of time
SB_PARTITION_BALANCE=    # Set different partitioning scheme
SB_NONTRX_MODE="insert"  # Nontrx-mode when running nontrx mode test
                         # point select query
SB_VERBOSITY="4"         # Debug level, 5 is highest level
SYSBENCH_DB="sbtest"     # Sysbench database name used in this test run

#Parameters specifying where MySQL Server is hosted
SERVER_HOST="127.0.0.1"        # Hostname of MySQL Server
SERVER_PORT="3306"             # Port of MySQL Server to connect to
SERVER_DOMAIN_ID=              # Location domain id of MySQL Servers
SLAVE_HOST=                    # Hostname of Slave MySQL Server
SLAVE_PORT="3307"              # Port of Slave MySQL Server to connect to
SLAVE_PARALLEL_TYPE="logical_clock" # Multi-threaded slave type
SLAVE_PARALLEL_WORKERS="1"     # Number of slave applier threads
WAIT_STOP=                     # Wait before starting stop to allow e.g. for slaves to catch up

#Set taskset to blank if no binding to CPU and memory is wanted
TASKSET=                      # Program to bind program to CPU's
                              # Currently taskset and numactl suported
BENCH_TASKSET=
SERVER_CPUS=                  # CPU's to bind for MySQL Server
SERVER_BIND=                  # Bind to NUMA nodes when TASKSET=numactl
SERVER_MEM_POLICY="interleaved" # Use interleaved/local memory policy with numactl
#Same parameters for benchmark program
BENCHMARK_CPUS=
BENCHMARK_BIND=
BENCHMARK_MEM_POLICY="local"

#Compiler to use, default is gcc
COMPILER=""
USE_DBT2_BUILD="yes"
COMPILER_PARALLELISM=

#Defaults for DBT2 parameters
DBT2_PARTITION_TYPE="KEY"
DBT2_NUM_PARTITIONS=""
DBT2_PK_USING_HASH="--using-hash"
DBT2_INTERMEDIATE_TIMER_RESOLUTION="3"
FIRST_CLIENT_PORT="30000"
DBT2_WAREHOUSES="10"
DBT2_TERMINALS="1"
DBT2_RUN_WAREHOUSES="1;2;4"
DBT2_NUM_SERVERS="1"
DBT2_TIME="90"
DBT2_SCI=
DBT2_SPREAD=
DBT2_LOADERS="8"
DBT2_GENERATE_FILES="no"
DBT2_USE_ALTERED_MODE="no"

#Defaults for DBT3 tests
DBT3_DATA_PATH="/export/home2/mronstro/dbt3/10"
DBT3_ONLY_CREATE="no"
DBT3_PARALLEL_LOAD="yes"
DBT3_USE_BOTH_NDB_AND_INNODB="no"
DBT3_USE_PARTITION_KEY="yes"
DBT3_PARTITION_BALANCE=
DBT3_READ_BACKUP="1"

#Defaults for iClaustron
RUN_AS_ROOT="no"
DATA_DIR_BASE=
TMP_BASE="/tmp"
MYSQL_BASE="5.7"
MYSQL_SERVER_BASE=
MYSQL_NDB_BASE=
BOOST_VERSION=
USE_MALLOC_LIB="no"
MALLOC_LIB="/usr/lib64/libtcmalloc_minimal.so.0"
PREPARE_JEMALLOC=
INNODB_BUFFER_POOL_INSTANCES="12"
INNODB_LOG_DIR=""
INNODB_DIRTY_PAGES_PCT=""
INNODB_OLD_BLOCKS_PCT=""
INNODB_SPIN_WAIT_DELAY=""
INNODB_STATS_ON_METADATA="off"
INNODB_STATS_ON_MUTEXES=
INNODB_MAX_PURGE_LAG=""
INNODB_SUPPORT_XA=""
INNODB_FILE_FORMAT="barracuda"
INNODB_READ_AHEAD_THRESHOLD="63"
INNODB_ADAPTIVE_HASH_INDEX="0"
INNODB_READ_IO_THREADS="8"
INNODB_WRITE_IO_THREADS="8"
INNODB_THREAD_CONCURRENCY="0"
INNODB_BUFFER_POOL_SIZE="8192M"
INNODB_LOG_FILE_SIZE="2000M"
INNODB_LOG_BUFFER_SIZE="256M"
INNODB_LOG_FILES_IN_GROUP=
INNODB_PAGE_CLEANERS=
INNODB_USE_NATIVE_AIO=
INNODB_FLUSH_LOG_AT_TRX_COMMIT="2"
INNODB_IO_CAPACITY="200"
INNODB_MAX_IO_CAPACITY=""
INNODB_FLUSH_METHOD=""
INNODB_NUM_PURGE_THREAD="1"
INNODB_FILE_PER_TABLE=""
INNODB_CHANGE_BUFFERING="all"
INNODB_DOUBLEWRITE="yes"
INNODB_MONITOR="no"
INNODB_FLUSH_NEIGHBOURS="no"
USE_LARGE_PAGES=""
LOCK_ALL=""
SORT_BUFFER_SIZE="524288"
KEY_BUFFER_SIZE="50M"
GRANT_TABLE_OPTION="--skip-grant-tables"
MAX_HEAP_TABLE_SIZE="1000M"
TMP_TABLE_SIZE="100M"
MAX_TMP_TABLES="100"
TABLE_CACHE_SIZE="4000"
META_DATA_CACHE_SIZE=""
TABLE_CACHE_INSTANCES="64"
USE_SUPERSOCKET=
USE_INFINIBAND=
SUPERSOCKET_LIB=
INFINIBAND_LIB=
TRANSACTION_ISOLATION=
RELAY_LOG=
BINLOG=
SYNC_BINLOG="1"
BINLOG_ORDER_COMMITS=
BINLOG_GROUP_COMMIT_DELAY="0"
BINLOG_GROUP_COMMIT_COUNT="0"
USE_DOCKER="no"
USE_SUDO_DOCKER="no"
USE_SELINUX="yes"
CHARACTER_SET_SERVER="latin1"
COLLATION_SERVER="latin1_swedish_ci"

#Defaults for flexAsynch
FLEX_ASYNCH_API_NODES=
FLEX_ASYNCH_NUM_THREADS="16"
FLEX_ASYNCH_NUM_PARALLELISM="32"
FLEX_ASYNCH_NUM_OPS_PER_TRANS="1"
FLEX_ASYNCH_EXECUTION_ROUNDS="500"
FLEX_ASYNCH_NUM_ATTRIBUTES="25"
FLEX_ASYNCH_ATTRIBUTE_SIZE="1"
FLEX_ASYNCH_NO_LOGGING="no"
FLEX_ASYNCH_FORCE_FLAG="force"
FLEX_ASYNCH_USE_WRITE="no"
FLEX_ASYNCH_USE_LOCAL="0"
FLEX_ASYNCH_NUM_MULTI_CONNECTIONS="1"
FLEX_ASYNCH_WARMUP_TIMER="10"
FLEX_ASYNCH_EXECUTION_TIMER="30"
FLEX_ASYNCH_COOLDOWN_TIMER="10"
FLEX_ASYNCH_NEW="-new"
FLEX_ASYNCH_NO_HINT=
FLEX_ASYNCH_DEF_THREADS="3"
FLEX_ASYNCH_END_AFTER_CREATE="no"
FLEX_ASYNCH_END_AFTER_INSERT="no"
FLEX_ASYNCH_END_AFTER_UPDATE="no"
FLEX_ASYNCH_END_AFTER_READ="no"
FLEX_ASYNCH_END_AFTER_DELETE="no"
FLEX_ASYNCH_NUM_TABLES="1"
FLEX_ASYNCH_NUM_INDEXES="0"
FLEX_ASYNCH_NO_UPDATE=
FLEX_ASYNCH_NO_DELETE=
FLEX_ASYNCH_NO_READ=
FLEX_ASYNCH_NO_DROP=
FLEX_ASYNCH_RECV_CPUS=
FLEX_ASYNCH_DEF_CPUS=
FLEX_ASYNCH_EXEC_CPUS=
FLEX_ASYNCH_MAX_INSERTERS="0"

#Defaults for this build script
SSH_PORT="22"
SSH_USER=
WINDOWS_REMOTE="no"
BUILD_REMOTE="no"
INSTALL_REMOTE="no"
CMAKE_GENERATOR="Visual;Studio;9;2008;Win64"
USE_FAST_MYSQL="yes"
TEST_DESCRIPTION=""

#Variable Declarations
MYSQL_BIN_INSTALL_DIR=
REMOTE_SRC_INSTALL_DIR=
BIN_INSTALL_DIR=
USE_BINARY_MYSQL_TARBALL="yes"
SRC_INSTALL_DIR=
CONFIG_FILE=
LOG_FILE=
SSH_CMD=
PIPE_FILE=

REMOTE_NODES=
DEFAULT_DIR=
VERBOSE=
VERBOSE_FLAG=
SKIP_LOAD_DBT2=
PERFSCHEMA_FLAG=
NUM_MYSQL_SERVERS="1"
USE_MYISAM_FOR_ITEM=
MSG=
WITH_DEBUG=
DEBUG_FLAG="no"
PACKAGE=
FAST_FLAG=
WITH_PERFSCHEMA_FLAG="yes"
WITH_NDB_TEST_FLAG=""
LINK_TIME_OPTIMIZER_FLAG=
MSO_FLAG=
COMPILER_FLAG=
CLIENT_MYSQL_VERSION=
MYSQL_CLIENT_VERSION=
MYSQL_VERSION=
MYSQL_SERVER_VERSION=
MYSQL_NDB_VERSION=
FEEDBACK_FLAG=
FEEDBACK_COMPILATION=
THREAD_REGISTER_CONFIG=
THREADPOOL_SIZE=
THREADPOOL_ALGORITHM=
THREADPOOL_STALL_LIMIT=
THREADPOOL_PRIO_KICKUP_TIMER=
MAX_CONNECTIONS="1000"
KILL_NODES="no"
SERVER_INSTANCE="0"

PERFORM_BUILD_LOCAL="no"
PERFORM_BUILD_REMOTE="no"
PERFORM_BUILD_MYSQL="no"
PERFORM_BUILD_BENCH="no"
PERFORM_GENERATE="no"
PERFORM_GENERATE_CONFIG_INI="no"
PERFORM_GENERATE_DBT2_DATA=
PERFORM_CLEANUP="no"
SKIP_START="--skip-start"
SKIP_STOP="--skip-stop"
SKIP_INITIAL=
SKIP_RUN=
SYSBENCH_INSTANCES="1"
PERFORM_INIT="no"
check_support_programs

while test $# -gt 0
do
  case $1 in
  --default-directory )
    shift
    DEFAULT_DIR="$1"
    ;;
  --init )
    PERFORM_INIT="yes"
    PERFORM_BUILD_LOCAL="yes"
    PERFORM_BUILD_REMOTE="yes"
    PERFORM_BUILD_BENCH="yes"
    PERFORM_BUILD_MYSQL="yes"
    PERFORM_GENERATE="yes"
    PERFORM_GENERATE_CONFIG_INI="yes"
    SKIP_START=
    ;;
  --skip-build-mysql )
    PERFORM_BUILD_MYSQL="no"
    PERFORM_BUILD_REMOTE="no"
    ;;
  --build-bench )
    PERFORM_BUILD_BENCH="yes"
    PERFORM_BUILD_LOCAL="yes"
    PERFORM_BUILD_REMOTE="yes"
    ;;
  --build )
    PERFORM_BUILD_LOCAL="yes"
    PERFORM_BUILD_REMOTE="yes"
    PERFORM_BUILD_MYSQL="yes"
    SKIP_START="--skip-start"
    ;;
  --build-mysql )
    PERFORM_BUILD_LOCAL="yes"
    PERFORM_BUILD_REMOTE="yes"
    PERFORM_BUILD_MYSQL="yes"
    SKIP_START="--skip-start"
    ;;
  --build-remote )
    BUILD_REMOTE="yes"
    ;;
  --windows-remote )
    WINDOWS_REMOTE="yes"
    ;;
  --generate )
    PERFORM_GENERATE="yes"
    PERFORM_GENERATE_CONFIG_INI="yes"
    ;;
  --skip-generate-config-ini )
    PERFORM_GENERATE_CONFIG_INI="no"
    ;;
  --generate-dbt2-data )
    PERFORM_GENERATE_DBT2_DATA="yes"
    ;;
  --start )
    SKIP_START=
    SKIP_INITIAL=
    ;;
  --start-no-initial )
    SKIP_START=
    SKIP_INITIAL=--skip-initial
    ;;
  --skip-run )
    SKIP_RUN="--skip-run"
    ;;
  --skip-start )
    SKIP_START="--skip-start"
    ;;
  --skip-stop )
    SKIP_START="--skip-stop"
    ;;
  --stop )
    SKIP_STOP=
    ;;
  --cleanup )
    PERFORM_CLEANUP="yes"
    ;;
  --skip-load-dbt2 )
    SKIP_LOAD_DBT2="--skip-load-dbt2"
    ;;
  --sysbench_instances )
    shift
    SYSBENCH_INSTANCES="$1"
    ;;
  --kill-nodes )
    KILL_NODES="yes"
    ;;
  --verbose )
    VERBOSE="yes"
    VERBOSE_FLAG="--verbose"
    ;;
  *)
    ${ECHO} "No such option $1, only default-directory can be provided"
    usage
    exit 1
  esac
  shift
done


CONFIG_FILE="${DEFAULT_DIR}/autobench.conf"
BIN_INSTALL_DIR="${DEFAULT_DIR}/basedir"
SRC_INSTALL_DIR="${DEFAULT_DIR}/src"
LOG_FILE="${DEFAULT_DIR}/build_prepare.log"

${ECHO} "Starting automated benchmark suite" > ${LOG_FILE}

#
# The user specified configuration information is placed in autobench.conf
# in a directory specified by the user. We use this information to write
# the iclaustron.conf-file that drives the management script that starts
# and stops NDB and MySQL programs this also includes the dis_config_c1.ini
# file, we also use it to write dbt2.conf that
# is used to drive the execution of the DBT2 benchmark and finally we use
# the information to write the sysbench.conf which is used to drive the
# sysbench benchmark. The autobench.conf also contains other parameters
# used by this script to build and copy binaries to remote nodes.
#

read_autobench_conf
check_client_mysql_version
check_parameters
set_compiler_flags
fix_server_host
fix_server_port
fix_benchmark_servers
set_up_benchmark_servers
set_first_server_host
set_first_server_port
set_up_taskset
set_up_ndb_index_stat
generate_configs
check_kill_nodes
clean_up_before_start
init_tarball_variables
create_dirs
create_data_dir_in_all_nodes
build_mysql_binaries
set_up_init_file
create_dbt2_test_files
handle_remote_build
create_data_dir_in_all_nodes
create_innodb_log_dir

#Perform the actual benchmark run
if test "x${BENCHMARK_TO_RUN}" = "xsysbench" ; then
  run_sysbench
elif test "x${BENCHMARK_TO_RUN}" = "xdbt2" ; then
  run_dbt2
elif test "x${BENCHMARK_TO_RUN}" = "xdbt3" ; then
  run_dbt3
elif test "x${BENCHMARK_TO_RUN}" = "xflexAsynch" ; then
  run_flexAsynch
fi
handle_cleanup
exit 0
