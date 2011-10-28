#!/usr/bin/perl
use File::Basename;
use File::Copy;
use Archive::Zip;
use XML::XPath;

use utf8;
use strict;

binmode STDOUT, ":utf8";
	
my $dir = $ARGV[0];
opendir my $dh, $dir;
my @files = grep {/^[^\.].+\.epub$/} readdir $dh;
closedir($dh);
	
foreach my $file (@files) {
	my ($id) = ($file =~ /^(.+)_eEPUB.*$/);
	
	my $temp = $dir."/temp_$id/";
	mkdir $temp;
	
	my $zip = Archive::Zip->new("$dir/$file");
	$zip->extractTree('', $temp);
	
	open(my $in, "<"."$temp/".$id."_opf.opf");
	open(my $out, ">"."$temp/new_".$id."_opf.opf");
	foreach my $line (<$in>) {
		if ($line ne "    <meta property=\"layout:orientation\">landscape</meta>\n") {
			print $out $line;
		}
	}
	close($out);
	close($in);
	move "$temp/new_".$id."_opf.opf", "$temp/".$id."_opf.opf";
	
	mkdir "$dir/new/";
	my $outfile = "$dir/new/$file";
	
	$zip = Archive::Zip->new();
	$zip->addFile("$temp/mimetype", 'mimetype');
	my ($mimetype) = $zip->members();
	$mimetype->desiredCompressionLevel(0);
	$zip->addTree($temp, '', sub { !($_ =~ /.*\/mimetype$/) and !($_ =~ /.*\/size$/) });
	$zip->writeToFileNamed($outfile);
}

opendir my $dh, $dir;
my @files = grep {/^[^\.].+\.opf$/} readdir $dh;
closedir($dh);
foreach my $file (@files) {
	open(my $in, "<"."$dir/$file");
	open(my $out, ">"."$dir/new/$file");
	foreach my $line (<$in>) {
		if ($line ne "    <meta property=\"layout:orientation\">landscape</meta>\n") {
			print $out $line;
		}
	}
	close($out);
	close($in);
}
