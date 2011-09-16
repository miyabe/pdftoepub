#!/usr/bin/perl
use File::Find;
use File::Basename;
use Data::UUID;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use HTML::Entities;

use utf8;
use strict;

binmode STDOUT, ":utf8";

my $pdf = $ARGV[0];
my $metafile = $ARGV[1];
my $insertdir = $ARGV[2];

my $outdir = $pdf;
$outdir =~ s/^(.*)\..*/$1/;
my $outfile = "$outdir.epub";

# Generate SVGs
{
	system "./pdftosvg $pdf $outdir true";
	system "./tootf.pe $outdir/fonts/*.svg";
	system "rm $outdir/fonts/*.svg";
	system "cp -r $insertdir/* $outdir";
	
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

# Generate BookID.
my $uuid;
{
	my $ug = new Data::UUID;
	$uuid = $ug->to_string($ug->create());
}

# Read meta data.
my ($publisher, $name, $issued, $ppd, $modified);
{
	my $xp = XML::XPath->new(filename => $metafile);
	$publisher = $xp->findvalue("/Content/PublisherInfo/Name/text()")->value;
	$publisher = encode_entities($publisher, '<>&"');
	
	$name = $xp->findvalue("/Content/MagazineInfo/Name/text()")->value;
	$name = encode_entities($name, '<>&"');
	
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

# Check SVG viewBox.
my ($width, $height);
{
	my $xp = XML::XPath->new(filename => "$outdir/1.svg");
	my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
	my ($x, $y);
	($x, $y, $width, $height) = split(/ /, $viewBox);
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
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOD
    close($fp);
}

# content.opf
{
	my $fp;
    open($fp, "> $outdir/content.opf");
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
    <dc:title id="title">$name</dc:title>
    <dc:publisher>$publisher</dc:publisher>
    <dc:description></dc:description>
    <meta property="dcterms:modified">$modified</meta>
    <meta property="dcterms:issued">$issued</meta>
    <meta property="prism:publicationName">$name</meta>
    <meta refines="#title" property="file-as">にゅーずうぃーくにほんばん</meta>
    <meta property="prism:volume">26</meta>
    <meta property="prism:number">34</meta>
    <meta property="layout:orientation">auto</meta>
    <meta property="layout:page-spread">double</meta>
    <meta property="layout:fixed-layout">true</meta>
    <meta property="layout:overflow-scroll">true</meta>
    <meta property="layout:viewport">width=$width, height=$height</meta>
    <meta property="prs:datatype">magazine</meta>
  </metadata>
  <manifest>
EOD

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
		$basename =~ /^mimetype$/ and return;
		$basename =~ /^content\.opf$/ and return;
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
    
    my @items;
    
    sub insert {
    	my $j = 1;
    	while(-f "$outdir/$i-$j/main.html") {
    		my $id = "t$i-$j";
    		my $file = "$i-$j/main.html";
    		print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"application/xhtml+xml\"/>\n";
    		push @items, [$id, $file];
    		++$j;
    	}
    }
	$i = 0;
    insert();
	$i = 1;
    while(-f "$outdir/$i.svg") {
    	my $id = "t$i";
    	my $file = "$i.svg";
    	print $fp "    <item id=\"$id\" href=\"$file\" media-type=\"image/svg+xml\"/>\n";
    	push @items, [$id, $file];
    	insert();
    	++$i;
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

# zip
if (-e $outfile) {
	unlink $outfile;
}
my $zip = Archive::Zip->new();
$zip->addTree($outdir, '');
$zip->writeToFileNamed($outfile)