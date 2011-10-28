#!/usr/bin/perl
use File::Basename;
use File::Copy;
use Archive::Zip;
use XML::XPath;

use utf8;
use strict;

binmode STDOUT, ":utf8";
	
my $src = $ARGV[0];
my ($id) = (basename($src) =~ /^(.+)_eEPUB.*$/);

my $temp = dirname($src)."/temp_$id/";
mkdir $temp;

my $zip = Archive::Zip->new($src);
$zip->extractTree('', $temp);
my $xp = XML::XPath->new(filename => "$temp/$id"."_opf.opf");
my ($w, $h) = ($xp->findvalue('/package/metadata/meta[@property=\'layout:viewport\']/text()')->value =~ /width=(\d+), height=(\d+)/);
my $nodes = $xp->find('/package/spine/*');

foreach my $node ($nodes->get_nodelist) {
	$xp = XML::XPath->new(context => $node);
	my ($i) = ($xp->findvalue('@idref')->value =~ /^t(\d+)$/);
	my $prop = $xp->findvalue('@properties')->value;
	my $svg = sprintf("%05d.svg", $i);
	my $outsvg = sprintf("%s/%05d.svg", $temp, $i);
	
	$xp = XML::XPath->new(filename => "$outsvg");
	my ($ww, $hh) = ($xp->findvalue('/svg/@viewBox')->value =~ /0 0 (\d+) (\d+)/);
	($ww == $w && $hh == $h) and next;
	
	my ($in, $out);
	open($in, "<$outsvg");
	open($out, ">$outsvg.temp");
	foreach my $line (<$in>) {
		if ($line =~ /viewBox=\"0 0 \d+ \d+\"/) {
			$line =~ s/viewBox=\"0 0 \d+ \d+\"/viewBox=\"0 0 $w $h\"/;
		}
		elsif ($line =~ /<image width=\"$ww\" height=\"$hh\" xlink:href=\".+\" \/>/) {
			if ($hh > $h) {
				$ww *= $h / $hh;
				$ww = int($ww);
				$hh = $h;
			}
			if ($ww > $w) {
				$hh *= $w / $ww;
				$hh = int($hh);
				$ww = $w;
			}
			
			my $x;
			if ($prop eq 'page-spread-left') {
				$x = $w - $ww + 1;
			}
			else {
				$x = -1;
			}
			$line = sprintf("<image x=\"$x\" width=\"$ww\" height=\"$hh\" xlink:href=\"%05d.jpg\" />\n", $i);
		}
		print $out $line;
	}
	close($out);
	close($in);
	
	move("$outsvg.temp", $outsvg);
}

mkdir dirname($src)."/new/";
my $outfile = dirname($src)."/new/".basename($src);

$zip = Archive::Zip->new();
$zip->addFile("$temp/mimetype", 'mimetype');
my ($mimetype) = $zip->members();
$mimetype->desiredCompressionLevel(0);
$zip->addTree($temp, '', sub { !($_ =~ /.*\/mimetype$/) and !($_ =~ /.*\/size$/) });
$zip->writeToFileNamed($outfile);

# check
system "java -cp lib/jing.jar:lib/saxon9he.jar:lib/flute.jar:lib/sac.jar -jar epubcheck-3.0b2.jar $outfile";
