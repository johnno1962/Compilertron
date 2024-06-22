#!/usr/bin/perl -w
#
# A short script to moderate the "mix" of swift-frontend
# processes on the CPU to stop memory & disk "thrashing".
# It can be useful to run this script alongside a full
# toolchain build on a machine that has limited memory.
# Should your build stall you can restart this script.
#
use strict;

my $maxActive = $ARGV[0] || 5;
my %stopped;

sub nextProcess {
    return (<PS>||"") =~ /(\w+) +(\d+) +([\d\.]+) +([\d\.]+)/
}

LOOP:
while (1) {
    warn "Stopped processes: @{[sort keys %stopped]}\n";
    open PS, "ps auxww | grep swift-frontend | grep -v grep |";
    
    for my $i (1..$maxActive) {
        my ($user, $pid, $cpu, $mem) = nextProcess();
        if (!$pid) { sleep 15; next LOOP; }
        warn "Continuing $pid\n";
        system "kill -CONT $pid";
        delete $stopped{$pid};
    }
    
    while (my ($user, $pid, $cpu, $mem) = nextProcess()) {
        warn "Stopping $pid\n";
        system "kill -STOP $pid";
        $stopped{$pid} = 1;
    }
    
    sleep 15;
}
