#!/bin/bash

# ./load_batch.sh - loads the database with the specified number of documents.
#
# The script accepts two optional parameters or uses the the defaults as set at install time.
# Usage example: to load the database with 300M documents using 40 clients run:
#          ./load_batch.sh  CLIENTS=40 POPULATION=300000000

cd %PKG_HOME%
CLIENTS=%LOAD_DB_PROCESSES%
POPULATION=%POPULATION%


while :; do
    case $1 in
        POPULATION=?*)
            POPULATION=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        CLIENTS=?*)
            CLIENTS=${1#*=}
            ;;
        ?*)
            printf 'ERROR: Unknown option (ignored): %s\n' "$1" >&2
            exit 1
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac
    shift
done

#mypath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
#cd $mypath

test_start_date=$(date +%s)
LOG=%BM_LOGS%/load_db.${test_start_date}.log
date >> $LOG
echo "$0 will now load the database with $POPULATION documents using $CLIENTS clients"
echo "To follow the progress use:  tail -F $LOG"
echo "$0 will now load the database with $POPULATION documents using $CLIENTS clients" >> $LOG
echo "starting mongod" >> $LOG
# rm -rf /data/mongodb/*
%MONGODB_BIN_PATH%/mongod --dbpath /data/mongodb --bind_ip_all --logpath /data/mongod_load_db.${test_start_date}.log --nojournal &
# allow few seconds for mongod to start
sleep 20
echo "database content before loading:" >> $LOG
%MONGODB_BIN_PATH%/mongo --eval '{db = db.getSiblingDB("yftest");db.stats();}' >> $LOG
%MONGODB_BIN_PATH%/mongo --eval '{db = db.getSiblingDB("yftest");db.users.stats().indexSizes;}' >> $LOG

echo "starting now to load the database ..." >> $LOG
# load database in chunks of 100,000,000 users (documents)
last_chunk=$(($POPULATION / 100000000 -1 ))
for base in $(seq 0 ${last_chunk});do
    date >> $LOG
    echo -n "Chunk $base starts ..." >> $LOG
    start_time=`date +%s`
    ./mongodb_load_batch_client.pl  --start ${base}00_000_000 --users 100_000_000 --clients $CLIENTS >> $LOG.load_db.clients
    end_time=`date +%s`
    runtime=$((end_time-start_time))
    echo "Batch $base is done in  $runtime seconds" >> $LOG
    echo "database statistics: ">> $LOG
    %MONGODB_BIN_PATH%/mongo --eval '{db = db.getSiblingDB("yftest");db.stats();}' | grep objects >> $LOG
    %MONGODB_BIN_PATH%/mongo --eval '{db = db.getSiblingDB("yftest");db.users.stats().indexSizes;}' | grep  "_id_" >> $LOG
    date >> $LOG
    echo "now waiting to confirm all inserts are synced to the storage"
    start_time_fs=`date +%s`
    ./db_fsync.pl
    end_time_fs=`date +%s`
    runtime_fs=$((end_time_fs-start_time_fs))
    echo "db_fsync is done in $runtime_fs seconds" >> $LOG

done
date >> $LOG
echo "load is done" >> $LOG

start_time=`date +%s`
%MONGODB_BIN_PATH%/mongod --dbpath /data/mongodb --bind_ip_all --logpath /data/mongod_load_db.${test_start_date}.log --shutdown   >> $LOG
end_time=`date +%s`
runtime=$((end_time-start_time))
echo "stopping DB is done in $runtime seconds" >> $LOG

date >> $LOG
echo "ALL done" >> $LOG


