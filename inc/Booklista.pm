package Booklista;
use File::Basename;
use File::Copy;
use Archive::Zip;
use Image::Magick;

use Utils;

require Exporter;
@ISA	= qw(Exporter);

use utf8;
use strict;

sub generate {
	our $base = dirname(__FILE__);

	my $dir = $_[0];
	my $destdir = $_[1];
	my $contentsID = basename($dir);
	
	our $pdfdir = "$dir/magazine";
	my $metafile1 = "$dir/$contentsID.xml";
	my $metafile2 = "$dir/m_$contentsID.xml";
	my $workdir = "$dir/work";
	our $outdir = "$workdir/sample";
	our $epubdir = "$workdir/epub";
	my $outfile = "$destdir/st_$contentsID.zip";
	my $opf = $contentsID."_opf.opf";
	
	our $previewPageOrigin = 1;
	
	# 変換に使うプログラム
	our $program = 'poppler';
	
	# 単一PDFで最初のページだけカバーにする
	our $extractcover = 0;
	
	if (! -f $metafile1) {
		print "$dir: メタ情報XMLファイル ($contentsID.xml) がありません。\n";
		return 0;
	}
	
	Utils::status('サンプル画像を生成します');
	
	my $thumbnail_height = 480;
	for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
		if ( $ARGV[$i] eq '-thumbnail-height' ) {
			$thumbnail_height = $ARGV[ ++$i ] + 0;
		}
		elsif ( $ARGV[$i] eq '-previewPageOrigin' ) {
			if ($ARGV[ ++$i ] eq '0') {
				$previewPageOrigin = 0;
			}
		}
		elsif ( $ARGV[$i] eq '-program' ) {
			my $op = $program;
			$program = $ARGV[ ++$i ];
			if ($i < @ARGV - 1) {
				my $pages = $ARGV[ $i + 1 ];
				if ($pages =~ /^[0-9,]+$/) {
					$program = $op;
					++$i;
				}
			}
		}
		elsif ( $ARGV[$i] eq '-extractcover' ) {
			$extractcover = 1;
		}
	}
		
	mkdir $workdir;
	mkdir $outdir;
	mkdir $destdir;
	copy($metafile2, "$outdir/m_$contentsID.xml");
	copy("$workdir/epub/$opf", "$destdir/$opf");
	
	# Read meta data.
	# サンプル画像
	sub outputSample {
		my ($dir, $contentsID, $sampleType, $startPage, $endPage) = @_;
		my %opts = ();
		if ($sampleType eq "s") {
			$opts{w} = $opts{h} = 480;
		}
		elsif ($sampleType eq "t") {
			$opts{w} = 198;
			$opts{h} = 285;
		}
		$opts{suffix} = 'jpg';
		my $pdf = "$dir/$contentsID.pdf";
		if (-f $pdf) {
			# 単一のPDF
			
			Utils::status("ページ分割されていないPDFを処理します($startPage - $endPage)");
			if ($extractcover) {
				if ($startPage == -1) {
					Utils::pdftoimage($program, $pdf, "$outdir/", \%opts, 2, -1);
				}
				else {
					Utils::pdftoimage($program, $pdf, "$outdir/", \%opts, $startPage == 0 ? 1 : $startPage + 1, $endPage + 1);
				}
			}
			else {
				if ($startPage == -1) {
					Utils::pdftoimage($program, $pdf, "$outdir/", \%opts, -1);
				}
				else {
					Utils::pdftoimage($program, $pdf, "$outdir/", \%opts, $startPage == 0 ? 1 : $startPage, $endPage);
				}
			}
			if ($startPage == -1) {
				$startPage = 1;
			}
			for (my $i = $startPage; ; ++$i) {
				my $file;
				if ($extractcover) {
					$file = sprintf("$outdir/%05d.jpg", $i + 1);
				}
				else {
					$file = sprintf("$outdir/%05d.jpg", $i);
				}
				if (!(-f $file)) {
					last;
				}
				move $file, sprintf("$outdir/$sampleType"."_$contentsID"."_%04d.jpg", $i);
			}
			return;
		}
		
		Utils::status("ページ分割されたPDFを処理します($startPage - $endPage)");
		do {
			Utils::status($startPage);
			$pdf = sprintf("$pdfdir/%05d.pdf", $startPage);
			if (-f $pdf) {
				Utils::pdftoimage($program, $pdf, "$outdir/", \%opts, -1);
				if ($?) {
					print STDERR "$dir: $pdf をJPEGに変換する際にエラーが発生しました。\n";
				}
				else {
					move "$outdir/00001.jpg", sprintf("$outdir/$sampleType"."_$contentsID"."_%04d.jpg", $startPage);
				}
			}
			++$startPage;
		} while ($startPage <= $endPage);
	}
    
	my ($sampleType, $startPage, $endPage);
	my $xp = XML::XPath->new(filename => $metafile1);
	my $samples = $xp->find("/Content/ContentInfo/PreviewPageList/PreviewPage");
	
	Utils::status('ちび見を生成します');
	$sampleType = "s";
	foreach my $node ($samples->get_nodelist) {
		$xp = XML::XPath->new(context => $node);
		$startPage = Utils::trim($xp->findvalue("StartPage/text()")->value) - $previewPageOrigin;
		$endPage = Utils::trim($xp->findvalue("EndPage/text()")->value) - $previewPageOrigin;
		outputSample($dir, $contentsID, $sampleType, $startPage, $endPage);
	}
	if (-f $metafile2) {
		$xp = XML::XPath->new(filename => $metafile2);
		$sampleType = Utils::trim($xp->findvalue("/ContentsSample/SampleType/text()")->value);
		if ($sampleType eq "s") {
			$startPage = Utils::trim($xp->findvalue("/ContentsSample/StartPage/text()")->value) - $previewPageOrigin;
			$endPage = Utils::trim($xp->findvalue("/ContentsSample/EndPage/text()")->value) - $previewPageOrigin;
			outputSample($dir, $contentsID, $sampleType, $startPage, $endPage);
		}
	}
	
	$sampleType = "t";
	Utils::status('ちら見を生成します');
	if (-d $pdfdir) {
		# ページ分割されたPDF
		my $dh;
		opendir($dh, $pdfdir);
		my @files = sort grep {/^\d{5}\.pdf$/} readdir($dh);
		closedir($dh);
		$startPage = $files[0];
		$startPage =~ s/\.pdf//;
		$endPage = $files[-1];
		$endPage =~ s/\.pdf//;
		outputSample($dir, $contentsID, $sampleType, $startPage, $endPage);
	}
	else {
		# 単一のPDF
		outputSample($dir, $contentsID, $sampleType, -1, -1);
	}
	
	if (-f "$dir/cover.pdf") {
		my %opts = ();
		$opts{h} = $thumbnail_height;
		$opts{w} = $thumbnail_height;
		$opts{suffix} = "jpg";
		Utils::pdftoimage($program, "$dir/cover.pdf", "$workdir/coverx.jpg", \%opts);
		if ($?) {
			print STDERR "$dir: cover.pdf をJPEGに変換する際にエラーが発生しました。\n";
		}
		else {
			move "$workdir/coverx.jpg", "$destdir/$contentsID.jpg";
		}
	}
	else {
		my $file;
		
		if (-f "$dir/cover.jpg") {
			$file = "$dir/cover.jpg";
		}
		elsif(-d "$dir/appendix") {
			my $dh;
			opendir($dh, "$dir/appendix");
			my @files = sort grep {/^[^\.].*\.jpg$/} readdir($dh);
			closedir($dh);
			if (@files) {
				$file = "$dir/appendix/".$files[0];
			}
		}
		else {
			my $dh;
			opendir($dh, $epubdir);
			my @files = sort grep {/^[^\.].*\.jpg$/} readdir($dh);
			closedir($dh);
			if (@files) {
				$file = "$epubdir/".$files[0];
			}
		}
		if (-f $file) {
			my $image = Image::Magick->new;
			$image->Read($file);
			my ($cw, $ch) = $image->Get('width', 'height');
			$image->Scale(geometry => $thumbnail_height.'x'.$thumbnail_height);
			$image->Write("$destdir/$contentsID.jpg");
		}
	}
	
	# zip
	if (-e $outfile) {
		unlink $outfile;
	}
	my $zip = Archive::Zip->new();
	$zip->addTree($outdir, '');
	$zip->writeToFileNamed($outfile);
	return 1;
}
