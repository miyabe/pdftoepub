#!/usr/bin/perl
use File::Basename;

use lib dirname(__FILE__).'/inc';
use PdfToEpub;
use Booklista;
use Utils;

require Exporter;
@ISA	= qw(Exporter);

use utf8;
use strict;
use warnings;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $src = $ARGV[0];
my $dest = $ARGV[1];
my $outputType = 0;
(@ARGV >= 3) and $outputType = $ARGV[2];

sub process {
	my $src = $_[0];
	my $ret = 1;
	
	PdfToEpub::transcode($src, $dest, 1) or ($ret = 0);
	Booklista::generate($src, $dest) or ($ret = 0);

	return $ret;
}

Utils::status("処理を開始しました");

if ($src =~ /^.+\/$/) {
	my $dir;
	opendir($dir, $src);
	my @files = grep { !/^\.$/ and !/^\.\.$/ and -d "$src$_"} readdir $dir;
	closedir($dir);
	foreach my $file (@files) {
		eval {
			process("$src$file");
		};
		if ($@) {
			print STDERR "$src: 処理を中断しました。エラー: $@";
		}
	}
}
else {
	eval {
		process($src) or exit(-1);
	};
	if ($@) {
		print STDERR "$src: 処理を中断しました。エラー: $@";
		exit(-1);
	}
}

Utils::deletestatus();
exit(0);
