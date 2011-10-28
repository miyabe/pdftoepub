#!/usr/bin/perl
use Archive::Zip;

use utf8;
use strict;

binmode STDOUT, ":utf8";
	
my $dir = $ARGV[0];

my $zip = Archive::Zip->new();
$zip->addFile("$dir/mimetype", 'mimetype');
my ($mimetype) = $zip->members();
$mimetype->desiredCompressionLevel(0);
$zip->addTree($dir, '', sub { !($_ =~ /.*\/mimetype$/) });
$zip->writeToFileNamed("${dir}_eEPUB3.epub");
