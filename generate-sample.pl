#!/usr/bin/perl
use File::Find;
use File::Copy;
use File::Basename;
use Archive::Zip;
use XML::XPath;
use Date::Format;

use utf8;
use strict;

binmode STDOUT, ":utf8";

my $dir = $ARGV[0];
my $contentsID = basename($dir);

my $pdf = "$dir/$contentsID.pdf";
my $metafile = "$dir/m_$contentsID.xml";
my $workdir = "$dir/work";
my $outdir = "$workdir/sample";
my $outfile = "$workdir/st_$contentsID.zip";
mkdir $outdir;

mkdir $workdir;
mkdir $outdir;
copy($metafile, "$outdir/m_$contentsID.xml");

# Read meta data.
my ($sampleType, $startPage, $endPage);
{
	my $xp = XML::XPath->new(filename => $metafile);
	$sampleType = $xp->findvalue("/ContentsSample/SampleType/text()")->value;
	$startPage = $xp->findvalue("/ContentsSample/StartPage/text()")->value;
	$endPage = $xp->findvalue("/ContentsSample/EndPage/text()")->value;
}

if ($sampleType eq "s") {
	system "../poppler/utils/pdftocairo -f $startPage -l $endPage -scale-to 480 -jpeg $pdf $outdir/s_$contentsID";
}
elsif ($sampleType eq "t") {
	system "../poppler/utils/pdftocairo -f $startPage -l $endPage -scale-to-x 198 -scale-to-y 285 -jpeg $pdf $outdir/t_$contentsID";
}
system "../poppler/utils/pdftocairo -l 1 -scale-to 480 -jpeg $pdf $workdir/cover";
move "$workdir/cover_0001.jpg", "$workdir/$contentsID.jpg";

# zip
if (-e $outfile) {
	unlink $outfile;
}
my $zip = Archive::Zip->new();
$zip->addTree($outdir, '');
$zip->writeToFileNamed($outfile)