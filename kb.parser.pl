#!/usr/bin/perl
# 2009/Nov/03 @ Zdenek Styblik
#
# Parser of e-mails from Komercni Banka, a.s.
#
# CREATE TABLE account_balances (id_balance SERIAL,
# date_taken DATE, balance MONEY);
# CREATE TABLE account_transactions (id_transaction SERIAL,
# account_from VARCHAR, account_to VARCHAR, ammount MONEY,
# date_executed DATE, variable_symbol INTEGER,
# specific_symbol INTEGER,
# processed BIT(1) NOT NULL DEFAULT '0',
# error_code INT NOT NULL DEFAULT 0,
# id_kb_msg INT NOT NULL
# );
#
# CREATE UNIQUE INDEX account_transactions_id_kb_msg ON
# account_transactions (date_executed, id_kb_msg);
#
# directory structure:
# year
# year/month
# year/month/day/
# year/month/day/hour.minute.sec.randomname
#
use strict;
use warnings;
use DBI;
use Mail::Sendmail;
use POSIX qw(strftime);

# Settings
my $debug = 0;
my $dirPrefix = "/some/dir";
my $myBankAccountNo = "123456";
my $myBankNo = '0100';
# $mailRecipient is used for validation checks
my $mailRecipient = "foo\@domain.tld";
#
my $mailNotifyFrom = "bar\@domain.tld";
my $mailNotifySubject = "some subject";
my $mailNotifyTo = "bar\@domain.tld";
my $mailSmtpServer = "localhost";
## Settings - DB
my $dbname = 'acc';
my $host = 'localhost';
my $port = 5432;
my $username = 'acc';
my $password = '';

my $dbDSN = sprintf("DBI:Pg:dbname=%s;host=%s;port=%s;", $dbname, $host, $port);
my $dbConn = DBI->connect($dbDSN,
	$username,
	$password,
	{
		AutoCommit => 1,
		RaiseError => 1,
		PrintError => 1
	}
);

sub mailNotify {
	my $msg = shift;
	return 254 unless ($msg || $msg =~ /[A-Za-z0-9\.\-]+/);
	my %mail = (
		From    => $mailNotifyFrom,
		Subject => $mailNotifySubject,
		'X-Mailer' => "Mail::Sendmail version $Mail::Sendmail::VERSION",
	);
	$mail{'Content-Type'} = 'text/plain; charset=UTF-8';
	$mail{'Content-Transfer-Encoding'} = 'quoted-printable';
	$mail{'smtp'} = $mailSmtpServer;
	$mail{'message :'} = $msg;
	$mail{'To :'} = $mailNotifyTo;
	sendmail(%mail);
	return 0;
} # sub mailNotify

# Desc: parse through dayily account balance report
# Example:
# Pouzitelny zustatek na beznem uctu cislo XXX ze dne XX.XX.XXXX
# je XXX,XX CZK.
sub parseAccountBalance {
	my $arrayRef = shift;
	my $position = 0;
	my @lineAPart = @$arrayRef;
	my ($bankAccountNo, $state2date, $balance) = undef;
	for my $piece (@lineAPart) {
		if ($piece =~ /cislo/) {
			$bankAccountNo = $lineAPart[$position+1];
		}
		if ($piece =~ /dne/) {
			$state2date = $lineAPart[$position+1];
			my $offset = $position+2;
			while (1) {
				if ($lineAPart[$offset] =~ /[0-9]+/) {
					$balance = $balance.$lineAPart[$offset];
				}
				if ($lineAPart[$offset+1] =~ /CZK/) {
					printf("Found CZK!\n") if ($debug == 1);
					last;
				}
				unless ($lineAPart[$offset+1]) {
					printf("Out of the road!\n") if ($debug == 1);
					last;
				}
				$offset++;
			}
		}
		$position++;
	}
	unless ($bankAccountNo =~ /^\b${myBankAccountNo}\b$/) {
		&mailNotify("AcconoutNo doesn't match\n");
		printf("AcconoutNo doesn't match\n");
		exit 5;
	}
	unless ($balance =~ /^[0-9]+,[0-9]+$/) {
		&mailNotify("Balance seems like a rubbish to me.\n");
		printf("Balance seems like a rubbish to me.\n");
		exit 5;
	}
	my @arr = split(/\./, $state2date);
	$state2date = sprintf("%s.%s.%s", $arr[2], $arr[1], $arr[0]);
	$balance =~ s/,/\./;
	printf("%s\n", $bankAccountNo);
	printf("%s\n", $state2date);
	printf("%s\n", $balance);
	if ($state2date !~ /[0-9]+\.[0-9]+\.[0-9]+/) {
		&mailNotify("Bank balance date has invalid format.\n"
		."I'm going to try to insert anyway.\n");
		printf("Bank balance date has invalid format.\n");
	}
	my $sql = sprintf("INSERT INTO account_balances (date_taken, balance)
	VALUES ('%s', '%s');", $state2date, $balance);
	$dbConn->do($sql) or die("Unable to insert account balance");
	return 0;
} # sub parseAccountBalance

# Desc: parse trough payment report
# Example:
# Oznamujeme Vam provedeni platby z uctu cislo XXX na ucet cislo
# XXX castka XXX,XX CZK , datum splatnosti XX.XX.XXXX, variabilni
# symbol platby X, specificky symbol X. Typ transakce: Uhrada.
sub parsePayment {
	my $arrayRef = shift;
	my $transID = shift;
	my $position = 0;
	my @lineAPart = @$arrayRef;
	unless (@lineAPart) {
		&mailNotify("No array passed. Strange.");
		exit 2;
	}
	unless ($transID) {
		&mailNotify("Transaction ID is missing.");
		exit 2;
	}
	my ($accountFrom, $accountTo, $ammount, $executedOn);
	my ($variableSymbol, $specificSymbol, $transaction);
	for my $piece (@lineAPart) {
		if (($piece =~ /cislo/) && ($lineAPart[$position-1] =~ /uctu/)) {
			if ($lineAPart[$position+1]) {
				$accountFrom = $lineAPart[$position+1];
			}
		}
		if (($piece =~ /cislo/) && ($lineAPart[$position-1] =~ /ucet/)) {
			if ($lineAPart[$position+1]) {
				$accountTo = $lineAPart[$position+1];
			}
		}
		if ($piece =~ /castka/) {
			my $offset = $position;
			while (1) {
				if ($lineAPart[$offset] =~ /[0-9]+/) {
					$ammount = $ammount.$lineAPart[$offset];
				}
				if ($lineAPart[$offset+1] =~ /CZK/) {
					printf("Found CZK!\n") if ($debug == 1);
					last;
				}
				unless ($lineAPart[$offset+1]) {
					printf("Out of the road!\n") if ($debug == 1);
					last;
				}
				$offset++;
			}
		}
		if ($piece =~ /splatnosti/) {
			if ($lineAPart[$position+1]) {
				$executedOn = $lineAPart[$position+1];
				$executedOn =~ s/,$//;
			}
		}
		if ($piece =~ /variabilni/) {
			if ($lineAPart[$position+3]) {
				$variableSymbol = $lineAPart[$position+3];
				$variableSymbol =~ s/,$//;
			}
		}
		if ($piece =~ /specificky/) {
			if ($lineAPart[$position+2]) {
				$specificSymbol = $lineAPart[$position+2];
				$specificSymbol =~ s/\.$//;
			}
		}
		if ($piece =~ /transakce:/) {
			if ($lineAPart[$position+1]) {
				$transaction = $lineAPart[$position+1];
			}
		}
		$position++;
	}
	my @arr = split(/\./, $executedOn);
	$executedOn = sprintf("%s.%s.%s", $arr[2], $arr[1], $arr[0]);
	$executedOn =~ s/,/\./;
	my $sql10 = sprintf("SELECT COUNT(*) FROM account_transactions  
		WHERE id_kb_msg = %s AND date_executed = '%s';", $transID,
		$executedOn);
	unless ($dbConn->selectrow_array($sql10) == 0) {
		my $errorMsg = sprintf("This transaction [%i::%s] is already in DB.",
			$transID, $executedOn);
		&mailNotify();
		exit 3;
	}
	$ammount =~ s/,/\./;
	printf("%s\n", $accountFrom);
	printf("%s\n", $accountTo);
	printf("%s\n", $ammount);
	printf("%s\n", $executedOn);
	printf("%s\n", $variableSymbol);
	printf("%s\n", $specificSymbol);
	if ($accountFrom !~ /^\b${myBankAccountNo}\/${myBankNo}\b$/
		&& $accountTo !~ /^\b${myBankAccountNo}\/${myBankNo}\b$/)
	{
		&mailNotify("Account numbers aren't mine!\n");
		printf("Account numbers aren't mine!\n");
		exit 4;
	}
# TODO ~ add check if we have all values
	my $sql = sprintf("INSERT INTO account_transactions (account_from,
		account_to,	ammount, date_executed, variable_symbol, specific_symbol,
		id_kb_msg) VALUES ('%s', '%s', '%s', '%s', %s, %s, %s);",
		$accountFrom, $accountTo, $ammount, $executedOn, $variableSymbol,
		$specificSymbol, $transID);
	$dbConn->do($sql) or die("Unable to insert transaction");
	return 0;
} # sub parsePayment

sub validateAccount {
} # sub validateAccount

sub validateAmmount {
} # sub validateAmmount

sub validateDate {
} # sub validateDate

sub validateSymbol {
} # sub validateSymbol

### MAIN ###
my $numArgs = $#ARGV + 1;

if ($numArgs < 1) {
	printf("%s :: Parser of Komercni Banka's e-mails\n", $0);
	printf("Usage:\n");
	printf("%s email.txt	:: reading from file\n", $0);
	printf("%s -	:: reading from STDIN\n", $0);
	exit 1;
}

my $fhMode = "<";
if ($ARGV[0] eq "-") {
	$fhMode = "<-";
}
open(FILE, $fhMode, $ARGV[0])
	or die "Unable to open '".$ARGV[0]."' for reading";

printf("Openned '%s'\n", $ARGV[0]);

my ($returnPath, $xOriginalTo, $deliveredTo, $date) = undef;
my ($messageID, $from, $to, $subject, $textLine) = undef;

my ($sec,$min,$hour,$day,$month,$year) = localtime();
# correct the date and month for humans
$sec = sprintf("%02i", $sec);
$min = sprintf("%02i", $min);
$hour = sprintf("%02i", $hour);
$day = sprintf("%02i", $day);
$month++;
$month = sprintf("%02i", $month);
$year = 1900 + $year;

# Prepare directory structure
my @arr = ($year, $month, $day);
my $fPath = $dirPrefix;
umask 0022;
for my $item (@arr) {
	$fPath = sprintf("%s/%s", $fPath, $item);
	if ( -d $fPath) {
		next;
	}
	mkdir($fPath);
}

unless (-d $fPath) {
	printf("Dir '%s' doesn't exist.\n", $fPath);
	my $fileTmp = sprintf("%s/tmp-dump", $dirPrefix);
	open(FILE2, ">>", $fileTmp);
	while ((my $line = <FILE>)) {
		print FILE2 $line;
	}
	close(FILE2);
	close(FILE);
	exit 2;
}

my $minimum = 10;
my $range = 50;
my $fileOut = "";
while (1) {
	my $randomNum = int(rand($range)) + $minimum;
	$fileOut = sprintf("%s/%s.%s.%s.%s", $fPath, $hour, $min, $sec, $randomNum);
	last unless (-e $fileOut);
}

# Fields as they should appear in the text (mail)
my $line;
my $stopReading = 0;
# store e-mail to disk as well
umask 0022;
open(FILE2, ">", $fileOut)
	or die("Unable to open mail file.\n");
while ((defined($line = <FILE>)) && ($stopReading < 1)) {
	print FILE2 $line;
	if ($line =~ /^Return-Path:/) {
		$returnPath = $line;
		$returnPath =~ s/Return-Path: //;
	}
	if ($line =~ /^X-Original-To:/) {
		$xOriginalTo = $line;
		$xOriginalTo =~ s/X-Original-To: //;
	}
	if ($line =~ /^Delivered-To:/) {
		$deliveredTo = $line;
		$deliveredTo =~ s/Delivered-To: //;
	}
	if ($line =~ /^Date:/) {
		$date = $line;
		$date =~ s/Date: //;
	}
	if ($line =~ /^Message-ID:/) {
		$messageID = $line;
		$messageID =~ s/Message-ID: //;
	}
	if ($line =~ /^From:/) {
		$from = $line;
		$from =~ s/From: //;
	}
	if ($line =~ /^To:/) {
	  $to = $line;
		$to =~ s/To: //;
	}
	if ($line =~ /^Subject:/) {
		$subject = $line;
		$subject =~ s/Subject: //;
	}
	if ($line =~ /^Pouzitelny /) {
		$stopReading = 1;
		$textLine = $line;
		printf("Found the break!\n") if ($debug == 1);
	}
	if ($line =~ /^Oznamujeme /) {
		$stopReading = 1;
		$textLine = $line;
		printf("Found the break!\n") if ($debug == 1);
	}
}
# and store the rest of e-mail without rewriting already found values
# if this proves to be useless, it's going to be removed.
while (( $line = <FILE> )) {
	print FILE2 $line;
}
close(FILE);
close(FILE2);
# this is just in case reading ended up with EOF
unless ($stopReading == 1) {
	&mailNotify("Something went wrong. No stop string found.\nExiting.\n");
	printf("Something went wrong. No stop string found. Exiting.\n");
	exit 2;
}
my $validMail = 0;
# 8 checks
if ($returnPath =~ /^<info\@kb.cz>$/) {
	printf("OKRP\n") if ($debug == 1);
	$validMail++;
}
if ($xOriginalTo =~ /^\b${mailRecipient}\b$/) {
	printf("OKrec\n") if ($debug == 1);
	$validMail++;
}
if ($deliveredTo =~ $xOriginalTo) {
	printf("OK-DT=xOT\n") if ($debug == 1);
	$validMail++;
}
# Tue, 3 Nov 2009
my $today = strftime "%a, %e %b %Y", gmtime;
if ($date =~ /^${today}/) {
	printf("OKdate\n") if ($debug == 1);
	$validMail++;
}
if ($messageID =~ /^<[0-9\w\.]*\binfo\@kb.cz\b>$/) {
	printf("OKmsgid\n") if ($debug == 1);
	$validMail++;
}
if ($from =~ /^\binfo\@kb\.cz\b$/) {
	printf("OKfrom\n") if ($debug == 1);
	$validMail++;
}
if ($to =~ /^\b${mailRecipient}\b$/) {
	printf("OKto\n") if ($debug == 1);
	$validMail++;
}
if ($subject =~ /^\bOznameni ID: \b[0-9]+$/) {
	printf("OKsubj\n") if ($debug == 1);
	$validMail++;
}
printf("Validity: %s/8\n", $validMail) if ($debug == 1);

if ($validMail <= 5) {
	&mailNotify("Mail seems more like a scam.\nUnwilling to continue.\n");
	printf("Mail seems more like a scam. Unwilling to continue.\n");
	exit 3;
}

unless ($dbConn) {
	&mailNotify("DB connection seems to be AWOL.\n");
	printf("DB connection seems to be AWOL.\n");
	exit 254;
}

my @lineAPart = split(/ /, $textLine);
# probably ugly :-s
if ($lineAPart[0] =~ /^Pouzitelny/) {
	printf("Balance.\n") if ($debug == 1);
	&parseAccountBalance(\@lineAPart);
} elsif ($lineAPart[0] =~ /^Oznamujeme/) {
	printf("Transfer.\n") if ($debug == 1);
	my ($rubbish, $transID) = split(/:/, $subject);
	$transID =~ s/\s+//;
	&parsePayment(\@lineAPart, $transID);
} else {
	&mailNotify("Undefined case occured/unknown e-mail received.\n");
	printf("Undefined case for '%s'.\n", $fileOut);
}

$dbConn->disconnect();
# EOF
