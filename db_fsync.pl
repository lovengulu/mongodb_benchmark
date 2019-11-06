#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Time::HiRes qw(time);
use MongoDB;

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

db_fsync();

