#!/usr/bin/perl
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Getopt::Long qw(GetOptions);

my $used_percentage_threshold=40;
my $verbose;    # set to print more info on the mongostat file that was analyzed.
my $gnuplot;    # create additional file(s) to help to drew plot of the results.
my $limit=0;      # may limit the calculation to the the first X lines in the report.



GetOptions(
    'percentage|p=i' => \$used_percentage_threshold,
    'verbose|v'      => \$verbose,
    'gnuplot|g'      => \$gnuplot,
    'limit|l=i'        => \$limit, # For example, if mongostat reports every 30 seconds, set limit to 120 to get one hour
) or die "Usage: $0 --percentage N --verbose mongostat_file\n";

my $mongostat_file=shift;

my $queries_count=0;
my $samples_count=0;    # count the lines that are used to calculate the average
my $graph_sample_count=0;
my $connections_count=0;
# time where test processes start/end
my $test_start_time;
my $test_end_time;
# time boundaries to calculates average.
my $measure_time_start;
my $measure_time_end;
my $test_start_second;

open (INPUT,  $mongostat_file) or die "Could not open file '$mongostat_file' $!";

if ($gnuplot) {
    open (SHORT_FILE,  "> $mongostat_file.short") or die "Could not open file '$mongostat_file.short' $!";
    open (GP,  ">> graph_assist.gp") or die "Could not open file graph_assist.gp $!";
}

while (<INPUT>) {
    s/\*//g;
    s/%//g;
    my ($insert, $query, $update, $delete, $getmore, $command, $dirty, $used, $flushes, $vsize, $res,
        $qrw, $arw, $net_in, $net_out, $conn, $month, $day, $timestamp) = split;

    # ignore report lines that:
    next if (! looks_like_number($insert));             # seems as not a data line (header or notifications)
    if (!$test_start_time) {
        $test_start_time = "$month $day $timestamp";
        $test_start_second = `date -d \"$test_start_time\" +\"%s\"`;
    }

    $test_end_time   = "$month $day $timestamp";

    # once load start, use the data for the short file and graph although may not considered yet for average
    if ($gnuplot and ($used > 0)) {
        $graph_sample_count++;
        my $current_sec_since_epoch = `date -d \"$test_end_time\" +\"%s\"`;
        my $elapsed_time = ($current_sec_since_epoch - $test_start_second) / 3600;
        printf SHORT_FILE "%5.2f %10d %7s %7s %7s %7s %4d %3s %2s %12s\n",
            $elapsed_time, $query, $used, $vsize, $res, $net_out, $conn, $month, $day, $timestamp;
    }

    # ignore mongostat lines for calculating average based of various conditions.
    next if ($used < $used_percentage_threshold);       # seems not enough data loaded to RAM
    next if (($query==0) && ($net_out =~ /[bk]/));      # no queries and network activity - could be after test is done
    next if (($connections_count > 0) &&
        ((0.8 * $connections_count / $samples_count) > $conn )) ;  # seems that some of the clients lost connection

    $measure_time_start = "$month $day $timestamp" if (!$measure_time_start);
    $measure_time_end = "$month $day $timestamp";

    $samples_count++;
    $connections_count += $conn;
    $queries_count += $query;

    last if ($limit && ($limit > $samples_count));

}
close (INPUT);

if (!$samples_count) {
    print "WARN - Wrong input file: $mongostat_file\n";
    exit;
}

if ($verbose) {
    print "\nAdditional data:\n";
    print "percentage threshold: $used_percentage_threshold\n";
    print "Test start time:  $test_start_time\n";
    print "Measure start:    $measure_time_start\n";
    print "Measure end:      $measure_time_end\n";
    print "Test end time:    $test_end_time\n";

    my $test_end_second = `date -d \"$test_end_time\" +\"%s\"`;
    my $entire_duration = $test_end_second - $test_start_second;
    printf ("Entire duration:  %s seconds = %.1f minutes = %.1f hours\n", $entire_duration, $entire_duration/60, $entire_duration/3600);

    my $measure_start_sec = `date -d \"$measure_time_start\" +\"%s\"`;
    my $measure_end_sec   = `date -d \"$measure_time_end\" +\"%s\"`;
    my $measure_duration = $measure_end_sec - $measure_start_sec;
    printf ("Measure duration: %s seconds = %.1f minutes = %.1f hours\n", $measure_duration, $measure_duration/60, $measure_duration/3600);
    print "\n";
}

if ($gnuplot) {
    my $test_description=$mongostat_file;
    $test_description =~ s/mongostat//;
    $test_description =~ s/\./ /g;
    $test_description =~ s/_/ /g;
    printf GP '%-80s using 1:2 title "%s" with linespoints, \\', '"' . $mongostat_file . '.short"', $test_description;
    printf GP "\n";

    close SHORT_FILE;
    close GP;
}

my $average_throughput = $queries_count / $samples_count;
printf "FINAL INFO - Average throughput found in %-80s : %.1f K-TPS\n", $mongostat_file, $average_throughput / 1000;

# Example using GnuPlot:
# set title "MongoDB Benchmark - covered queries - Population size: 900 million documents"
# set xlabel "Time (Hours)"
# set ylabel "Throughput (TPS)"
# set xrange [ -0.25 : 8.5  ]
# plot \
#  "192GB.ram_pop.900M_Native.1565875797.mongostat.short"                                     using 1:2 title "192GB RAM - Native" with linespoints, \
#  "cron_ram.192GB_pop.900M_index.on.single.optan_IndexDir_Native.1566567527.mongostat.short" using 1:2 title "192GB RAM, index on single Optan, Native" with linespoints, \
#  "cron_ram.192GB_pop.900M_index.on_optan_IndexDir_Native.1566517395.mongostat.short"        using 1:2 title "192GB RAM, index on Optan raid, Native" with linespoints, \
#  "cron_ram.768GB_pop.900M_cache.525_cache.525_9.0.3365.62.1566112443.mongostat.short"       using 1:2 title "768GB RAM, cache525, IMDT 9.0.3365.62" with linespoints, \
#  "ram.768GB_pop.900M_cache.525_Native.1565639983.mongostat.short"                           using 1:2 title "768GB RAM, cache525, Native" with linespoints, \
# ;

