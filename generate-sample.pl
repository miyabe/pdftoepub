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

my $pdfdir = "$dir/magazine";
my $metafile1 = "$dir/$contentsID.xml";
my $metafile2 = "$dir/m_$contentsID.xml";
my $workdir = "$dir/work";
my $outdir = "$workdir/sample";
my $outfile = "$workdir/st_$contentsID.zip";
mkdir $outdir;

mkdir $workdir;
mkdir $outdir;
copy($metafile2, "$outdir/m_$contentsID.xml");

# Read meta data.
my ($sampleType, $startPage, $endPage);
sub outputSample {
	do {
		my $pdf = sprintf("$pdfdir/%05d.pdf", $startPage);
		if (-f $pdf) {
			if ($sampleType eq "s") {
				system "../poppler/utils/pdftocairo -scale-to 480 -jpeg $pdf $outdir/";
				move "$outdir/_0001.jpg", sprintf("$outdir/s_$contentsID"."_%04d.jpg", $startPage);
			}
			elsif ($sampleType eq "t") {
				system "../poppler/utils/pdftocairo -scale-to-x 198 -scale-to-y 285 -jpeg $pdf $outdir/";
				move "$outdir/_0001.jpg", sprintf("$outdir/t_$contentsID"."_%04d.jpg", $startPage);
			}
		}
		++$startPage;
	} while ($startPage <= $endPage);
}
if (-f $metafile2) {
	my $xp = XML::XPath->new(filename => $metafile2);
	$sampleType = $xp->findvalue("/ContentsSample/SampleType/text()")->value;
	$startPage = $xp->findvalue("/ContentsSample/StartPage/text()")->value;
	$endPage = $xp->findvalue("/ContentsSample/EndPage/text()")->value;
	outputSample();
}
else {
	my $xp = XML::XPath->new(filename => $metafile1);
	my $samples = $xp->find("/Content/ContentInfo/PreviewPageList/PreviewPage");
	$sampleType = "s";
	foreach my $node ($samples->get_nodelist) {
		$xp = XML::XPath->new(context => $node);
		$startPage = $xp->findvalue("StartPage/text()")->value;
		$endPage = $xp->findvalue("EndPage/text()")->value;
		outputSample();
	}
	
	$sampleType = "t";
	my $dh;
	opendir($dh, $pdfdir);
	my @files = sort grep {/^.*\.pdf$/} readdir($dh);
	closedir($dh);
	$startPage = $files[0];
	$startPage =~ s/\.pdf//;
	$endPage = $files[-1];
	$endPage =~ s/\.pdf//;
	outputSample();
}

system "../poppler/utils/pdftocairo -l 1 -scale-to 480 -jpeg $dir/cover.pdf $workdir/cover";
move "$workdir/cover_0001.jpg", "$workdir/$contentsID.jpg";

# zip
if (-e $outfile) {
	unlink $outfile;
}
my $zip = Archive::Zip->new();
$zip->addTree($outdir, '');
$zip->writeToFileNamed($outfile)