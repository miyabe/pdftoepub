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
	my $orientation = 0;
	foreach my $line (<$in>) {
		if ($line =~ /\s*<meta property=\"layout:orientation\">.*<\/meta>/) {
			$orientation = 1;
		}
		elsif ($line =~ /\s*<meta property=\"layout:fixed-layout\">true<\/meta>/) {
			if (!$orientation) {
				print $out "    <meta property=\"layout:orientation\">auto<\/meta>\n";
			}
		}
		print $out $line;
	}
	close($out);
	close($in);
	mkdir "$dir/new/";
	
	copy "$temp/new_".$id."_opf.opf", "$dir/new/".$id."_opf.opf";
	move "$temp/new_".$id."_opf.opf", "$temp/".$id."_opf.opf";
	
	my $outfile = "$dir/new/$file";
	
	$zip = Archive::Zip->new();
	$zip->addFile("$temp/mimetype", 'mimetype');
	my ($mimetype) = $zip->members();
	$mimetype->desiredCompressionLevel(0);
	$zip->addTree($temp, '', sub { !($_ =~ /.*\/mimetype$/) and !($_ =~ /.*\/size$/) });
	$zip->writeToFileNamed($outfile);
}

