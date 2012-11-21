#! /usr/bin/perl

# Michael Eaton
# Jan 4, 2001
# backup.pl
# Purpose: to read an XML file with files to be backed up.
# Perl conversion of backup.vbs.

use strict;

use XML::Parser;
use Win32;
use File::Spec::Win32;
# used to retrieve the CD drive and to make sure
# it is ready for use.
use Win32::DriveInfo;
# used to do a recursive file copy
use File::NCopy qw (copy);
use File::Find;
use File::Path;
use File::Spec;
# used to eject the CD
use Win32::MCI::Basic;
# used to send the email
use Net::SMTP;
# used to set the error mode so
# Windows doesn't popup any dialogs
use Win32API::File 0.02 qw( :ALL );

# holds config info from $Infile
my %config = ();

# array to hold all the file information
my @files;
# array to hold email recipient info
my @recipients;

# used when iterating the array 
my $file;
my $compress;
my $output;
my $recurse;
my $outfile;
my $dir_name;

my $date;

my $success = "true";
my $context;

# this is the configuration file
my $Infile = "backup.xml";

# make sure the config file exists.
if (! -e $Infile) {
	$success = "false";
	$context = "Cannot find $Infile";
	goto done;
}

my $fileSet;
# if a fileset is passed in, use it, otherwise bail.
if ($#ARGV == 0) {
	# this is the number of files to
	# process.
	$fileSet = $ARGV[0];	
}
elsif ($#ARGV == -1) {
	$success = "false";
	$context = "I don't know which fileset to use";
	print $context;
	exit;
}

# create the parser and set the Event handlers
my $parser = new XML::Parser(Handlers=>{Start=>\&handle_start,
										Char=>\&handle_char});

# parse the XML.  See the event handlers for details on how to read the XML.
$parser->parsefile($Infile);

# after the file is parsed, we should have the configuration info and the
# list of files to process.  Instead of using the config hash, I'm putting
# the info into individual vars...good or bad?  I don't care.
my $log = $config{'log_dir'};
# canonpath fixes up all the backslash/forward slash issues
my $dest = File::Spec::Win32->canonpath($config{'destination'});

loggit($log, "----- starting $0 -----");

# this is the local path for the backup files.
if (! -d $dest) {	
	mkdir $dest;
}

# get today's date formatted as yyyyddmm
$date = getDate();

# don't do anything if purge_after_days is 0
if ($config{'purge_after_days'} > 0) {
	# cleanup old directories
	find(\&wanted, $dest);
	sub wanted {
		# the directory we're processing must be all digits
		if (/(\d+)/) {
			#print $1, "\n";
			# must be a directory
			return unless -d $_;
			# must be old enough
			return unless -M > $config{'purge_after_days'};	
			loggit($log, $File::Find::dir . "/" . $1 . " will be removed");
			rmtree($File::Find::dir . "/" . $1, 1, 0);		
		}
	}
}

# if no files were returned, bail.
if ($#files == -1) {
	$success = "false";
	$context = "The fileset '$fileSet', does not exist.";
	goto done;
}

# loop through the files
# see handle_start for details of how this array is populated.
for (0..$#files) {
	 
	my $localDir = "";
	 
	# parse the file array 
	($file, $compress, $output, $recurse, $dir_name) = split(/~/, $files[$_]);
	 	 
	 if ($config{'use_dates'} eq "1") {
		$localDir = $dest . "\\" . $dir_name . "\\" . $date . "\\";
		$outfile = $localDir . $output;		
		# create the folder(s) if needed.
		if (! -d $localDir) {
			mkdir $dest . "\\" . $dir_name;
			mkdir $localDir;
		}		
	 } else {
		$localDir = $dest . "\\" .$dir_name . "\\";		 
		$outfile = $localDir . $output;		 
	 }
	 

	# mje 6/7/2005 - replacing InfoZip with WinZip Command Line clien
	# this is the command-line that requires the existence of
	# the InfoZip 'zip.exe' file in the path.
	my $command;
	$command = "$config{'zip_path'} a $outfile $file ";

	loggit($log, "Zipping...");
	loggit($log, $command);
	my $cmd = `$command`;
	if($cmd eq "") {
		$context = "winzip failure.";
		$success = "false";
		goto done;
	}
	loggit($log, $cmd);
}

done:
if ($success eq "true") {
	sendMail($config{'mail_server'}, $config{'mail_from'}, $config{'mail_subject'} . " - Success", "The backup of fileset '$fileSet' was successful.\n");
} else {
	sendMail($config{'mail_server'}, $config{'mail_from'}, $config{'mail_subject'} . " - Failure", "The backup of fileset '$fileSet' was unsuccessful.  The last error was: '$!'.  Extra info: $context\n");
}
loggit($log, "----- done -----");
exit;

################################################
# Other procedures
################################################

sub ejectCD {
	my ($cd_drive, $eject_when_done) = @_;

	if (Win32::DriveInfo::IsReady($cd_drive)) {
		if ($eject_when_done == "1") {
			if (Win32::DriveInfo::DriveType($cd_drive) == 5) {
				loggit($log, "Ejecting the CD");
				my $command = "set cdaudio door open wait";
				my ($APICallReturnValue, $return) = mciSendString($command);
			}
		}
	}
}

sub sendMail {
	my ($mail_server, $mail_from, $mail_subject, $msg) = @_;
	
	loggit($log, $msg);
	
	my $smtp;	
	$smtp = Net::SMTP->new($mail_server);
    $smtp->mail($mail_from);
	foreach my $rec (@recipients) {
		loggit($log, "Sending email to: $rec");
		$smtp->to($rec);
	}
    $smtp->data();    
	$smtp->datasend("Subject: $mail_subject\n");
    $smtp->datasend("\n");
    $smtp->datasend($msg);
    $smtp->dataend();
    $smtp->quit;
}

################################################
# XML procedures
################################################
sub handle_char {
	my ($p, $data) = @_;

	my $t = $data;
	
	# remove leading / trailing spaces
	for ($t) {
		s/^\s+//;
		s/\s+$//;
	}

	return if ($t eq ""); 

	if ($p->current_element eq 'destination') {
		$config{'destination'} = $t;
	} elsif ($p->current_element eq 'reset_archive_bit') {
		$config{'reset_archive_bit'} = $t;
	} elsif ($p->current_element eq 'log_dir') {
		$config{'log_dir'} = $t;
	} elsif ($p->current_element eq 'use_dates') {
		$config{'use_dates'} = $t;
	} elsif ($p->current_element eq 'cd_drive') {
		$config{'cd_drive'} = $t;
	} elsif ($p->current_element eq 'eject_when_done') {
		$config{'eject_when_done'} = $t;
	} elsif ($p->current_element eq 'mail_server') {
		$config{'mail_server'} = $t;
	} elsif ($p->current_element eq 'mail_subject') {
		$config{'mail_subject'} = $t;
	} elsif ($p->current_element eq 'mail_from') {
		$config{'mail_from'} = $t;
	} elsif ($p->current_element eq 'purge_after_days') {
		$config{'purge_after_days'} = $t;
	} elsif ($p->current_element eq 'zip_path') {
		$config{'zip_path'} = $t;
	}
}

sub handle_start {
	my $p = shift;
	my $line = shift;
	my %attr = @_;

	return if ($line eq "");

	# grab email addresses
	if ($line eq "recipient") {
		push @recipients, $attr{'email'};
	}

	# as we find files, add them to an array for later processing.
	if ($line eq 'file') {
		if (lc($attr{'fileset'}) eq lc($fileSet)) {
			# convert the 0..4 in the XML to a valid wzzip.exe parameter.
			# if I were cool, I'd figure out how to tar the files so this
			# wouldn't rely on winzip.
			# mje 6/7/2005 - changed default compression to "normal" (was none)			
			if($attr{'compress'} eq "4") { $attr{'compress'} = "-ex"; }
			if($attr{'compress'} eq "3") { $attr{'compress'} = "-ef"; }
			if($attr{'compress'} eq "2") { $attr{'compress'} = "-ef"; }
			if($attr{'compress'} eq "1") { $attr{'compress'} = "-e0"; }

			#$attr{'compress'} = ("-e1", "-en")[$attr{'compress'}];
			# if recurse is false, set to blank, otherwise set to valid
			# winzip parameter.
			if($attr{'recurse'} ne "0") {
				$attr{'recurse'} = "-rp";
			} else {
				$attr{'recurse'} = "";
			}
			#$attr{'recurse'} = ("-rp", "")[$attr{'recurse'}];
			
			# sub-dir name (under $config{'destination'}
			$attr{'dir_name'} = $attr{'dir_name'};
			# ~ delimit the array entry for easy parsing later on.
			push @files, $attr{'name'} . "~" . $attr{'compress'} . "~" . $attr{'archive_name'} . "~" . $attr{'recurse'} . "~" . $attr{'dir_name'};
		}
	}
}

################################################
# non-XML procedures
################################################
sub loggit {
	my ($logdir, $msg) = @_;
	my $OUT;
	my $date = getDate();
	my $outfile = $logdir . "backup." . $date . ".log";

	my ($sec, $min, $hour) = (localtime)[(0,1,2)];

	# open log file for append
	if (!open($OUT, ">>$outfile")) {
		print "cannot open $logdir because '$!'.", "\n";
	}

	# print to stdout and the log file
	print $msg, "\n";
	print $OUT "$hour:$min:$sec\t$msg", "\n";

	close $OUT;
}

# returns a specially formatted date (yyyymmdd)
sub getDate {
	my ($day, $mon, $year) = (localtime)[(3,4,5)];
	$year += 1900;
	$mon = sprintf("%02d", $mon += 1);
	$day = sprintf("%02d", $day);
	my $date = $year . $mon . $day;
	return $date;
}

# adds commas to a number.
sub commify {
   my $input = shift;
	$input = reverse $input;
	$input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
	return scalar reverse $input;
}

__END__

=head1 Name

Backup.pl - A complete backup program written in Perl

=head1 Purpose

Backup is a full featured backup program that will compress files into a Zip archive and optionally copy the
zip file to a secondary location such as a CD-RW drive.

=head1 Usage

backup.pl E<lt>fileset nameE<gt>

=head1 Configuration

To configure this program, you must edit Backup.xml in a text / xml editor.  There are several sections in the
file.  Each section will need to be customized for you to get the most out of this application.  The parent node
of this xml file is named E<lt>backup_infoE<gt>.  It contains three sections:

=over 4

=item *
configuration

=item *
files

=item *
email_recipients

=back

=head2 General

All of the general settings for the application are taken care of in the configuration section of the xml file.

=over 4

=item *
destination -- This is the location where the zip file is created before it is copied to the optional cd_drive location.

=item *
reset_archive_bit -- This is currently not supported.

=item *
log_dir -- This is the directory where the log file will be written.  Log files are named as backup.yyyymmdd.log.

=item *
use_dates -- If this is set to a value of 1, the zip files will be written to destination\yyyymmdd.

=item *
cd_drive -- This is an optional setting.  After the zip file is created, it will be copied to this location. 

=item *
eject_when_done -- If this is set to a value of 1 and the cd_drive value is actually a CD drive, the CD will be
ejected after it is written.

=item *
mail_server -- This needs to be a valid SMTP server.  A Success / Failure message will be emailed when the backup
is complete.

=item *
mail_from -- This is who the email will come from.

=item *
mail_subject -- This will be the subject of the email that is sent.

=item *
purge_after_days -- If this value is greater than 0 and use_dates = 1, any directories under destination that are over
purge_after_days will be deleted.

=back

=head2 Filesets

In order to facilitate backing up multiple locations / files on a given computer, each E<lt>fileE<gt> section must
have a fileset attribute.

The name attribute is the full path and filename (wildcards are acceptable) of the files you want backed up.

The archive_name attribute is the name of the zip file.

If the recurse attribute is set to 1, all directories under the path defined using the name attribute will be backed up.

The dir_name attribute is the name of the directory under destination where the zip file will be created.

=head2 Email

At the end of the backup process, an email will be sent to the addresses defined in this section.

=head1 Author

Michael Eaton, mjeaton@sitedev.com

=head1 Copyright

Copyright (c) 2001-2003 Michael Eaton.  All rights reserved.

=cut
