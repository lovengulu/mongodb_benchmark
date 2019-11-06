#!/usr/bin/bash

# Before running the installer, set the correct values in 'install_config_env.sh'
# The installer creates two directories. One for the benchmark logs and /data for mounting the storage.

source ./install_config_env.sh
clients_hostname=${clients_hostname:-localhost}

mkdir -p ${BM_LOGS}

cd ${PKG_HOME}

# First confirm that have enough storage for the database
if [ -n "$AMAZON" ]; then
    source ./amazon_create_raid.sh
    if [ $? -eq 1 ]
    then
        echo "Error while creating raid for db storage "
        exit
    fi
fi

mkdir -p /data
mount  $DB_STORAGE_DEV /data
mkdir -p /data/mongodb

# now test that we have enough disk space
storage_disk_space=$(df /data | grep -v Filesystem  | awk '{print $4}')
required_storage_size_estimation=$( bc <<< " 1.3 * $POPULATION "  | awk -F. '{print $1}')
if [ "$storage_disk_space" -lt "$required_storage_size_estimation" ]; then
    echo "Error: Not enough disk space:"
    echo "   $required_storage_size_estimation KB is required (estimation). "
    echo "   $storage_disk_space KB is available"
    exit 1
fi

# Install MongoDB
curl -O https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-rhel70-${MONGODB_VER}.tgz &
sudo yum install numactl screen nc -y
#sudo yum install cpan gcc -y
sudo yum install dstat -y
sudo iptables -F
wait
tar xf mongodb-linux-x86_64-rhel70-${MONGODB_VER}.tgz

for file in load_batch.sh run_server.sh; do
    sed -i.ORIG -e "s/%CLIENTS_HOSTNAME%/${clients_hostname}/"    \
                -e "s=%BM_LOGS%=$BM_LOGS="                  \
                -e "s=%MONGODB_BIN_PATH%=$MONGODB_BIN_PATH=" \
                -e "s=%DB_STORAGE_DEV%=$DB_STORAGE_DEV=" \
                -e "s=%POPULATION%=$POPULATION=" \
                -e "s=%LOAD_DB_PROCESSES%=$LOAD_DB_PROCESSES=" \
                -e "s=%gulu_INSTALLER%=$gulu_INSTALLER=" \
                -e "s=%PKG_HOME%=$PKG_HOME=" $file
done

# Now, install client packages. This allows loading the database using the same node.
./install_client.sh


# TODO: verify if the following is needed - most likely not.
#[ -z "${SUDO}" ] && sed -i "s/sudo//" run_server.sh


