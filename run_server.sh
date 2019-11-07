#!/usr/bin/bash

test_id=${1}
test_duration=12600
clients_hostname="%CLIENTS_HOSTNAME%"

function usage {
cat - <<EOF
usage: $0 test_id [ list of parameters ]
  where:

  test_id     string to use in the logs file name to help identify the test

  Optional parameters:
    --reboot    - will reboot the server once the test is done.
    --short     - skip collecting system_info
    --mount     - storage device to mount for database usage Default: %DB_STORAGE_DEV%
    --sleep  N  - set test duration to N seconds. Default: ${test_duration}
    --cache  N  - set wiredTiger CacheSize to N [GB]  (--wiredTigerCacheSizeGB)
    --index     - add the parameter "--wiredTigerDirectoryForIndexes" to mongodb start command
    --usage     - print this usage text

  Example:
  ./run_server.sh testname --short --sleep 9000 --cache 525

EOF

}

# TODO: how to set CacheSize? a generic approach is to use 70% of the RAM. Need to allow "default" option as well.

if [[ "${test_id}" == "--usa"* ]]; then
    usage
    exit
elif [[ "${test_id}" == "-"* ]]; then
    echo "Error: testid can not start with hyphen"
    echo "  use the --usage option for for help"
    exit
elif [ -z "${test_id}" ];then
    test_id=noname
fi

POSITIONAL=(${test_id})
shift
while [[ $# -gt 0 ]];do
key="$1"

case $key in
    --reboot)
        REBOOT="y"
        shift # past argument
        ;;
    --short)
        SHORT_RUN="y"
        shift # past argument
        ;;
    --sleep)
        SLEEP="$2"
        shift # past argument
        shift # past value
        PARAM_STRING_LOGGER="$PARAM_STRING_LOGGER\ntest duration settings:=$SLEEP"
        ;;
    --mount)
        MOUNT="$2"
        shift # past argument
        shift # past value
        PARAM_STRING_LOGGER="$PARAM_STRING_LOGGER\nmount device:=$MOUNT"
        ;;
    --cache*|--wiredTigerCacheSizeGB)
        CACHE_PARAM="--wiredTigerCacheSizeGB $2"
        shift # past argument
        shift # past value
        PARAM_STRING_LOGGER="$PARAM_STRING_LOGGER\nwiredTigerCacheSizeGB:=$CACHE_PARAM"
        ;;
    --index|--wiredTigerDirectoryForIndexes)
        INDEX_PARAM="--wiredTigerDirectoryForIndexes"
        shift # past argument
        PARAM_STRING_LOGGER="$PARAM_STRING_LOGGER\nwiredTigerDirectoryForIndexes:=YES"
        ;;
    *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        usage
        exit
        ;;
    --usage|--help)    #
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        usage
        exit
        ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#####   Adjust test_id  ############################
guluversion_res=$(/usr/local/bin/guluversion 2> /dev/null)

if [ -z "$guluversion_res" ]; then
    test_env="Native"
else
    test_env="gulu"
fi

if [ "$test_env" = "gulu" ]; then
    guluversion=$(echo "$guluversion_res" | grep -i gulu | sed "s/.*: //" |  sed "s/[[:space:]]*(.*//")
    # remove the last two characters if ".0"
    [ ${guluversion: -3} = ".0" ] && guluversion=${guluversion: 0: -3}
	test_env=$guluversion
fi

if [ -n "$CACHE_PARAM" ]; then
    test_id_cache=$(echo "$CACHE_PARAM" | awk '{print "_cache." $2}')
fi

if [ -n "$INDEX_PARAM" ]; then
    test_id_index="_IndexDir"
fi

test_id=${test_id}${test_id_index}${test_id_cache}_${test_env}.`date +%s`

if [ -f  %PKG_HOME%/send_notification.sh ]; then
    %PKG_HOME%/send_notification.sh "Test start: $test_id"
fi

#####End of Adjust test_id section #############################


### start MongoDB server 
free -g && sync && time echo 1 > /proc/sys/vm/drop_caches && free -g

#TODO: fix bug. the value from the command line is not used.
sudo mount %DB_STORAGE_DEV% /data
numactl --interleave=all %MONGODB_BIN_PATH%/mongod --dbpath /data/mongodb --bind_ip_all --logpath /data/mongod.log $CACHE_PARAM $INDEX_PARAM &

### monitoring 
cd %BM_LOGS%
%PKG_HOME%/machine_info.sh > %BM_LOGS%/host_info.${test_id}.txt
echo -e "${PARAM_STRING_LOGGER}" >> %BM_LOGS%/host_info.${test_id}.txt

if [ -z "$SHORT_RUN" ];then
    %gulu_INSTALLER% si -sq
fi

dstat -tlvn --output ${test_id}.dstat.csv 30  &
%MONGODB_BIN_PATH%/mongostat 30 >  ${test_id}.mongostat  &
sleep 10

### trigger client to start load and wait for the test duration
sudo iptables -F
# TODO: I added here few attempts to start the client due to connection issues. Most likely the issues where with the specific hardware I used. Otherwise, need to replace with some more robust code to to it.
echo "sending start trigger to client ..."
for i in $(seq 1 5); do
    for client in $clients_hostname; do
        echo "$test_id" | nc  $client  6505
    done
    sleep 5
done


sleep "${SLEEP:-$test_duration}"

### stop monitoring and mongodb server 
kill %2
kill %3

if [ -f  %PKG_HOME%/send_notification.sh ]; then
    %PKG_HOME%/send_notification.sh "Test end: $test_id"
fi


%MONGODB_BIN_PATH%/mongod --dbpath /data/mongodb  --shutdown  &
# while waiting for mongodb to stop properly, let's take another system info.
if [ -z "$SHORT_RUN" ];then
    %gulu_INSTALLER% si -sq
fi
wait

# report the throughput:
./calc_avg_throughput.pl %BM_LOGS%/${test_id}.mongostat

if [ -n "$REBOOT" ];then
    wall "rebooting in 60 seconds"
    sleep 60
    /usr/sbin/reboot
fi

