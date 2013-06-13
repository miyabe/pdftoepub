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
use File::Spec;

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
	my ( $infile, $outfile, $w, $h, $left, $kobo ) = @_;
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
		$x = $w - $ww;
		if (! $kobo) {
			$x = $x + 1;
		}
	}
	else {
		$x = 0;
		if (! $kobo) {
			$x = $x - 1;
		}
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
# EPUB3 Fixed Layout でのみ使用
sub wrapsvg {
	my ( $infile, $outfile, $name ) = @_;
	
	my $xp =
	  XML::XPath->new( filename => $infile );
	my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
	my ( $width, $height ) =
	  ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );

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
    <meta name="viewport" content="width=$width, height=$height, initial-scale=1.0" />
    <title>$name</title>
    <link rel="stylesheet" href="Stylesheet.css" type="text/css"/>
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
	# 解像度
	our $dpi = 188;

	# 画質
	our $default_qf  = 98;
	# 文字以外のアンチエイリアス
	our $aaVector    = 'yes';
	# 画像タイプ
	our $imageSuffix = 'jpg';
	# EPUB2互換
	my $epub2      = 0;
	# Kobo向け
	my $kobo      = 0;
	# 画像直接参照
	our $imagespine = 0;
	# ブランクページの削除
	my $skipBlankPage = 0;
	# サンプルのみ変換
	my $sample = 0;
	
	for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
		if ( $ARGV[$i] eq '-view-height' ) {
			$view_height = $ARGV[ ++$i ] + 0;
		}
		elsif ( $ARGV[$i] eq '-dpi' ) {
			$dpi = $ARGV[ ++$i ];
			$view_height = -1;
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
		elsif ( $ARGV[$i] eq '-kobo' ) {
			$kobo = 1;
		}
		elsif ( $ARGV[$i] eq '-imagespine' ) {
			$imagespine = 1;
		}
		elsif ( $ARGV[$i] eq '-skipBlankPage' ) {
			$skipBlankPage = 1;
		}
		elsif ( $ARGV[$i] eq '-sample' ) {
			$sample = 1;
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
	my %samplePages = ();
	my $maxSamplePage = 0;

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
	my %blankPages = ();
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
			$xp->findvalue("/Content/ContentInfo/PageOpenWay/text()")->value ) + 0;
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
	
		# サンプルだけ出力
		if ($sample) {
			my $samples = $xp->find("/Content/ContentInfo/PreviewPageList/PreviewPage");
			foreach my $node ($samples->get_nodelist) {
				my ($xp2, $i, $startPage, $endPage);
				$xp2 = XML::XPath->new(context => $node);
				$startPage = trim($xp2->findvalue("StartPage/text()")->value);
				$endPage = trim($xp2->findvalue("EndPage/text()")->value);
				for ($i = $startPage; $i <= $endPage; ++$i) {
					$samplePages{$i} = 1;
				}
				if ($endPage > $maxSamplePage) {
					$maxSamplePage = $endPage;
				}
			}
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
			if ($sample && !$samplePages{$startPage}) {
				next;
			}
			my $file;
			if ($imagespine) {
				$file = sprintf( "%05d.$imageSuffix", $startPage );
			}
			elsif ($epub2) {
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
				if ($sample && !$samplePages{$startPage}) {
					next;
				}
				my $file;
				if ($imagespine) {
					$file = sprintf( "%05d.$imageSuffix", $startPage );
				}
				else {
					$file = sprintf( "%05d.xhtml", $startPage );
				}
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
			my $pageKbn = trim(
				$xp->findvalue( "PageKbn/text()", $pageContent )->value ) + 0;
			my $viewHeight = trim(
				$xp->findvalue( "ViewHeight/text()", $pageContent )->value );
			my $Dpi = trim(
				$xp->findvalue( "Resolution/text()", $pageContent )->value );
			my $qf =
			  trim( $xp->findvalue( "Quality/text()", $pageContent )->value );
			my $fmt = trim(
				$xp->findvalue( "ImageFormat/text()", $pageContent )->value );
			if ($pageKbn == 3) {
				$blankPages{$pageNo} = 1;
			}
			elsif ($pageKbn == 99) {
				$blankPages{$pageNo} = 2;
			}
			$pageToHeight{$pageNo} = $viewHeight;
			$pageToDpi{$pageNo} = $Dpi;
			$pageToQuality{$pageNo} = $qf;
			$pageToFormat{$pageNo} = $fmt;
		}

		close($fp);
	}

	sub imageOptions {
		my ($page) = @_;
		my $scale;
		my $viewHeight = $pageToHeight{$page};
		if ( !$viewHeight && !$pageToDpi{$page}) {
			$viewHeight = $view_height;
		}
		if ( !$viewHeight ) {
			$viewHeight = $pageToDpi{$page};
			$scale = "-r $viewHeight";
		}
		else {
			if ( $viewHeight == -1 ) {
				$scale = "-r $dpi";
			}
			else {
				$scale = "-scale-to-y $viewHeight -scale-to-x -1";
			}
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
			$suffix = 'jpg';
			$imageFormat = '-jpeg';
		}
		return ( $scale, $viewHeight, $qf, $suffix, $imageFormat );
	}

	# PDFからSVGまたは画像に変換する
	{
		if ($raster) {
			# 画像に変換
			my $dh;
			my ( $w, $h );
			if ( -d $pdfdir ) {
				# ページ分割されたPDF
				opendir $dh, "$pdfdir";
				my @files = grep { /^\d{5}\.pdf$/ } readdir $dh;
				closedir($dh);
				foreach my $file (@files) {
					my ($num) = ( $file =~ /^(\d{5})\.pdf$/ );
					# ブランクページは飛ばす
					if ($skipBlankPage && $blankPages{$num + 0}) {
						next;
					}
					if ($blankPages{$num + 0} == 2) {
						next;
					}
					
					# サンプルページだけ出力する場合
					if ($sample && !$samplePages{$num + 0}) {
						next;
					}
					
					my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
					  imageOptions( $num + 0 );
					system
"$pdftoppm -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $pdfdir/$file > $outdir/$num.$suffix";
					if ($?) {
						print STDERR
"$dir: $file を画像に変換する際にエラーが発生しました。(1)\n";
					}
				}
				if (! $skipBlankPage && -f "$dir/BlankImage/blank.pdf") {
					# ブランクページがあれば、それを使う
					foreach my $num ( keys( %blankPages ) ) {
						my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
						  imageOptions( $num );
						if ($blankPages{$num} == 2 || -f "$outdir/$num.$suffix") {
							next;
						}
						$num = sprintf("%05d", $num);
						system
"$pdftoppm -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $dir/BlankImage/blank.pdf > $outdir/$num.$suffix";
					}
				}
			}
			else {
				# 単一のPDF
				for ( my $i = 1 ; ; ++$i ) {
					# ブランクページは飛ばす
					if ($skipBlankPage && $blankPages{$i}) {
						next;
					}
					if ($blankPages{$i} == 2) {
						next;
					}
					
					# サンプルページだけ出力する場合
					if ($sample && !$samplePages{$i}) {
						if ($i >= $maxSamplePage) {
							last;
						}
						next;
					}
					
					my ( $scale, $viewHeight, $qf, $suffix, $imageFormat ) =
					  imageOptions($i);
					if ($blankPages{$i} && -f "$dir/BlankImage/blank.pdf") {
						# ブランクページがあれば、それを使う
						my $num = sprintf("%05d", $i);
						system
"$pdftoppm -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $dir/BlankImage/blank.pdf > $outdir/$num.$suffix";
					}
					else {
						system
"$pdftoppm -f $i -l $i -cropbox $imageFormat -jpegcompression q=$qf -aaVector $aaVector $scale $pdfdir $outdir/";
					}
					if ($?) {
						print STDERR
"$dir: $pdfdir を画像に変換する際にエラーが発生しました。(2)\n";
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
"$dir: cover.pdf を画像に変換する際にエラーが発生しました。(3)\n";
					last;
				}
				( $w, $h ) = imgsize("$outdir/00000.$suffix");
			}
			elsif ( -f "$dir/cover.jpg" ) {
				copy "$dir/cover.jpg", "$outdir/00000.jpg";
			}
			if ($imagespine == 0) {
				# SVGでくるむ
				opendir $dh, "$outdir";
				@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
				closedir($dh);
				foreach my $file (@files) {
					my ($i) = ( $file =~ /^(\d+)\.[jp][pn]g$/ );
					wrapimage( "$outdir/$file", "$outdir/$i.svg", $w, $h,
						( $i % 2 == ( ( $ppd eq 'rtl' ) ? 0 : 1 ) ), $kobo );
				}
			}
		}
		else {
			# SVGに変換
			system "$pdftosvg $pdfdir $outdir" . ( $otf ? ' true' : '' );
			
			# ブランクページを消す
			foreach my $i (keys(%blankPages)) {
				unlink sprintf( "$outdir/%05d.svg", $i);
			}
			
			if ( !( -f "$dir/cover.pdf" ) ) {
				if ( -f "$dir/cover.jpg" ) {
					copy "$dir/cover.jpg", "$outdir/00000.jpg";
				}
				if ( -f "$outdir/00000.jpg" && $imagespine == 0) {
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
						$height, ( $ppd eq 'rtl' ), $kobo );
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
		if ($imagespine == 0) {
			@files = sort grep { /^\d{5}\.svg$/ } readdir($dir);
		}
		else {
			@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dir;
		}
		closedir($dir);
	}

	# Check SVG viewBox.
	my ( $width, $height );
	{
		if ($imagespine == 0) {
			my $xp = XML::XPath->new( filename => "$outdir/" . $files[0] );
			my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
			( $width, $height ) = ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );
		} else {
			( $width, $height ) = imgsize( "$outdir/" . $files[0] );
		}
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
		my $title_file_as;
		if ($datatype eq 'magazine') {
			$title_file_as = "$kana $sales_date";
		}
		else {
			$title_file_as = $kana;
		}
		
		open( $fp, "> $outdir/$opf" );
		binmode $fp, ":utf8";
		print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf"
         prefix="layout: http://xmlns.sony.net/e-book/prs/layoutoptions/
         prism: http://prismstandard.org/namespaces/basic/2.1
EOD
		if ($epub2) {
			# EPUB3 Fixed Layout
			print $fp <<"EOD";
         rendition: http://www.idpf.org/vocab/rendition/#
EOD
		}
		print $fp <<"EOD";
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
    <meta refines="#title" property="file-as">$title_file_as</meta>
    <meta refines="#publisher" property="file-as">$publisher_kana</meta>
    <meta refines="#publication" property="file-as">$kana</meta>
    <meta property="prism:volume">$sales_yyyy</meta>
    <meta property="prism:number">${sales_mm}${sales_dd}</meta>
    <meta property="layout:fixed-layout">true</meta>
    <meta property="layout:orientation">$orientation</meta>
    <meta property="layout:viewport">width=$width, height=$height</meta>
    <meta property="prs:datatype">$datatype</meta>
EOD
		if ($epub2) {
			# EPUB3 Fixed Layout
			# 固定レイアウト、向き自動、見開き自動
			print $fp <<"EOD";
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:orientation">$orientation</meta>
    <meta property="rendition:spread">auto</meta>
EOD
		}
		print $fp <<"EOD";
  </metadata>
  <manifest>
EOD

		# <meta property="layout:overflow-scroll">true</meta>

		# マニフェスト

		# nav
		print $fp
"    <item id=\"nav\" href=\"nav.xhtml\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n";

		# nav
		if ($epub2) {
			# EPUB3 Fixed Layout
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
			$basename =~ /^[^\/]*\.svg$/      and return;
			if ($imagespine) {
				$basename =~ /^[^\/]*\.png$/      and return;
				$basename =~ /^[^\/]*\.jpg$/      and return;
			}
			
			my $is_image = 0;
			++$i;
			print $fp "    <item id=\"r$i\" href=\"$basename\" media-type=\"";
			if (/^.*\.png$/) {
				print $fp "image/png";
				$is_image = 1;
			}
			elsif (/^.*\.gif$/) {
				print $fp "image/gif";
				$is_image = 1;
			}
			elsif (/^.*\.jpg$/) {
				print $fp "image/jpeg";
				$is_image = 1;
			}
			elsif (/^.*\.svg$/) {
				print $fp "image/svg+xml";
				$is_image = 1;
			}
			elsif (/^.*\.css$/) {
				print $fp "text/css";
			}
			elsif (/^.*\.js$/) {
				print $fp "text/javascript";
			}
			elsif (/^.*\.html$/ || /^.*\.xhtml$/) {
				print $fp "application/xhtml+xml";
			}
			elsif (/^.*\.otf$/) {
				print $fp "font/otf";
			}
			print $fp "\"";
			# カバーページ
			if ($is_image) {
				if (!($basename =~ /^00000\..+$/)) {
					if ($basename =~ /^00001\..+$/) {
						if ( -f "00000.png" || -f "00000.gif" || -f "00000.jpg" || -f "00000.svg" ) {
							$is_image = 0;
						}
					}
					else {
						$is_image = 0;
					}
				}
				if ($is_image) {
					print $fp " properties=\"cover-image\"";
				}
			}
			print $fp "/>\n";
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
			my $id = "t$i";
			if ($imagespine) {
				my $file;
				my $mime_type;
				if (-f sprintf("$outdir/%05d.jpg", $i)) {
					$file = sprintf( "%05d.jpg", $i );
					$mime_type = "image/jpeg";
				}
				elsif (-f sprintf("$outdir/%05d.png", $i)) {
					$file = sprintf( "%05d.png", $i );
					$mime_type = "image/png";
				}
				else {
					next;
				}
				print $fp
"    <item id=\"$id\" href=\"$file\" media-type=\"$mime_type\"/>\n";
				push @items, [ $id, $file, $i ];
				insert();
			}
			else {
				my $svgfile = sprintf("$outdir/%05d.svg", $i);
				if ( -f  $svgfile ) {
					my $file;
					if ($epub2) {
						# EPUB3 Fixed Layout
						wrapsvg($svgfile, sprintf( "$outdir/%05d.xhtml", $i, $name));
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
