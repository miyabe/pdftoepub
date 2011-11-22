#!/usr/bin/perl
use File::Find;
use File::Basename;
use File::Copy;
use File::Path;
use File::Temp;
use Data::UUID;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use HTML::Entities;
use Image::Size;
use Image::Magick;

use utf8;
use strict;
use warnings;

binmode STDOUT, ":utf8";

# 画面の高さ
our $view_height = 2068;

# ファイルポインタ格納用
our $fp;

# 出力先ディレクトリ
our $outdir;

# 変換元のPDFのディレクトリ
our $pdfdir;

# プログラムのベースディレクトリ
our $base = dirname(__FILE__);

sub trim {
	my $val = shift;
	$val =~ s/^\s*(.*?)\s*$/$1/;
	return $val;
}

sub transcode {
	my $dir = $_[0];
	my $contentsID = basename($dir);
	
	my $pdfdir = "$dir/$contentsID.pdf";
	if (!(-f $pdfdir)) {
		$pdfdir = "$dir/magazine";
	}
	
	my $metafile = "$dir/$contentsID.xml";
	my $insertdir = "$base/ins";
	my $workdir = "$dir/work";
	$outdir = "$workdir/epub";
	my $outfile = "$workdir/$contentsID"."_eEPUB3.epub";
	my $opf = $contentsID."_opf.opf";
	my $otf = 0;
	my $raster = 0;
	
	if (! -f $metafile) {
		print STDERR "$dir: メタ情報XMLファイル ($contentsID.xml) がないため処理できませんでした。\n";
		return 0;
	}
	
	if(@_ >= 2) {
		mkdir $_[1];
		$outfile = $_[1]."/$contentsID"."_eEPUB3.epub";
	}
	(@_ >= 3) and $raster = $_[2];
	
	rmtree $workdir;
	mkdir $workdir;
	mkdir $outdir;
	
	# メタデータを読み込む
	my ($publisher, $publisher_kana, $name, $kana, $cover_date, $sales_date, $sales_yyyy, $sales_mm, $sales_dd, $introduce, $issued, $ppd, $orientation, $modified, $datatype);
	{
		my $xp = XML::XPath->new(filename => $metafile);
		
		$publisher = $xp->findvalue("/Content/PublisherInfo/Name/text()")->value;
		if ($publisher) {
			$publisher = trim(encode_entities($publisher, '<>&"'));
		}
		
		$publisher_kana = $xp->findvalue("/Content/PublisherInfo/Kana/text()")->value;
		if ($publisher_kana) {
			$publisher_kana = trim(encode_entities($publisher_kana, '<>&"'));
		}
		
		$name = $xp->findvalue("/Content/MagazineInfo/Name/text()")->value;
		if ($name) {
			$name = trim(encode_entities($name, '<>&"'));
		}
		
		$kana = $xp->findvalue("/Content/MagazineInfo/Kana/text()")->value;
		if ($kana) {
			$kana = trim(encode_entities($kana, '<>&"'));
		}
		
		$cover_date = $xp->findvalue("/Content/CoverDate/text()")->value;
		if ($cover_date) {
			$cover_date = trim(encode_entities($cover_date, '<>&"'));
		}
		
		$sales_date = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($sales_date) {
			($sales_yyyy, $sales_mm, $sales_dd) = ($sales_date =~ /(\d+)-(\d+)-(\d+)/);
		}
		
		$introduce = $xp->findvalue("/Content/IntroduceScript/text()")->value;
		if ($introduce) {
			$introduce = trim(encode_entities($introduce, '<>&"'));
		}
		
		$issued = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($issued) {
			$issued = trim(encode_entities($issued, '<>&"'));
		}
		
		$ppd = trim($xp->findvalue("/Content/ContentInfo/PageOpenWay/text()")->value);
		$ppd = ($ppd == 1) ? 'ltr' : 'rtl';
		
		$orientation = trim($xp->findvalue("/Content/ContentInfo/Orientation/text()")->value);
		if (!$orientation) {
			$orientation = 'auto';
		}	
		elsif ($orientation == 1) {
			$orientation = 'portrait';
		}
		elsif ($orientation == 2) {
			$orientation = 'landscape';
		}
		else {
			$orientation = 'auto';
		}
		
		$modified = time2str("%Y-%m-%dT%H:%M:%SZ", time, "GMT");
		
		$datatype = trim($xp->findvalue("/Content/DataType/text()")->value);
		if (!$datatype) {
			$datatype = 'magazine';
		}
		
		# 目次
		my $indexList = $xp->find("/Content/ContentInfo/IndexList/Index");
	    open($fp, "> $outdir/nav.xhtml");
	    binmode $fp, ":utf8";
			print $fp <<"EOD";
<!DOCTYPE html>
<html lang="ja"
      xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <meta charset="UTF-8" />
    <title>$name</title>
    <link rel="stylesheet" href="tocstyle/tocstyle.css" type="text/css"/>
  </head>
  <body>
  <nav epub:type="lot">
    <ol>
EOD
		foreach my $index ($indexList->get_nodelist) {
			my $title = trim($xp->findvalue("Title/text()", $index)->value);
			$title = encode_entities($title, '<>&"');
			my $startPage = trim($xp->findvalue("StartPage/text()", $index)->value) - 1;
			my $file = sprintf("%05d.svg", $startPage);
			print $fp <<"EOD";
		<li><a href="$file">$title</a></li>
EOD
		}
			print $fp <<"EOD";
    </ol>
  </nav>
  </body>
</html>
EOD
		close($fp);
	}
	
	# 画像をSVGでくるむ
	sub wrapimage {
		my ($infile, $outfile, $w, $h, $left) = @_;
		my ($ww, $hh) = imgsize($infile);
		
		if ($hh != $h) {
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
		if ($left) {
			$x = $w - $ww + 1;
		}
		else {
			$x = -1;
		}
		
		my $file = basename($infile);
		open($fp, "> $outfile");
		binmode $fp, ":utf8";
		print $fp <<"EOD";
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
  width="100%" height="100%" viewBox="0 0 $w $h">
  <image x="$x" width="$ww" height="$hh" xlink:href="$file" />
</svg>
EOD
		close($fp);
	}
	
	# PDFからSVGまたは画像に変換する
	{
		if ($raster) {
			my $dh;
			my ($w, $h);
			if (-d $pdfdir) {
				opendir $dh, "$pdfdir";
				my @files = grep {/^\d{5}\.pdf$/} readdir $dh;
				closedir($dh);
				foreach my $file (@files) {
					my ($num) = ($file =~ /^(\d{5})\.pdf$/);
					system "$base/../poppler/utils/pdftoppm -cropbox -jpeg -scale-to $view_height $pdfdir/$file > $outdir/$num.jpg";
					if ($?) {
						print STDERR "$dir: $file をJPEGに変換する際にエラーが発生しました。\n";
					}
				}
			}
			else {
				system "$base/../poppler/utils/pdftoppm -cropbox -jpeg -scale-to $view_height $pdfdir $outdir/";
				if ($?) {
					print STDERR "$dir: $pdfdir をJPEGに変換する際にエラーが発生しました。\n";
				}
			}
			opendir $dh, "$outdir";
			my @files = sort grep {/^\d{5}\.jpg$/} readdir $dh;
			closedir($dh);
			($w, $h) = imgsize("$outdir/".$files[0]);
			if (-f "$dir/cover.pdf") {
				system "$base/../poppler/utils/pdftoppm -cropbox -jpeg -scale-to $view_height $dir/cover.pdf > $outdir/00000.jpg";
				if ($?) {
					print STDERR "$dir: cover.pdf をJPEGに変換する際にエラーが発生しました。\n";
					last;
				}
				($w, $h) = imgsize("$outdir/00000.jpg");
			}
			elsif (-f "$dir/cover.jpg") {
				copy "$dir/cover.jpg", "$outdir/00000.jpg";
			}
			opendir $dh, "$outdir";
			@files = sort grep {/^\d{5}\.jpg$/} readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				my ($i) = ($file =~ /^(\d+)\.jpg$/);
				wrapimage("$outdir/$file", "$outdir/$i.svg",
					$w, $h, ($i % 2 == (($ppd eq 'rtl') ? 0 : 1)));
			}
		}
		else {
			system "$base/pdftosvg $pdfdir $outdir".($otf ? ' true' : '');
			if (!(-f "$dir/cover.pdf")) {
				if (-f "$dir/cover.jpg") {
					copy "$dir/cover.jpg", "$outdir/00000.jpg";
				}
				if (-f "$outdir/00000.jpg") {
					my $dir;
					opendir($dir, $outdir);
					my @files = sort grep {/^\d{5}\.svg$/} readdir($dir);
					closedir($dir);
					my $xp = XML::XPath->new(filename => "$outdir/".$files[0]);
					my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
					my ($width, $height) = ($viewBox =~ /^0 0 (\d+) (\d+)$/);
					wrapimage("$outdir/00000.jpg", "$outdir/00000.svg",
							$width, $height, ($ppd eq 'rtl'));
				}
			}
		}
		
		if ($otf) {
			opendir my $dir, "$outdir/fonts";
			my @files = grep {/^.+\.svg$/} readdir $dir;
			foreach my $file (@files) {
				if ($file =~ /^.+\.svg$/) {
					system "./tootf.pe $outdir/fonts/$file";
				}
			}
			closedir $dir;
			
			system "rm $outdir/fonts/*.svg";
			
			opendir $dir, $outdir;
			@files = grep {/^.+\.svg$/} readdir $dir;
			foreach my $file (@files) {
				open my $in, "< $outdir/$file";
				open my $out, "> $outdir/$file.tmp";
				foreach my $line (<$in>) {
					$line =~ s/src: url\(\"fonts\/font\-(\d+)\.svg\"\) format\(\"svg\"\);/src: url\(\"fonts\/font\-$1\.otf\"\) format\(\"opentype\"\);/s;
					print $out $line;
				}
				close $in;
				close $out;
				unlink "$outdir/$file";
				rename "$outdir/$file.tmp", "$outdir/$file";
			}
			closedir $dir;
		}
		
		if ($insertdir) {
			system "cp -r $insertdir/* $outdir";
		}
	}
	
	# Generate BookID.
	my $uuid;
	{
		my $ug = new Data::UUID;
		$uuid = $ug->to_string($ug->create());
	}
	
	my @files;
	{
		my $dir;
		opendir($dir, $outdir);
		@files = sort grep {/^\d{5}\.svg$/} readdir($dir);
		closedir($dir);
	}
	
	# Check SVG viewBox.
	my ($width, $height);
	{
		my $xp = XML::XPath->new(filename => "$outdir/".$files[0]);
		my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
		($width, $height) = ($viewBox =~ /^0 0 (\d+) (\d+)$/);
	}
	
	# mimetype
	{
		open($fp, "> $outdir/mimetype");
		print $fp "application/epub+zip";
		close($fp);
	}
	
	# container.xml
	{
		my $dir = "$outdir/META-INF";
		unless(-d $dir) {
			mkdir($dir, 0755);
		}
	    open($fp, "> $dir/container.xml");
	    print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="$opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOD
	    close($fp);
	}
	
	# OPF
	{
	    open($fp, "> $outdir/$opf");
	    binmode $fp, ":utf8";
	    print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf"
         prefix="layout: http://xmlns.sony.net/e-book/prs/layoutoptions/
         prism: http://prismstandard.org/namespaces/basic/2.1
         prs: http://xmlns.sony.net/e-book/prs/"
         version="3.0"
         unique-identifier="BookID">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:language>ja</dc:language>
    <dc:identifier id="BookID">urn:uuid:$uuid</dc:identifier>
    <dc:title id="title">$name $cover_date</dc:title>
    <dc:publisher id="publisher">$publisher</dc:publisher>
    <dc:description>$introduce</dc:description>
    <meta property="dcterms:modified">$modified</meta>
    <meta property="dcterms:issued">$issued</meta>
    <meta id="publication" property="prism:publicationName">$name</meta>
    <meta refines="#title" property="file-as">$kana $sales_date</meta>
    <meta refines="#publisher" property="file-as">$publisher_kana</meta>
    <meta refines="#publication" property="file-as">$kana</meta>
    <meta property="prism:volume">$sales_yyyy</meta>
    <meta property="prism:number">${sales_mm}${sales_dd}</meta>
    <meta property="layout:fixed-layout">true</meta>
    <meta property="layout:orientation">$orientation</meta>
    <meta property="layout:viewport">width=$width, height=$height</meta>
    <meta property="prs:datatype">$datatype</meta>
  </metadata>
  <manifest>
EOD
	# <meta property="layout:overflow-scroll">true</meta>
	
	# マニフェスト
		# nav
		print $fp "    <item id=\"nav\" href=\"nav.xhtml\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n";
	
		our $i = 0;
	
		#--------------------------------------------
		#ファイルが見つかる度に呼び出される
		#--------------------------------------------
		sub wanted {
		# 通常ファイル以外は除外
			-f $_ or return;
			my $basename = substr($File::Find::name, length($outdir) + 1);
			$basename =~ /^size$/ and return;
			$basename =~ /^mimetype$/ and return;
			$basename =~ /^.*\.opf$/ and return;
			$basename =~ /^nav\.xhtml$/ and return;
			$basename =~ /^.+\.epub$/ and return;
			$basename =~ /^META-INF\/.*$/ and return;
			$basename =~ /^.*\.svg$/ and return;
			
			++$i;
			print $fp "    <item id=\"r$i\" href=\"$basename\" media-type=\"";
			if (/^.*\.png$/) {
				print $fp "image/png";
			}
			elsif (/^.*\.gif$/) {
				print $fp "image/gif";
			}
			elsif (/^.*\.jpg$/) {
				print $fp "image/jpeg";
			}
			elsif (/^.*\.css$/) {
				print $fp "text/css";
			}
			elsif (/^.*\.js$/) {
				print $fp "text/javascript";
			}
			elsif (/^.*\.svg$/) {
				print $fp "image/svg+xml";
			}
			elsif (/^.*\.html$/) {
				print $fp "application/xhtml+xml";
			}
			elsif (/^.*\.otf$/) {
				print $fp "font/otf";
			}
			print $fp "\"/>\n";
		}
	
		#-- ディレクトリを指定(複数の指定可能) --#
		my @directories_to_search = ($outdir);
	
		#-- 実行 --#
		find(\&wanted, @directories_to_search);
	    
	    our @items = ();
	    
	    sub insert {
	    	my $j = 1;
	    	while(-f sprintf("$outdir/%05d-%05d/main.html", $i, $j)) {
	    		my $id = "t$i-$j";
	    		my $file = sprintf("%05d-%05d/main.html", $i, $j);
	    		print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"application/xhtml+xml\"/>\n";
	    		push @items, [$id, $file];
	    		++$j;
	    	}
	    }
		$i = -1;
		my $max = $files[-1];
		$max =~ s/\..+$//;
	    while($i < $max) {
	     	++$i;
	    	if (-f sprintf("$outdir/%05d.svg", $i)) {
		    	my $id = "t$i";
		    	my $file = sprintf("%05d.svg", $i);
		    	print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"image/svg+xml\"/>\n";
		    	push @items, [$id, $file, $i];
		    	insert();
	    	}
	    }
	    
	    print $fp <<"EOD";
  </manifest>
  <spine page-progression-direction="$ppd">
EOD
	
		foreach my $item ( @items ) {
			my ($id, $file, $i) = @$item;
	    	my $props = ($i % 2 == (($ppd eq 'rtl') ? 0 : 1)) ? "page-spread-left" : "page-spread-right";
	    	print $fp "    <itemref idref=\"$id\" properties=\"$props\"/>\n";
	    }
	    
	    print $fp <<"EOD";
  </spine>
</package>
EOD
	
	    close($fp);
	}
	
	# zip
	if (-e $outfile) {
		unlink $outfile;
	}
	my $zip = Archive::Zip->new();
	$zip->addFile("$outdir/mimetype", 'mimetype');
	my ($mimetype) = $zip->members();
	$mimetype->desiredCompressionLevel(0);
	$zip->addTree($outdir, '', sub { !($_ =~ /.*\/mimetype$/) and !($_ =~ /.*\/size$/) });
	$zip->writeToFileNamed($outfile);
	
	# check
	my $tmp = tmpnam();
	system "java -cp \"$base/lib/jing.jar:$base/lib/saxon9he.jar:$base/lib/flute.jar:$base/lib/sac.jar\" -jar \"$base/epubcheck-3.0b2.jar\" $outfile 2> $tmp";
	if ($?) {
		print STDERR "$dir: EPUBチェッカの実行時にエラーがありました。\n";
		unlink $tmp;
	}
	
	open $fp, "< $tmp";
	my $err = 0;
	while (<$fp>) {
		print STDERR $_;
		if (!$err && $_) {
			$err = 1;
		}
	}
	close $fp;
	unlink $tmp;
	if ($err) {
		return 0;
	}
	
	return 1;
}

sub generate {
	my $dir = $_[0];
	my $destdir = $_[1];
	my $contentsID = basename($dir);
	
	$pdfdir = "$dir/magazine";
	my $metafile1 = "$dir/$contentsID.xml";
	my $metafile2 = "$dir/m_$contentsID.xml";
	my $workdir = "$dir/work";
	$outdir = "$workdir/sample";
	my $outfile = "$destdir/st_$contentsID.zip";
	my $opf = $contentsID."_opf.opf";
	
	if (! -f $metafile1) {
		print "$dir: メタ情報XMLファイル ($contentsID.xml) がありません。\n";
		return 0;
	}
	
	mkdir $workdir;
	mkdir $outdir;
	mkdir $destdir;
	copy($metafile2, "$outdir/m_$contentsID.xml");
	copy("$workdir/epub/$opf", "$destdir/$opf");
	
	# Read meta data.
	sub outputSample {
		my ($dir, $contentsID, $sampleType, $startPage, $endPage) = @_;
		do {
			my $pdf = sprintf("$pdfdir/%05d.pdf", $startPage);
			if (-f $pdf) {
				if ($sampleType eq "s") {
					system "$base/../poppler/utils/pdftoppm -cropbox -scale-to 480 -jpeg $pdf $outdir/";
					if ($?) {
						print STDERR "$dir: $pdf をJPEGに変換する際にエラーが発生しました。\n";
					}
					else {
						move "$outdir/00001.jpg", sprintf("$outdir/s_$contentsID"."_%04d.jpg", $startPage);
					}
				}
				elsif ($sampleType eq "t") {
					system "$base/../poppler/utils/pdftoppm -cropbox -scale-to-x 198 -scale-to-y 285 -jpeg $pdf $outdir/";
					if ($?) {
						print STDERR "$dir: $pdf をJPEGに変換する際にエラーが発生しました。\n";
					}
					else {
						move "$outdir/00001.jpg", sprintf("$outdir/t_$contentsID"."_%04d.jpg", $startPage);
					}
				}
			}
			++$startPage;
		} while ($startPage <= $endPage);
	}
	my ($sampleType, $startPage, $endPage);
	my $xp = XML::XPath->new(filename => $metafile1);
	my $samples = $xp->find("/Content/ContentInfo/PreviewPageList/PreviewPage");
	$sampleType = "s";
	foreach my $node ($samples->get_nodelist) {
		$xp = XML::XPath->new(context => $node);
		$startPage = trim($xp->findvalue("StartPage/text()")->value);
		$endPage = trim($xp->findvalue("EndPage/text()")->value);
		outputSample($dir, $contentsID, $sampleType, $startPage, $endPage);
	}
	
	$sampleType = "t";
	my $dh;
	opendir($dh, $pdfdir);
	my @files = sort grep {/^\d{5}\.pdf$/} readdir($dh);
	closedir($dh);
	$startPage = $files[0];
	$startPage =~ s/\.pdf//;
	$endPage = $files[-1];
	$endPage =~ s/\.pdf//;
	outputSample($dir, $contentsID, $sampleType, $startPage, $endPage);
	
	if (-f "$dir/cover.pdf") {
		system "$base/../poppler/utils/pdftoppm -cropbox -l 1 -scale-to 480 -jpeg $dir/cover.pdf $workdir/cover";
		if ($?) {
			print STDERR "$dir: cover.pdf をJPEGに変換する際にエラーが発生しました。\n";
		}
		else {
			move "$workdir/cover00001.jpg", "$destdir/$contentsID.jpg";
		}
	}
	else {
		my $file;
		
		if (-f "$dir/cover.jpg") {
			$file = "$dir/cover.jpg";
		}
		else {
			my $dh;
			opendir($dh, "$dir/appendix");
			my @files = sort grep {/^[^\.].*\.jpg$/} readdir($dh);
			closedir($dh);
			if (@files) {
				$file = "$dir/appendix/".$files[0];
			}
		}
		if (-f $file) {
			my $image = Image::Magick->new;
			$image->Read($file);
			$image->Scale(geometry => "480x480");
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

my $src = $ARGV[0];
my $dest = $ARGV[1];
my $jpg = 0;
(@ARGV >= 3) and $jpg = $ARGV[2];

sub process {
	my $src = $_[0];
	my $ret = 1;
	if ($jpg eq 'raster') {
		transcode($src, $dest, 1) or ($ret = 0);
		generate($src, $dest) or ($ret = 0);
	}
	elsif ($jpg eq 'svg') {
		transcode($src, $dest, 0) or ($ret = 0);
		generate($src, $dest) or ($ret = 0);
	}
	else {
		my $destdir = "$dest/raster";
		mkdir $destdir;
		transcode($src, $destdir, 1) or ($ret = 0);
		generate($src, $destdir) or ($ret = 0);
		$destdir = "$dest/svg";
		mkdir $destdir;
		transcode($src, $destdir, 0) or ($ret = 0);
		generate($src, $destdir) or ($ret = 0);
	}
	return $ret;
}
if ($src =~ /^.+\/$/) {
	my $dir;
	opendir($dir, $src);
	my @files = grep { !/^\.$/ and !/^\.\.$/ and -d "$src$_"} readdir $dir;
	closedir($dir);
	foreach my $file (@files) {
		eval{
			process("$src$file");
		};
		if ($@) {
			print STDERR "$src: 処理を中断しました。エラー: $@";
		}
	}
}
else {
	eval{
		process($src) or exit(-1);
	};
	if ($@) {
		print STDERR "$src: 処理を中断しました。エラー: $@";
		exit(-1);
	}
}
exit(0);
