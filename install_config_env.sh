#!/usr/bin/bash

# set here the MongoDB version to use:
MONGODB_VER="4.2.1"

export PKG_HOME=$(pwd)
export BM_LOGS=${PKG_HOME}/logs

# If NOT running on Amazon, set the following parameter to the path of the DB storage device.
# The storage device should be pre-formatted and ready for mount.
# If running under Amazon, you can ignore this parameter.
# Example:   export  NON_AMAZON_DB_STORAGE_PATH=/dev/nvme0n1
export NON_AMAZON_DB_STORAGE_PATH=/dev/nvme0n1

# set here the names (or IPs) of the db server and the client(s).
export server_hostname=
export clients_hostname=""

# change here - the population size used in the benchmark. Use multiples of 100 millions
# IMPORTANT: It is crucial for realistic benchmark to set POPULATION according the RAM on the server.
# Recommendations:
# RAM       Population size     Required disk storage (estimation)
# 768GB     900000000           1.4TB
export POPULATION=900000000

# change here - the number of client processes to start on each client host.
# IMPORTANT: For a realistic benchmark, the total number of client processes should load the database server
#            so the CPU idle time would be 10% or less
export CLIENT_PROCESSES_TO_START=96

# change here the number of client processes to use while loading the database.
# This controls the speed that the database is loaded with the entire population.
# This parameter does not impact the benchmark result.
# Recommendations:
# Core threads       LOAD_DB_PROCESSES
# 72                 50
export LOAD_DB_PROCESSES=50

# set SUDU=sudo if not running as root and need to allow user with 'sudo' install permissions
export SUDO="sudo"

# set here the path to gulu_installer. example: gulu_installer=/root/gulu_installer-9.0.3365.62.sh
export gulu_INSTALLER=/root/gulu_installer-9.0.3365.62.sh

# no need to update the following settings:
export MONGODB_BIN_PATH=${PKG_HOME}/mongodb-linux-x86_64-rhel70-${MONGODB_VER}/bin

export AMAZON=$(uname -r | grep -i amzn)
if [ -z "$AMAZON" ]; then
    export DB_STORAGE_DEV="$NON_AMAZON_DB_STORAGE_PATH"
else
    export DB_STORAGE_DEV="/dev/md0"
fi
