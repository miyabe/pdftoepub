#!/usr/bin/perl
use File::Find;
use File::Copy;
use File::Basename;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use Image::Magick;

use utf8;
use strict;

binmode STDOUT, ":utf8";

sub generate {
	my $dir = $_[0];
	my $destdir = $_[1];
	my $contentsID = basename($dir);
	$destdir = "$destdir/$contentsID";
	
	my $pdfdir = "$dir/magazine";
	my $metafile1 = "$dir/$contentsID.xml";
	my $metafile2 = "$dir/m_$contentsID.xml";
	my $workdir = "$dir/work";
	my $outdir = "$workdir/sample";
	my $outfile = "$destdir/st_$contentsID.zip";
	my $opf = $contentsID."_opf.opf";
	
	mkdir $workdir;
	mkdir $outdir;
	mkdir $destdir;
	copy($metafile2, "$outdir/m_$contentsID.xml");
	copy("$workdir/epub/$opf", "$destdir/$opf");
	
	# Read meta data.
	our ($sampleType, $startPage, $endPage);
	sub outputSample {
		do {
			my $pdf = sprintf("$pdfdir/%05d.pdf", $startPage);
			if (-f $pdf) {
				if ($sampleType eq "s") {
					system "../poppler/utils/pdftoppm -scale-to 480 -jpeg $pdf $outdir/";
					move "$outdir/00001.jpg", sprintf("$outdir/s_$contentsID"."_%04d.jpg", $startPage);
				}
				elsif ($sampleType eq "t") {
					system "../poppler/utils/pdftoppm -scale-to-x 198 -scale-to-y 285 -jpeg $pdf $outdir/";
					move "$outdir/00001.jpg", sprintf("$outdir/t_$contentsID"."_%04d.jpg", $startPage);
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
	
	if (-f "$dir/cover.pdf") {
		system "../poppler/utils/pdftoppm -l 1 -scale-to 480 -jpeg $dir/cover.pdf $workdir/cover";
		move "$workdir/cover00001.jpg", "$destdir/$contentsID.jpg";
	}
	else {
		my $dh;
		opendir($dh, "$dir/appendix");
		my @files = sort grep {/^.*\.jpg$/} readdir($dh);
		closedir($dh);
		
		my $image = Image::Magick->new;
		$image->Read("$dir/appendix/".$files[0]);
		$image->Scale(geometry => "480x480");
		$image->Write("$destdir/$contentsID.jpg");
	}
	
	# zip
	if (-e $outfile) {
		unlink $outfile;
	}
	my $zip = Archive::Zip->new();
	$zip->addTree($outdir, '');
	$zip->writeToFileNamed($outfile)
}

my $src = $ARGV[0];
my $dest = $ARGV[1];

if ($src =~ /^.+\/$/) {
	my $dir;
	opendir($dir, $src);
	my @files = grep { !/^\.$/ and !/^\.\.$/ } readdir $dir;
	foreach my $file (@files) {
		generate("$src$file", $dest);
	}
	closedir($dir);
}
else {
	generate($src, $dest);
}
