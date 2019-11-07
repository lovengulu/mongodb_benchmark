#!/bin/bash

# This wrapper wait for a signal to start the client. The trigger comes from "run_server.sh" once the
# database server has started. if for some reason the wrapper was not running when the trigger is sent, it is fine to
# send the trigger manually using:
#       echo some_test_name | nc  localhost  6505

# set here the IP or hostname of the mongodb-server
dest_server=%SERVER_HOSTNAME%

# set the POPULATION size to query.
population=%POPULATION%

# set here the number of client processes to start
clients=%CLIENT_PROCESSES_TO_START%

# endless_loop
# yes  -  The wrapper in endless loop. This is useful when testing various settings on the server to eliminate the
#         need to restart the client side.
# no   -  The wrapper runs once and it's process is done once the client is stopped.
endless_loop=no

#TODO: mongodb_endless_get_client.pl not exiting when db is shutdown. This is because the masted process runs forever although the
# childes are dead resulting defunct processes. Below is watchdog as a temporary workaround until I fix it.

logfile=mongodb_client.`date +%s`.txt

while true; do
    date >> $logfile
    ping -c 1 $dest_server
    echo "waiting for trigger to start mongodb_endless_get_client.pl" >> $logfile
    # wait for start trigger
    #ncat -v -l -p 6505
    test_name=$(nc -l 6505)
    date
    ping -c 2  $dest_server;  [ "$?" -eq "1" ] && ping -c 16 $dest_server
    echo "Received trigger to start test: $test_name" >> $logfile
    echo "starting clients ..."
    echo "starting clients" >> $logfile
    echo "Population size is: $population" >> $logfile
    echo -n "client time: " >> $logfile ; date >> $logfile
    echo -n "server time: " >> $logfile ; ssh "$dest_server" date >> $logfile

    # TODO: once done debugging reduce the verbose level to the default 1.
    ./mongodb_endless_get_client.pl --rep_dur 60 --server $dest_server --cli $clients --max_user $population --tid $test_name --verbose 2 &

    # Temporary watchdog:
    while true; do
        sleep 60
        if $(ps -ef | grep mongodb_endless | grep -v grep | grep -q defunct); then
            echo "killing defunct clients ..." >> $logfile
            echo -n "client time: " >> $logfile ; date >> $logfile
            echo -n "server time: " >> $logfile ; ssh "$dest_server" date >> $logfile
            killall mongodb_endless_get_client.pl
            break
        fi
    done
    [ "$endless_loop" = "no" ] && break
done

