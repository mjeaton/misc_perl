#!/usr/bin/perl -w

use strict;

my $INFILE;
my $OUTFILE;
my $inFileName = "states.csv";
my $outFileName = "states.sql";

my @lines = ();

if(!open($INFILE, $inFileName)) {
	die "unable to open '$inFileName' because $!.";
}

@lines = <$INFILE>;
close $INFILE;

if(!open($OUTFILE, ">$outFileName")) {
	die "unable to open '$outFileName' because $!.";
}

my @ele = ();
foreach(@lines) {
	chomp;
	@ele = split/,/;
	print $OUTFILE "insert into [State](Name, Abbreviation) values('$ele[0]', '$ele[1]')\n";
}

close $OUTFILE;
