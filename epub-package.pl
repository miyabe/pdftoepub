#!/usr/bin/perl
use File::Basename;

use lib dirname(__FILE__).'/inc';
use EpubCheck;
use EpubPackage;

use utf8;
use strict;

binmode STDOUT, ":utf8";
	
my $dir = $ARGV[0];
EpubPackage::epub_package($dir, "${dir}_eEPUB3.epub");