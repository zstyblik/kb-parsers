#!/usr/bin/perl
# 2010/Jan/22 @ Zdenek Styblik <zdenek.styblik@gmail.com>
#
# Desc: parse through dump of bank account transactions [txt] from
# Komercni Banka a.s. and get rid of uncessary lines
#
# We had a need for old bank transcripts. But Komercni Banka a.s. provides
# these for extra charge in PDF.
# Luckily, you can get transaction history ~ T-1year by yourself, although
# not in user-friendly/useable format. At least so I've been told :)
#
# This was reason for a script which parses out empty lines and
# some 'garbage', converts strings from wonderfull CP1250 to UTF8.
#
# Next thing, load TXT file into Seamonkey/Firefox, change encoding
# to UTF8, add page number to the footer and print it into PDF.
#
# I agree it's not as nice as regular print-outs, but it's for free.
# btw Komercni Banka a.s. turned into the most expensive and
# probably the crappiest banks in Czech republic
#
# ToDo/Ideas:
# - it could have been parsed into TeX/XML/HTML/CVS/whatever
# - it could have been prepared for further process into :::: file
# - data could be adjusted for A4 resp. pagged
use Encode;

my $numArgs = $#ARGV + 1;

if ($numArgs == 0) {
	printf("Parser of transaction dumps [TXT] of Komercni Banka\n");
	printf("Usage:\n");
	printf("%s dump.txt	:: reading from file\n", $0);
	printf("%s -	:: reading from STDIN\n", $0);
}

my $fhMode = "<";
my $outFile = sprintf("%s.parsed", $ARGV[0]);
if ($ARGV[0] eq "-") {
	$fhMode = "<-";
	#
	my ($sec,$min,$hour,$day,$month,$year) = localtime();
	# correct the date and month for humans
	$sec = sprintf("%02i", $sec);
	$min = sprintf("%02i", $min);
	$hour = sprintf("%02i", $hour);
	$day = sprintf("%02i", $day);
	$month++;
	$month = sprintf("%02i", $month);
	$year = 1900 + $year;
	$outFile = sprintf("stdin-%s.%s.%s_%s%s%s.parsed", $year, $month, $day,
		$hour, $min, $sec);
	printf("Reading from STDIN. Parsed data will be stored in '%s'.\n",
		$outFile);
}

open(FH_IN, $fhMode, $ARGV[0])
	or die("Unable to open '".$ARGV[0]."' for reading$!");
open(FH_OUT, ">", $outFile)
	or die("Unable to open '".$outFile."' for writing.$!");

my $linePrev = undef;
my $lineConv = undef;
my ($obratVe, $obratNa, $vs, $ks, $ss) = 0;
while (my $line = <FH_IN>) {
	if ($line =~ /^[\s]+$/) {
		next;
	}
	if ($line =~ /Strana/) {
		next;
	}
	if ($line =~ /Pozn\./) {
		next;
	}
	# this is intentional skip as we want to keep '--..--' as prev line
	if ($line =~ /^Obrat na/) {
		if ($obratNa == 1) {
			next;
		}
		$obratNa = 1;
	}
	if ($line =~ /^Obrat ve/) {
		if ($obratVe == 1) {
			next;
		}
		$obratVe = 1;
	}
	if ($line =~ /^Typ transakce[\w\s]+KS/) {
		if ($ks == 1) {
			next;
		}
		$ks = 1;
	}
	if ($line =~ /VS[\W\w\s]+Datum/) {
		if ($vs == 1) {
			next;
		}
		$vs = 1;
	}
	if ($line =~ /SS[\w\s]+Datum/) {
		if ($ss == 1) {
			next;
		}
		$ss = 1;
	}
	if ($line =~ /^_/ && $line =~ $linePrev) {
		$linePrev = $line;
		next;
	}
	$linePrev = $line;
	$lineConv = decode("cp1250", $line);
	$lineConv = encode("utf8", $lineConv);
	print FH_OUT $lineConv;
}
close(FH_IN) or die("Is FH_IN already closed? $!");
close(FH_OUT) or die("Is FH_OUT already closed? $!");
# EOF
