﻿#!/usr/bin/perl
use File::Find;
use File::Basename;
use File::Copy;
use Data::UUID;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use HTML::Entities;

use utf8;
use strict;

binmode STDOUT, ":utf8";

my $dir = $ARGV[0];
my $contentsID = basename($dir);

#my $pdfdir = "$dir/$contentsID.pdf";
my $pdfdir = "$dir/magazine";
my $metafile = "$dir/$contentsID.xml";
my $insertdir = "work/ins";
my $workdir = "$dir/work";
my $outdir = "$workdir/epub";
my $outfile = "$workdir/$contentsID"."_eEPUB3.epub";
#my $outfile = "out/$contentsID"."_eEPUB3.epub";
my $opf = $contentsID."_opf.opf";
my $otf = 0;
my $raster = 1;

mkdir $workdir;

# Generate SVGs
{
	if ($raster) {
		if (-d $pdfdir) {
			opendir my $dir, "$pdfdir";
			my @files = grep {/^.+\.pdf$/} readdir $dir;
			foreach my $file (@files) {
				my ($num) = ($file =~ /^(\d+)\.pdf$/);
				system "../poppler/utils/pdftoppm -jpeg -scale-to 1280 $pdfdir/$file > $outdir/$num.jpg";
			}
		}
		else {
			system "../poppler/utils/pdftoppm -jpeg -scale-to 1280 $pdfdir $outdir/";
		}
	}
	else {
		system "./pdftosvg $pdfdir $outdir".($otf ? ' true' : '');
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
		
		opendir my $dir, $outdir;
		my @files = grep {/^.+\.svg$/} readdir $dir;
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

# Read meta data.
my ($publisher, $publisher_kana, $name, $kana, $cover_date, $sales_date, $sales_yyyy, $sales_mm, $sales_dd, $introduce, $issued, $ppd, $modified);
{
	my $xp = XML::XPath->new(filename => $metafile);
	
	$publisher = $xp->findvalue("/Content/PublisherInfo/Name/text()")->value;
	$publisher = encode_entities($publisher, '<>&"');
	
	$publisher_kana = $xp->findvalue("/Content/PublisherInfo/Kana/text()")->value;
	$publisher_kana = encode_entities($publisher, '<>&"');
	
	$name = $xp->findvalue("/Content/MagazineInfo/Name/text()")->value;
	$name = encode_entities($name, '<>&"');
	
	$kana = $xp->findvalue("/Content/MagazineInfo/Kana/text()")->value;
	$kana = encode_entities($kana, '<>&"');
	
	$cover_date = $xp->findvalue("/Content/CoverDate/text()")->value;
	$cover_date = encode_entities($cover_date, '<>&"');
	
	$sales_date = $xp->findvalue("/Content/SalesDate/text()")->value;
	($sales_yyyy, $sales_mm, $sales_dd) = ($sales_date =~ /(\d+)-(\d+)-(\d+)/);
	
	$introduce = $xp->findvalue("/Content/IntroduceScript/text()")->value;
	$introduce = encode_entities($introduce, '<>&"');
	
	$issued = $xp->findvalue("/Content/SalesDate/text()")->value;
	
	$ppd = $xp->findvalue("/Content/ContentInfo/PageOpenWay/text()")->value;
	$ppd = ($ppd == 1) ? 'ltr' : 'rtl';
	
	$modified = time2str("%Y-%m-%dT%H:%M:%SZ", time, "GMT");
	
	# TOC
	my $indexList = $xp->find("/Content/ContentInfo/IndexList/Index");
	my $fp;
    open($fp, "> $outdir/nav.xhtml");
    binmode $fp, ":utf8";
		print $fp <<"EOD";
<!DOCTYPE html>
<html lang="ja"
      xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www,idpf.org/2007/ops">
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
		my $title = $xp->findvalue("Title/text()", $index)->value;
		$title = encode_entities($title, '<>&"');
		my $startPage = $xp->findvalue("StartPage/text()", $index)->value;
		print $fp <<"EOD";
		if (-f "$outdir/.jpg")
      		<li><a href="$startPage.jpg">$title</a></li>
      	elsif (-f "$outdir/.png")
      		<li><a href="$startPage.png">$title</a></li>
      	else
      		<li><a href="$startPage.svg">$title</a></li>
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

my @files;
# Check SVG viewBox.
my ($width, $height);
{
	my $dir;
	opendir($dir, $outdir);
	@files = sort grep {/^.+\.svg$/ or /^.+\.jpg$/ or /^.+\.png$/} readdir($dir);
	closedir($dir);
	
	my $file = "$outdir/size";
	my $fp;
	open($fp, "< $file");
	($width, $height) = split(/ /, <$fp>);
	close($fp);
}

# mimetype
{
	my $fp;
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
	my $fp;
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
	my $fp;
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
    <meta property="layout:viewport">width=$width, height=$height</meta>
    <meta property="prs:datatype">magazine</meta>
  </metadata>
  <manifest>
EOD
# <meta property="layout:orientation">auto</meta>
# <meta property="layout:overflow-scroll">true</meta>

# マニフェスト
	# nav
	print $fp "    <index id=\"nav\" href=\"nav.xhtml\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n";

	#-- ディレクトリを指定(複数の指定可能) --#
	my @directories_to_search = ($outdir);

	#-- 実行 --#
	find(\&wanted, @directories_to_search);

	my $i = 0;

	#--------------------------------------------
	#ファイルが見つかる度に呼び出される
	#--------------------------------------------
	sub wanted {
	# 通常ファイル以外は除外
		-f $_ or return;
		my $basename = substr($File::Find::name, length($outdir) + 1);
		$basename =~ /^size$/ and return;
		$basename =~ /^mimetype$/ and return;
		$basename =~ /^*.\.opf$/ and return;
		$basename =~ /^nav\.xhtml$/ and return;
		$basename =~ /^.+\.epub$/ and return;
		$basename =~ /^META-INF\/.*$/ and return;
		$basename =~ /^.*\.svg$/ and return;
		$basename =~ /^.*\.jpg$/ and !($basename =~ /^images\/.*$/) and return;
		$basename =~ /^.*\.png$/ and !($basename =~ /^images\/.*$/) and return;
		
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
    
    my @items;
    
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
	    	push @items, [$id, $file];
	    	insert();
    	}
    	elsif (-f sprintf("$outdir/%05d.png", $i)) {
	    	my $id = "t$i";
	    	my $file = sprintf("%05d.png", $i);
	    	print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"image/png\"/>\n";
	    	push @items, [$id, $file];
	    	insert();
    	}
    	elsif (-f sprintf("$outdir/%05d.jpg", $i)) {
	    	my $id = "t$i";
	    	my $file = sprintf("%05d.jpg", $i);
	    	print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"image/jpeg\"/>\n";
	    	push @items, [$id, $file];
	    	insert();
    	}
    }
    
    print $fp <<"EOD";
  </manifest>
  <spine page-progression-direction="$ppd">
EOD

	my $props = ($ppd eq 'rtl') ? "page-spread-left" : "page-spread-right";
	foreach my $item ( @items ) {
		my ($id, $file) = @$item;
    	print $fp "    <itemref idref=\"$id\" properties=\"$props\"/>\n";
    	$props = ($props eq "page-spread-right") ? "page-spread-left" : "page-spread-right";
    }
    
    print $fp <<"EOD";
  </spine>
</package>
EOD

    close($fp);
}
copy "$outdir/$opf", "$workdir/$opf";

# zip
if (-e $outfile) {
	unlink $outfile;
}
my $zip = Archive::Zip->new();
$zip->addTree($outdir, '');
$zip->writeToFileNamed($outfile)