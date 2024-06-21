#!/usr/bin/perl -w
#
# A short script to moderate the "mix" of swift-frontend
# processes on the CPU to stop memory & disk "thrashing".
# It can be useful to run this script alongside a full
# toolchain build on a machine that has limited memory.
# If your build stalls you can restart this script.
#
use strict;

my $maxActive = $ARGV[0] || 5;
my %stopped;

while (1) {
    open PS, "ps auxww | grep swift-frontend |";
    my $nextProcess = sub  {
        return (<PS>||"") =~ /(\w+) +(\d+) +([\d\.]+) +([\d\.]+)/
    };
    
    for my $i (1..$maxActive) {
        my ($user, $pid, $cpu, $mem) = $nextProcess->() or last;
        warn "Continuing $pid\n";
        system "kill -CONT $pid";
        delete $stopped{$pid};
    }
    
    while (my ($user, $pid, $cpu, $mem) = $nextProcess->()) {
        warn "Stopping $pid\n";
        system "kill -STOP $pid";
        $stopped{$pid} = 1;
    }
    
    warn "Stopped processes: @{[sort keys %stopped]}\n";
    sleep 15;
}
