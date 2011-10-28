#!/usr/bin/perl
use File::Basename;
use Archive::Zip;
use XML::XPath;

use utf8;
use strict;

binmode STDOUT, ":utf8";
	
my $src = $ARGV[0];
my ($id) = (basename($src) =~ /^(.+)_eEPUB.*$/);

my $zip = Archive::Zip->new($src);
my ($opf) = $zip->memberNamed($id."_opf.opf");
$opf->extractToFileNamed("/tmp/".$id."_opf.opf");

my $xp = XML::XPath->new(filename => "/tmp/".$id."_opf.opf");
my $ppd = $xp->findvalue('/package/spine/@page-progression-direction')->value;
my $nodes = $xp->find('/package/spine/*');
my ($in, $out);
open($in, "<"."/tmp/".$id."_opf.opf");
open($out, ">"."/tmp/new_".$id."_opf.opf");
foreach my $line (<$in>) {
	my $i;
	if (($i) = ($line =~ /^\s+<itemref idref=\"t(\d+)\" properties=\".+\"\/>$/)) {
    my $props = ($i % 2 == (($ppd eq 'rtl') ? 0 : 1)) ? "page-spread-left" : "page-spread-right";
    print $out "    <itemref idref=\"t$i\" properties=\"$props\"/>\n";
	}
	else {
	print $out $line;
	}
}
close($out);
close($in);

$zip->updateMember($opf, "/tmp/new_".$id."_opf.opf");
mkdir dirname($src)."/new/";
$zip->writeToFileNamed(dirname($src)."/new/".basename($src));

# check
#system "java -cp lib/jing.jar:lib/saxon9he.jar:lib/flute.jar:lib/sac.jar -jar epubcheck-3.0b2.jar $outfile";
