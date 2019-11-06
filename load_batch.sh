#!/bin/bash


# TODO: add to files processed by server_install.sh
# This scrip loads the database with documents.
# The only parameter (optional) it takes is the number processes to start while loading the database.
# The POPULATION size parameter is set at the time of running 'install_server.sh'

CLIENTS=${1:-%LOAD_DB_PROCESSES%}
POPULATION=%POPULATION%
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
    /opt/perl-mongo-bm/mongodb-linux-x86_64-4.0.12/bin/mongo --eval '{db = db.getSiblingDB("yftest");db.stats();}' | grep objects >> $LOG
    %MONGODB_BIN_PATH%/mongo --eval '{db = db.getSiblingDB("yftest");db.users.stats().indexSizes;}' >> $LOG
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


