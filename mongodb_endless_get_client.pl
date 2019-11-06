#!/usr/bin/perl
use strict;
use warnings;
use boolean;
use MongoDB;
use Time::HiRes qw(time);
use IO::Select;
use IO::Socket;
use JSON;

sub init;
sub client_process;

sub usage {
    print <<"USAGE";
Usage: $0 [ --flag value  ....]

Where: Flags:
    server   - destination server hostname (default: localhost)
    rep_dur  - report duration time - how frequent (in seconds) the client should report the statistics (default: 60)
    clients  - how many clients to start (default: 1)
    tid      - testid label. Is used for naming the client statistical report file (default: testid)
    max_user - maximal user id to query (default: 1000)
    path     - path to store logfile (Default: current running directory)
    verbose  - Verbose level of logs. Between 0 and 4 (Default: 1 ).
    help     - print this help (No additional value is needed)

Note that flags must:
	1. start with "--"
	2. followed by value - unless stated otherwise

USAGE
}

my $client_params_ref = init();

my $max_user_id = $$client_params_ref{max_user};
$max_user_id  =~ s/[,_]//g;
my $dest = $$client_params_ref{server};
my $report_duration = $$client_params_ref{report_duration};
my $num_clients = $$client_params_ref{clients};
my $logfile_path = $$client_params_ref{logpath} ? $$client_params_ref{logpath} . '/' : $$client_params_ref{logpath};
my $verbose = $$client_params_ref{verbose};
my $test_id = $$client_params_ref{testid};


#TODO: clients parameter
#TODO: decide how to handle report and use 'testid'

my %resp_latency_count = ();
my $req_count_prev = 0;
my $my_hostname=`hostname`;
chomp $my_hostname;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $full_log_path_name = sprintf ("%s%s_%s_%d%02d%02d%d%d.log",
    $logfile_path, $my_hostname, $test_id, $year+1900, $mon+1, $mday, $hour, $min);

print "Starting client. Log file name: $full_log_path_name\n";

# exit;
open(LOGFILE, '>', $full_log_path_name) or die "Could not open log file '$full_log_path_name' $!";
LOGFILE->autoflush(1) if ($verbose > 1);

if ($verbose > 1) {
    print LOGFILE "Debug: destination host: $dest ; population: $max_user_id ; num_clients: $num_clients ";
    print LOGFILE "report_duration: $report_duration ; logfile_path: $logfile_path ; verbose: $verbose ; test_id: $test_id\n ";
}


sub client_process {
    # open connection to master for reporting purposes
    my $sock = IO::Socket::INET->new(Proto => 'udp', PeerPort => 5151, PeerAddr => 'localhost') or die "Creating socket: $!\n";
    $sock->autoflush(1);
#    WRITER->autoflush(1);

    # open connection to database
    my $client = MongoDB::MongoClient->new(host => $dest, port => 27017);
    my $db = $client->get_database('yftest');
    my $users = $db->get_collection('users');

    srand();
    my $random_offset=rand();
    my $batch_start_time = time();

    for (my $req_count = 0; 1; $req_count++) {
        my $user_id_to_fetch = sprintf("USER%015d", rand($max_user_id));
        my $filter = { userid => $user_id_to_fetch };
        my $projection = { projection => { userid => 1, payload0 => 1, payload1 => 1, _id => 0 } };
        my $t0 = time();
        my @all_users = $users->find($filter, $projection)->all;
        my $t1 = time();
        my $resp_time_mSec = int(1000 * ($t1 - $t0));
        if ($all_users[0]) {
            $resp_latency_count{$resp_time_mSec}++;
            print LOGFILE "Debug: $all_users[0]->{userid} , $all_users[0]->{payload0} $all_users[0]->{payload1} \n" if ($verbose > 3);
        }
        else {
            printf LOGFILE "%7.2f - WARN: user %s not found in database\n", time(), $user_id_to_fetch if ($verbose > 0);
        }

        # report current TPS every $report_duration seconds.
        # The first report will be of a shorter/longer period in order to align all clients report to the system date
        if (!(int($t1) % $report_duration) and ((int($batch_start_time) + $report_duration + $random_offset) < $t1)) {
            my $current_time = time();
            my $elapsed_time = $current_time - $batch_start_time;
            my $current_TPS = int(($req_count - $req_count_prev) / ($elapsed_time) + 0.5);
            $req_count_prev = $req_count;
            $batch_start_time = $current_time;

            my $int_timestamp = int($current_time);
            my $resp_latency_count_string = "";
            foreach my $key (keys %resp_latency_count) {
                $resp_latency_count_string .= sprintf(qq("%s":%d,), $key, $resp_latency_count{$key});
            }
            # now remove the last comma (",")
            chop $resp_latency_count_string;
            my $periodic_report = sprintf(qq({"timestamp":%d,"hostname":"%s","pid":%d,"throughput":%d,"latencies":{),
                $int_timestamp, $my_hostname, $$, $current_TPS);
            $periodic_report .= $resp_latency_count_string . "}}";
            $sock->send($periodic_report);
#           print WRITER $periodic_report . "\n";
            printf LOGFILE "%7.2f - CHILD report : %s\n", time(), $periodic_report if ($verbose > 1);
            # clean $resp_latency_count to start fresh in next periodic report
            %resp_latency_count = ();
            # TODO: I'll need the sort below for extracting the data
            # print "Response histogram - milli-sec\n";
            # foreach my $key (sort  { $a <=> $b} keys %resp_latency_count) {
            #     printf "%-4d,  %-6d\n", $key, $resp_latency_count{$key};
            # }
        }
    }
}

sub init {
    my %setup_params = ();
    my %cmd_line_params = ();

    # This structure keeps the command line flag, name of parameter, config file variable name, and a default value if nothing else is defined.
    my %cmd_line_flags = (
        ser => {name => 'server', dflt => 'localhost' },
        rep => {name => 'report_duration', dflt => 60 },
        cli => { name => 'clients', dflt => 1 },
        tid => { name => 'testid', dflt => 'testid' },
        max => { name => 'max_user', dflt => 1_000 },
        log => { name => 'logpath', dflt => "" },
        ver => { name => 'verbose', dflt => 1 },
    );

    # load command line parameters to %cmd_line_params
    while (my $arg = shift @ARGV) {
        if ($arg =~ /^--hel/) {
            #help
            usage();
            exit;
        }
        elsif (($arg =~ /^--/) && ($arg = substr($arg, 2, 3)) && $cmd_line_flags{$arg}) {
            $cmd_line_params{$cmd_line_flags{$arg}{name}} = shift @ARGV;
        }
        else {
            print "Error: unknown flag argument: $arg\n";
            exit(1);
        }
    }

    # establish %setup_params with values.
    # Take the concrete values either from command line, or default (in this priority order).
    foreach my $key (keys %cmd_line_flags) {
        # printf "DEBUG: key: %s  \n",$key;
        # printf "DEBUG: param: %s ",$cmd_line_params{$cmd_line_flags{$key}{name}};
        # printf "DEBUG: default: %s \n", $cmd_line_flags{$key}{dflt};
        $setup_params{$cmd_line_flags{$key}{name}} = $cmd_line_params{$cmd_line_flags{$key}{name}} ||
                                                 $cmd_line_flags{$key}{dflt};
    }

    #TODO: can't print to LOGFILE as not initialized
    # if ($setup_params{verbose} > 1) {
    #     foreach my $key (keys %setup_params) {
    #         print "Final config: $key  =>  ";
    #         print $setup_params{$key} || " parameter is undefined ";
    #         print "\n";
    #     }
    # }
    return \%setup_params;
}

# pipe (READER, WRITER);
# WRITER->autoflush(1);
my @descenders; #Keep pids of child processes
for (my $client_id =0; $client_id < $num_clients; $client_id++ ) {
    if (my $pid = fork) {     #Parent
        push @descenders, $pid;
    }
    else {         # child
        die "cannot fork: $!" unless defined $pid;
    	#$client_sim_params_hash{client_id} =	$client_id;
    	client_process();   # TODO: confirm no need to pass parameters. or maybe better to move them inside
    	exit(0);
    }
}

my($sock, $MAXLEN, $PORTNO);
$MAXLEN = 10240;
$PORTNO = 5151;
$sock = IO::Socket::INET->new(LocalPort => $PORTNO, Proto => 'udp') or die "socket: $@";
my $sel = IO::Select->new();
$sel->add($sock);
#$sel->add(\*READER);
my $client_report;
my $read_count=0;
my %aggregated_latency_count = ();
my $client_report_hash_ref;
my %client_report_hash;
my %client_latencies_hash;


my $results = MongoDB::MongoClient->new(host => $dest, port => 27017)->get_database('yftest')->get_collection('results');

print LOGFILE "DEBUG: waiting for reports: ... \n" if ($verbose > 2);
while (true) {
    my ($ts, $host, $pid, $throughput, $latencies_str);
    my $total_periodic_tps=0;
    my $status_flag="";         # status to mark that aggregated report is valid

    # get report from child processes
    LOGFILE->autoflush(0);
    while ($sel->can_read(1)) {
#        $client_report = <READER>;
        $sock->recv($client_report, $MAXLEN);
        print LOGFILE "R" if ($verbose > 1);
        $read_count++;
        #print "$client_report\n";
        ($ts, $host, $pid, $throughput, $latencies_str) =
            ($client_report =~ /{"timestamp":(\d+),"hostname":"(\S+)","pid":(\d+),"throughput":(\d+),"latencies":{(.+)}}/);
        $client_report_hash_ref = JSON->new->utf8->decode($client_report);
        %client_report_hash = %$client_report_hash_ref;
        $total_periodic_tps += $throughput;

        my $latencies_hash_ref = $client_report_hash{"latencies"};
        %client_latencies_hash = %$latencies_hash_ref;
        foreach my $k (keys %client_latencies_hash) {
            #printf "DEBUG: L-KEY: %s, %s \n", $k, $client_latencies_hash{$k};
            $aggregated_latency_count{$k} += $client_latencies_hash{$k};
        }

        #print "DEBUG: $ts,$host,$pid,$throughput, $latencies_str \n";
        if (time() - 3 > $ts) {
            printf LOGFILE "%7.2f - WARN - Parent got late report from %s as follows: %s", time(), $ts, $client_report;
            $status_flag .= "Late_";
        }
    }

    # aggregate childes reports
    LOGFILE->autoflush(1);
    if ($read_count > 0) {
        print LOGFILE "\nRead so far: $read_count child reports. Now aggregating them.\n" if ($verbose > 1);
        if ($read_count != $num_clients) {
            printf LOGFILE "%7.2f - WARN - Parent got got %3d reports (expected: %3d reports) \n",
                time(), $read_count, $num_clients if ($verbose > 0);
            $status_flag .= "MissingChild_";

        }
        if ($verbose > 3) {
            foreach my $k (sort  { $a <=> $b} keys %aggregated_latency_count) {
                printf LOGFILE " DEBUG: sorted aggregated_latency_count:: %3s, %8s \n", $k, $aggregated_latency_count{$k};
            }
        }
        my $aggregated_latency_count_sting = encode_json (\%aggregated_latency_count);
        print LOGFILE "DEBUG aggregated latency JSON string: $aggregated_latency_count_sting \n" if ($verbose > 2);
        $status_flag = "StatusOK" if ($status_flag eq "");
        my $aggregated_periodic_report =
            sprintf(qq({"timestamp":%d,"hostname":"%s","testid":"%s","pid":%d,"throughput":%d,"clients":%d,"status":"%s","latencies":%s}),
                $ts, $host, $test_id, $$, $total_periodic_tps, $num_clients, $status_flag, $aggregated_latency_count_sting);
        print LOGFILE "INFO: $aggregated_periodic_report \n";
        #$results->insert_one(JSON->new->utf8->decode($aggregated_periodic_report));


        $read_count = 0;
        %aggregated_latency_count=();
        $status_flag="";
        printf LOGFILE "\nDEBUG: %7.2f - parent is waiting to read more \n", time() if ($verbose > 2);
    }
}
