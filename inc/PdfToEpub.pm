package PdfToEpub;
use File::Find;
use File::Basename;
use File::Path;
use File::Temp;
use File::Copy;
use Data::UUID;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use Image::Size;
use HTML::Entities;

use EpubCheck;
use EpubPackage;

require Exporter;
@ISA = qw(Exporter);

use utf8;
use strict;

# テキストのトリム
sub trim {
	my $val = shift;
	$val =~ s/^\s*(.*?)\s*$/$1/;
	return $val;
}

# 画像をSVGでくるむ
sub wrapimage {
	my ( $infile, $outfile, $w, $h, $left ) = @_;
	my ( $ww, $hh ) = imgsize($infile);

	if ( $hh != $h ) {
		$ww *= $h / $hh;
		$ww = int($ww);
		$hh = $h;
	}
	if ( $ww > $w ) {
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
	my $fp;
	open( $fp, "> $outfile" );
	binmode $fp, ":utf8";
	print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
  width="100%" height="100%" viewBox="0 0 $w $h">
  <image x="$x" width="$ww" height="$hh" xlink:href="$file" />
</svg>
EOD
	close($fp);
}

# SVGをXHTMLでくるむ
sub wrapsvg {
	my ( $infile, $outfile ) = @_;
	
	my $infp;
	open( $infp, "< $infile" );
	binmode $infp, ":utf8";
	my $fp;
	open( $fp, "> $outfile" );
	binmode $fp, ":utf8";
	print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html lang="ja-JP" xml:lang="ja-JP" xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="initial-scale=1.0" />
    <title>タイトル 1ページ</title>
  </head>
  <body>
    <div>
EOD
	<$infp>;
	while(<$infp>) {
		print $fp $_;
	}
	print $fp <<"EOD";
    </div>
  </body>
</html>
EOD
	close($fp);
	close($infp);
}

sub transcode {
	our $base     = dirname(__FILE__);
	our $pdftoppm = "$base/../../poppler/utils/pdftoppm";
	our $pdftosvg = "$base/../pdftosvg";
	our $tootf = "$base/../tootf.pe";

	# 画面の高さ
	our $view_height = 2068;

	# 画質
	our $default_qf  = 98;
	# 文字以外のアンチエイリアス
	our $aaVector    = 'yes';
	# 画像タイプ
	our $imageSuffix = 'jpg';
	# EPUB2互換
	my $epub2      = 0;
	
	for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
		if ( $ARGV[$i] eq '-view-height' ) {
			$view_height = $ARGV[ ++$i ];
		}
		elsif ( $ARGV[$i] eq '-aaVector' ) {
			$aaVector = $ARGV[ ++$i ];
		}
		elsif ( $ARGV[$i] eq '-quality' ) {
			$default_qf = $ARGV[ ++$i ];
		}
		elsif ( $ARGV[$i] eq '-png' ) {
			$imageSuffix = 'png';
		}
		elsif ( $ARGV[$i] eq '-epub2' ) {
			$epub2 = 1;
		}
	}

	my $dir        = $_[0];
	my $contentsID = basename($dir);

	my $pdfdir = "$dir/$contentsID.pdf";
	if ( !( -f $pdfdir ) ) {
		$pdfdir = "$dir/magazine";
	}

	my $metafile  = "$dir/$contentsID.xml";
	my $insertdir = "$base/ins";
	my $workdir   = "$dir/work";
	our $outdir    = "$workdir/epub";
	my $outfile   = "$workdir/$contentsID" . "_eEPUB3.epub";
	my $opf       = $contentsID . "_opf.opf";
	my $otf       = 0; # 1にするとOTFを出力する
	my $raster    = 0;
	our $fp;

	if ( !-f $metafile ) {
		print STDERR
"$dir: メタ情報XMLファイル ($contentsID.xml) がないため処理できませんでした。\n";
		return 0;
	}

	if ( @_ >= 2 ) {
		mkdir $_[1];
		$outfile = $_[1] . "/$contentsID" . "_eEPUB3.epub";
	}
	( @_ >= 3 ) and $raster = $_[2];
	( @_ >= 4 ) and $epub2 = $_[3];

	rmtree $workdir;
	mkdir $workdir;
	mkdir $outdir;

	# Generate BookID.
	my $uuid;
	{
		my $ug = new Data::UUID;
		$uuid = $ug->to_string( $ug->create() );
	}

	# メタデータを読み込む
	my (
		$publisher,   $publisher_kana, $name,       $kana,
		$cover_date,  $sales_date,     $sales_yyyy, $sales_mm,
		$sales_dd,    $introduce,      $issued,     $ppd,
		$orientation, $modified,       $datatype
	);
	our %pageToHeight  = ();
	our %pageToDpi     = ();
	our %pageToQuality = ();
	our %pageToFormat  = ();
	{
		my $xp = XML::XPath->new( filename => $metafile );

		$publisher =
		  $xp->findvalue("/Content/PublisherInfo/Name/text()")->value;
		if ($publisher) {
			$publisher = trim( encode_entities( $publisher, '<>&"' ) );
		}

		$publisher_kana =
		  $xp->findvalue("/Content/PublisherInfo/Kana/text()")->value;
		if ($publisher_kana) {
			$publisher_kana =
			  trim( encode_entities( $publisher_kana, '<>&"' ) );
		}

		$name = $xp->findvalue("/Content/MagazineInfo/Name/text()")->value;
		if ($name) {
			$name = trim( encode_entities( $name, '<>&"' ) );
		}

		$kana = $xp->findvalue("/Content/MagazineInfo/Kana/text()")->value;
		if ($kana) {
			$kana = trim( encode_entities( $kana, '<>&"' ) );
		}

		$cover_date = $xp->findvalue("/Content/CoverDate/text()")->value;
		if ($cover_date) {
			$cover_date = trim( encode_entities( $cover_date, '<>&"' ) );
		}

		$sales_date = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($sales_date) {
			( $sales_yyyy, $sales_mm, $sales_dd ) =
			  ( $sales_date =~ /(\d+)-(\d+)-(\d+)/ );
		}

		$introduce = $xp->findvalue("/Content/IntroduceScript/text()")->value;
		if ($introduce) {
			$introduce = trim( encode_entities( $introduce, '<>&"' ) );
		}

		$issued = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($issued) {
			$issued = trim( encode_entities( $issued, '<>&"' ) );
		}

		$ppd = trim(
			$xp->findvalue("/Content/ContentInfo/PageOpenWay/text()")->value );
		$ppd = ( $ppd == 1 ) ? 'ltr' : 'rtl';

		$orientation = trim(
			$xp->findvalue("/Content/ContentInfo/Orientation/text()")->value );
		if ( !$orientation ) {
			$orientation = 'auto';
		}
		elsif ( $orientation == 1 ) {
			$orientation = 'portrait';
		}
		elsif ( $orientation == 2 ) {
			$orientation = 'landscape';
		}
		else {
			$orientation = 'auto';
		}

		$modified = time2str( "%Y-%m-%dT%H:%M:%SZ", time, "GMT" );

		$datatype = trim( $xp->findvalue("/Content/DataType/text()")->value );
		if ( !$datatype ) {
			$datatype = 'magazine';
		}

		# 目次
		my $indexList = $xp->find("/Content/ContentInfo/IndexList/Index");

		# nav.xhtml
		open( $fp, "> $outdir/nav.xhtml" );
		binmode $fp, ":utf8";
		print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html lang="ja-JP" xml:lang="ja-JP"
      xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <meta charset="UTF-8" />
    <title>$name</title>
    <link rel="stylesheet" href="tocstyle/tocstyle.css" type="text/css"/>
  </head>
  <body>
  <nav epub:type="toc" id="toc">
    <ol>
EOD
		foreach my $index ( $indexList->get_nodelist ) {
			my $title = trim( $xp->findvalue( "Title/text()", $index )->value );
			$title = encode_entities( $title, '<>&"' );
			my $startPage =
			  trim( $xp->findvalue( "StartPage/text()", $index )->value ) - 1;
			my $file;
			if ($epub2) {
				$file = sprintf( "%05d.xhtml", $startPage );
			}
			else {
				$file = sprintf( "%05d.svg", $startPage );
			}
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

		# toc.ncx
		if ($epub2) {
			open( $fp, "> $outdir/toc.ncx" );
			binmode $fp, ":utf8";
			print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:$uuid"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>$name</text>
  </docTitle>
  <navMap>
EOD
			my $i = 0;
			foreach my $index ( $indexList->get_nodelist ) {
				my $title =
				  trim( $xp->findvalue( "Title/text()", $index )->value );
				$title = encode_entities( $title, '<>&"' );
				my $startPage =
				  trim( $xp->findvalue( "StartPage/text()", $index )->value ) -
				  1;
				my $file = sprintf( "%05d.xhtml", $startPage );
				++$i;
				print $fp <<"EOD";
	<navPoint id="t$startPage" playOrder="$i">
	  <navLabel>
        <text>$title</text>
      </navLabel>
      <content src="$file"/>
    </navPoint>
EOD
			}
			print $fp <<"EOD";
  </navMap>
</ncx>
EOD
		}

		# ページ設定
		my $pageContentList = $xp->find("/Content/PageContentList/PageContent");
		foreach my $pageContent ( $pageContentList->get_nodelist ) {
			my $pageNo =
			  trim( $xp->findvalue( "PageNo/text()", $pageContent )->value ) +
			  0;
			my $viewHeight = trim(
				$xp->findvalue( "ViewHeight/text()", $pageContent )->value );
			my $Dpi = trim(
				$xp->findvalue( "Resolution/text()", $pageContent )->value );
			my $qf =
			  trim( $xp->findvalue( "Quality/text()", $pageContent )->value );
			my $fmt = trim(
				$xp->findvalue( "ImageFormat/text()", $pageContent )->value );
			$pageToHeight{$pageNo}  = $viewHeight;
			$pageToDpi{$pageNo}     = $Dpi;
			$pageToQuality{$pageNo} = $qf;
			$pageToFormat{$pageNo}  = $fmt;
		}

		close($fp);
	}

	sub imageOptions {
		my ($page) = @_;
		my $scale;
		my $viewHeight = $pageToHeight{$page};
		if ( !$viewHeight ) {
			$viewHeight = $pageToDpi{$page};
			if ( !$viewHeight ) {
				$scale = "-scale-to $view_height";
			}
			else {
				$scale = "-r $viewHeight";
			}
		}
		else {
			$scale = "-scale-to $viewHeight";
		}
		my $qf;
		if ( $pageToQuality{$page} ) {
			$qf = $pageToQuality{$page};
		}
		else {
			$qf = $default_qf;
		}
		my $suffix;
		my $imageFormat;
		if ( $pageToFormat{$page} ) {
			$suffix = $pageToFormat{$page};
		}
		else {
			$suffix = $imageSuffix;
		}
		if ( $suffix eq 'png' ) {
			$imageFormat = '-png';
		}
		else {
			$imageFormat = '-jpeg';
		}
		return ( $scale, $viewHeight, $qf, $suffix, $imageFormat );
	}

	# PDFからSVGまたは画像に変換する
	{
		if ($raster) {
			my $dh;
			my ( $w, $h );
			if ( -d $pdfdir ) {
				opendir $dh, "$pdfdir";
				my @files = grep { /^\d{5}\.pdf$/ } readdir $dh;
				closedir($dh);
				foreach my $file (@files) {
					my ($num) = ( $file =~ /^(\d{5})\.pdf$/ );
					my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
					  imageOptions( $num + 0 );
					system
"$pdftoppm -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $pdfdir/$file > $outdir/$num.$suffix";
					if ($?) {
						print STDERR
"$dir: $file を画像に変換する際にエラーが発生しました。\n";
					}
				}
			}
			else {
				for ( my $i = 1 ; ; ++$i ) {
					my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
					  imageOptions($i);
					system
"$pdftoppm -f $i -l $i -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $pdfdir $outdir/";
					if ($?) {
						print STDERR
"$dir: $pdfdir を画像に変換する際にエラーが発生しました。\n";
					}
					( -f sprintf( "$outdir/%05d.$suffix", $i ) ) or last;
				}
			}
			opendir $dh, "$outdir";
			my @files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
			closedir($dh);
			( $w, $h ) = imgsize( "$outdir/" . $files[0] );
			if ( -f "$dir/cover.pdf" ) {
				my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
				  imageOptions(0);

				# カバー
				system
"$pdftoppm -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $dir/cover.pdf > $outdir/00000.$suffix";
				if ($?) {
					print STDERR
"$dir: cover.pdf を画像に変換する際にエラーが発生しました。\n";
					last;
				}
				( $w, $h ) = imgsize("$outdir/00000.$suffix");
			}
			elsif ( -f "$dir/cover.jpg" ) {
				copy "$dir/cover.jpg", "$outdir/00000.jpg";
			}
			opendir $dh, "$outdir";
			@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				my ($i) = ( $file =~ /^(\d+)\.[jp][pn]g$/ );
				wrapimage( "$outdir/$file", "$outdir/$i.svg", $w, $h,
					( $i % 2 == ( ( $ppd eq 'rtl' ) ? 0 : 1 ) ) );
			}
		}
		else {
			system "$pdftosvg $pdfdir $outdir" . ( $otf ? ' true' : '' );
			if ( !( -f "$dir/cover.pdf" ) ) {
				if ( -f "$dir/cover.jpg" ) {
					copy "$dir/cover.jpg", "$outdir/00000.jpg";
				}
				if ( -f "$outdir/00000.jpg" ) {
					my $dir;
					opendir( $dir, $outdir );
					my @files = sort grep { /^\d{5}\.svg$/ } readdir($dir);
					closedir($dir);
					my $xp =
					  XML::XPath->new( filename => "$outdir/" . $files[0] );
					my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
					my ( $width, $height ) =
					  ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );
					wrapimage( "$outdir/00000.jpg", "$outdir/00000.svg", $width,
						$height, ( $ppd eq 'rtl' ) );
				}
			}
		}

		if ($otf) {
			opendir my $dir, "$outdir/fonts";
			my @files = grep { /^.+\.svg$/ } readdir $dir;
			foreach my $file (@files) {
				if ( $file =~ /^.+\.svg$/ ) {
					system "$tootf $outdir/fonts/$file";
				}
			}
			closedir $dir;

			system "rm $outdir/fonts/*.svg";

			opendir $dir, $outdir;
			@files = grep { /^.+\.svg$/ } readdir $dir;
			foreach my $file (@files) {
				open my $in,  "< $outdir/$file";
				open my $out, "> $outdir/$file.tmp";
				foreach my $line (<$in>) {
					$line =~
s/src: url\(\"fonts\/font\-(\d+)\.svg\"\) format\(\"svg\"\);/src: url\(\"fonts\/font\-$1\.otf\"\) format\(\"opentype\"\);/s;
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

	my @files;
	{
		my $dir;
		opendir( $dir, $outdir );
		@files = sort grep { /^\d{5}\.svg$/ } readdir($dir);
		closedir($dir);
	}

	# Check SVG viewBox.
	my ( $width, $height );
	{
		my $xp = XML::XPath->new( filename => "$outdir/" . $files[0] );
		my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
		( $width, $height ) = ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );
	}

	# mimetype
	{
		open( $fp, "> $outdir/mimetype" );
		print $fp "application/epub+zip";
		close($fp);
	}

	# container.xml
	{
		my $dir = "$outdir/META-INF";
		unless ( -d $dir ) {
			mkdir( $dir, 0755 );
		}
		open( $fp, "> $dir/container.xml" );
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
		open( $fp, "> $outdir/$opf" );
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
		print $fp
"    <item id=\"nav\" href=\"nav.xhtml\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n";

		# ncx
		if ($epub2) {
			print $fp
"    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n";
		}

		our $i = 0;

		#--------------------------------------------
		#ファイルが見つかる度に呼び出される
		#--------------------------------------------
		sub wanted {
			# 通常ファイル以外は除外
			-f $_ or return;
			my $basename = substr( $File::Find::name, length($outdir) + 1 );
			$basename =~ /^size$/         and return;
			$basename =~ /^mimetype$/     and return;
			$basename =~ /^.*\.opf$/      and return;
			$basename =~ /^nav\.xhtml$/   and return;
			$basename =~ /^toc\.ncx$/     and return;
			$basename =~ /^.+\.epub$/     and return;
			$basename =~ /^META-INF\/.*$/ and return;
			$basename =~ /^.*\.svg$/      and return;

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
			elsif (/^.*\.html$/ || /^.*\.xhtml$/) {
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
		find( \&wanted, @directories_to_search );

		our @items = ();

		# コンテンツの挿入
		sub insert {
			my $j = 1;
			while ( -f sprintf( "$outdir/%05d-%05d/main.html", $i, $j ) ) {
				my $id = "t$i-$j";
				my $file = sprintf( "%05d-%05d/main.html", $i, $j );
				print $fp
"    <item id=\"$id\" href=\"$file\" media-type=\"application/xhtml+xml\"/>\n";
				push @items, [ $id, $file ];
				++$j;
			}
		}

		# 各ページ
		$i = -1;
		my $max = $files[-1];
		$max =~ s/\..+$//;
		while ( $i < $max ) {
			++$i;
			my $svgfile = sprintf( "$outdir/%05d.svg", $i );
			if ( -f sprintf( "$outdir/%05d.svg", $i ) ) {
				my $id = "t$i";
				my $file;
				if ($epub2) {
					wrapsvg($svgfile, sprintf( "$outdir/%05d.xhtml", $i ));
					unlink $svgfile;
					$file = sprintf( "%05d.xhtml", $i );
					print $fp
"    <item id=\"$id\" href=\"$file\" properties=\"svg\" media-type=\"application/xhtml+xml\"/>\n";
				}
				else {
					$file = sprintf( "%05d.svg", $i );
					print $fp
"    <item id=\"$id\" href=\"$file\" media-type=\"image/svg+xml\"/>\n";
				}
				push @items, [ $id, $file, $i ];
				insert();
			}
		}

		# EPUB2.0互換ではNCXを参照
		my $ncx = '';
		if ($epub2) {
			$ncx = ' toc="ncx"';
		}

		print $fp <<"EOD";
  </manifest>
  <spine$ncx page-progression-direction="$ppd">
EOD

		foreach my $item (@items) {
			my ( $id, $file, $i ) = @$item;
			my $props =
			  ( $i % 2 == ( ( $ppd eq 'rtl' ) ? 0 : 1 ) )
			  ? "page-spread-left"
			  : "page-spread-right";
			print $fp "    <itemref idref=\"$id\" properties=\"$props\"/>\n";
		}

		print $fp <<"EOD";
  </spine>
</package>
EOD

		close($fp);
	}

	# zip
	EpubPackage::epub_package( $outdir, $outfile );

	# check
	if ( EpubCheck::epub_check($outfile) ) {
		return 0;
	}
	return 1;
}