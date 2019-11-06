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
# true  -  The wrapper in endless loop. This is useful when testing various settings on the server to eliminate the
#          need to restart the client side.
# false -  The wrapper runs once and it's process is done once the client is stopped.
endless_loop=false

#TODO: check why mongodb_endless_get_client.pl not exiting when db is shutdown. When I tested in the past it worked (could be on SLES only)

while true; do
    date
    ping -c 1 $dest_server
    echo "waiting for trigger to start mongodb_endless_get_client.pl"
    # wait for start trigger
    #ncat -v -l -p 6505
    test_name=$(nc -l 6505)
    date
    ping -c 2  $dest_server;  [ "$?" -eq "1" ] && ping -c 16 $dest_server
    echo "starting clients ..."
    #./mongodb_endless_get_client.pl --rep_dur 30 --server dl380g10-0 --cli 270 --max_user 900_000_000 --tid $test_name --verbos 2
    # TODO: once done debugging reduce the verbose level to the default 1.
    ./mongodb_endless_get_client.pl --rep_dur 60 --server $dest_server --cli $clients --max_user $population --tid $test_name --verbose 2
    sleep 5
done




############### OLD CODE ####################
exit

#!/usr/bin/bash

sudo iptables -F
while true; do
    date 
    echo "waiting for trigger to start mongodb_endless_get_client.pl" 
    # wait for start trigger 
    ncat -v -l -p 6505 
    date 
    echo "starting clients ..."
    for i in `seq 1 %CLIENT_PROCESSES_TO_START%`; do ./mongodb_endless_get_client.pl  %POPULATION%  & done
    wait
    sleep 5
done         
