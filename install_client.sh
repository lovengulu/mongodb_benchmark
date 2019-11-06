#!/usr/bin/bash

source ./install_config_env.sh
server_hostname=${server_hostname:-localhost}

sudo yum install numactl screen nc -y
sudo yum install cpan gcc -y

echo -e "install local::lib\n" | ${SUDO} perl -MCPAN -e shell
echo -e "install JSON\n" | ${SUDO} perl -MCPAN -e shell
echo -e "install MongoDB\n" | ${SUDO} perl -MCPAN -e shell

# No need to path the loader. it uses 'localhost' as should run from the server machine.

#sed -i.ORIG "s/%SERVER_HOSTNAME%/$server_hostname/" mongodb_endless_get_client.pl

sed -i.ORIG -e "s/%CLIENT_PROCESSES_TO_START%/${CLIENT_PROCESSES_TO_START}/"    \
            -e "s/%SERVER_HOSTNAME%/$server_hostname/"                          \
            -e "s=%POPULATION%=${POPULATION}="    run_client.sh

# [ -z "${SUDO}" ] && sed -i "s/sudo//" run_client.sh
