#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Time::HiRes qw(time);
use MongoDB;

my $rand_string_len=100;

sub text_gen;
sub users_loader;
sub db_fsync;

sub usage {
    print <<"USAGE";
Usage: $0 [ --option value  ....]

Where: Flags:
    bsize    - batch size - number of users in each insert (default: 1000)
    start    - user id to start with. (must be a multiple of 'batch size' (default: 0)
    users    - total number of users to create. (must be a multiple of 'batch size' (default: 1000)
    clients  - how many clients to start (default: 1)
    host     - destination hostname running the database (Default: 'localhost')
    help     - print this help (No additional value is needed)

USAGE
}


GetOptions(
    'bsize|b=i' => \(my $batch_size = 1000), # set warm-up period to skip
    'host=s'    => \(my $dest = 'localhost'),
    'start=s'   => \(my $startid = '0'),
    'users=s'   => \(my $num_users = 1_000),
    'clients=i' => \(my $num_clients = 1),
    'help|h'    => \(my $help_flag=0),
) or die("Error in command line arguments\n");

usage() if $help_flag;

# remove the '_' or ',' characters that are allowed in the input for human readability
$startid =~ s/[,_]//g;
$num_users =~ s/[,_]//g;

die ("Error: the number of users (= $num_users) to load MUST divide evenly to batch size (=  $batch_size)  \n") if ($num_users % $batch_size);
die ("Error: the start-id (=$startid) MUST divide evenly by the batch-size (=$batch_size) \n") if ($startid % $batch_size);

sub users_loader{
    my $current_start_id = shift;
    my $current_num_users = shift;
    my @user_documents = ();

    # TODO: add exception handling to allow reducing the timeout
    my $client = MongoDB::MongoClient->new(host => $dest, port => 27017, socket_timeout_ms => 900_000);
    my $db = $client->get_database('yftest');
    my $users = $db->get_collection('users');


    srand();
    STDOUT->autoflush(1);

    for (my $i=int($current_start_id/$batch_size); $i < int(($current_start_id + $current_num_users)/$batch_size) ; $i++) {
        for (my $j=0; $j < $batch_size; $j++) {
            my $user_id_num = sprintf("USER%015d", $i * $batch_size + $j);
            my $document = { 'userid' => $user_id_num,
                'payload0'            => text_gen(),
                'payload1'            => text_gen(),
                'payload2'            => text_gen(),
                'payload3'            => text_gen(),
                'payload4'            => text_gen(),
                'payload5'            => text_gen(),
                'payload6'            => text_gen(),
                'payload7'            => text_gen(),
                'payload8'            => text_gen(),
                'payload9'            => text_gen(),
            };
            push @user_documents, $document;
            #$users->insert_one($document);
        }
        my $batch_start_time = time();
        my $results = $users->insert_many( [@user_documents ]);
        if ($results->inserted_count != $batch_size) {
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($batch_start_time);
            my $time_stamp = sprintf ("%d-%02d-%02dT%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
            printf "%s ERROR -  only %d out of %d documents in the batch are inserted to database\n",
                $time_stamp, $results->inserted_count, $batch_size;
        }
        my $batch_processing_duration = time() - $batch_start_time;
        if ($batch_processing_duration > 0.85) {
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($batch_start_time);
            my $time_stamp = sprintf ("%d-%02d-%02dT%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
            printf "%s WARN -  batch starting at id: %012d processed in %6.2f seconds\n",
                $time_stamp, $i * $batch_size, $batch_processing_duration;
        }
        @user_documents = ();

        if ($batch_processing_duration > 15) {
            my $random_sleep=rand(5);
            printf "Client: Random sleep: %4.2f\n",$random_sleep;
            sleep $random_sleep;
        }
        STDOUT->flush();
    }

    #db_fsync();
    $client->disconnect;

}

sub text_gen {
    my @chars = ("A".."Z", "a".."z");
    my $random_text="";
    $random_text .= $chars[rand @chars] for 1 .. $rand_string_len;
    return $random_text;
}

sub db_fsync {
    my $dest = 'localhost';
    my $client = MongoDB::MongoClient->new(host => $dest, port => 27017, socket_timeout_ms => 1_800_000);

    my $time_stamp_0 = time();
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time_stamp_0);
    my $time_stamp = sprintf("%d-%02d-%02dT%02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
    printf "%s DEBUG  -  before fsync(async) at: %s \n", $time_stamp, $time_stamp_0;
    $client->fsync({ async => 1 });
    #$client->fsync();
    my $time_stamp_1 = time();
    ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time_stamp_1);
    $time_stamp = sprintf("%d-%02d-%02dT%02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
    printf "%s DEBUG  -  after  fsync(async) at: %s. Action duration: %6.2f \n",
        $time_stamp, $time_stamp_1, $time_stamp_1 - $time_stamp_0;

    $client->disconnect;
}


###
###  The fun starts here ...
###

# create the database & index
my $set_idx_client = MongoDB::MongoClient->new(host => $dest, port => 27017);
my $db = $set_idx_client->get_database('yftest');
my $users = $db->get_collection('users');
$users->indexes->create_one( [ userid => 1, payload0 => 1, payload1 => 1  ] );
$set_idx_client->disconnect;

STDOUT->autoflush(1);

my $nub_processes = 0;

my @descenders; #Keep pids of child processes
my $users_per_client=int($num_users/$num_clients/$batch_size) * $batch_size;
for (my $client_id =0; $client_id < $num_clients; $client_id++ ) {
    #sleep 2;
    if (my $pid = fork) {     #Parent
        push @descenders, $pid;
        $nub_processes++;
    }
    else {         # child
        die "cannot fork: $!" unless defined $pid;
        users_loader($startid + $users_per_client * $client_id, $users_per_client);
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        my $time_stamp = sprintf ("%d-%02d-%02dT%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
        printf "%s Child-exit - time: %s  client-id: %02d\n", $time_stamp, time, $client_id;
        exit(0);
    }
}

wait;
$nub_processes--;
# now that one client is done so there's less load and start loading the last batches that don't divide evenly to clients
my $remaining_start_id = int($num_users/$num_clients/$batch_size)*$num_clients*$batch_size;
users_loader($startid + $users_per_client * $num_clients, $num_users - $remaining_start_id);
while ($nub_processes){
    wait;
    $nub_processes--;
    # TODO: consider to run here  db_fsync() once most clients has completed
}

