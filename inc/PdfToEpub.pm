package PdfToEpub;
use File::Find;
use File::Basename;
use File::Path;
use File::Temp;
use File::Copy;
use File::Copy::Recursive;
use Data::UUID;
use Archive::Zip;
use XML::XPath;
use Date::Format;
use Image::Size;
use HTML::Entities;
use File::Spec;
use Image::Magick;

use EpubCheck;
use EpubPackage;

use Utils;

require Exporter;
@ISA = qw(Exporter);

use utf8;
use strict;

# XMLテキストのエスケープ
sub xmlescape {
	my $val = shift;
	$val = encode_entities($val, '<>&"\'');
	return $val;
}

# 画像をSVGでくるむ
# (入力ファイル, 出力ファイル, 幅, 高さ, 左ページフラグ, koboフラグ, ハイパーリンク)
sub wrapimage {
	my ( $infile, $outfile, $w, $h, $left, $kobo, @links ) = @_;
	
	# 画像のサイズを求める
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
EOD
	
	for my $link (@links) {
        my $lx = $$link[0] * $ww;
        my $ly = $$link[1] * $hh;
        my $lw = $$link[2] * $ww;
        my $lh = $$link[3] * $hh;
        my $href = xmlescape($$link[4]);
        my $id = $$link[5];
        $lx += $x;
        
        our $forceint;
        if ($forceint) {
            $lx = int($lx + .5);
            $ly = int($ly + .5);
            $lw = int($lw + .5);
            $lh = int($lh + .5);
        }
        
        our $audio;
        if ($href =~ m/.*\.mp3$/ ) {
            print $fp <<"EOD";
      <rect id="play$id" onclick='\$("#track$id")[0].play()' x="$lx" y="$ly" width="$lw" height="$lh" stroke="transparent" fill="transparent"/>
EOD
            $audio = 1;
        }
        else {
            print $fp <<"EOD";
      <a xlink:title="LINK" xlink:href="$href" target="_blank"><rect x="$lx" y="$ly" width="$lw" height="$lh" stroke="transparent" fill="transparent"/></a>
EOD
        }
	}

	print $fp <<"EOD";
</svg>
EOD
	
	close($fp);
}

# SVGをXHTMLでくるむ
# EPUB3 Fixed Layout でのみ使用
sub wrapsvg {
	my ( $infile, $outfile, $name, @links ) = @_;

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
	
	our $noInitialScale;
	my $viewport;
	if ($noInitialScale) {
		$viewport = "width=$width, height=$height";
	}
	else {
		$viewport = "width=$width, height=$height, initial-scale=1.0";
	}
	
	our $kindle;
	print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html lang="ja-JP" xml:lang="ja-JP" xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta charset="UTF-8" />
EOD
if ($kindle) {
	print $fp <<"EOD";
    <meta name="primary-writing-mode" content="horizontal-rl"/>
EOD
}
	print $fp <<"EOD";
    <meta name="viewport" content="$viewport" />
    <title>$name</title>
    <link rel="stylesheet" href="Stylesheet.css" type="text/css"/>
EOD

    my $count = @links;
    if ($count > 0) {
        print $fp <<"EOD";

    <script src="./jquery-2.1.0.min.js" type="text/javascript"></script>
    <script>
      \$(document).ready(function() {
        \$('audio').each(function() {
          \$(this).hide();
          \$(this).bind("ended", function(event) {
            this.pause();
            if (this.setCurrentTime) {
              this.setCurrentTime(0);
            } else {
              this.currentTime = 0;
            }
          })
        })
      })
    </script>
EOD
    }

    print $fp <<"EOD";
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
EOD

	for my $link (@links) {
        my $href = xmlescape($$link[4]);
        my $id = $$link[5];
           
        if ($href =~ m/.*\.mp3$/ ) {
            print STDERR "debug: audio link $href\n";
            print $fp <<"EOD";
<audio id="track$id"  src="$href"  ></audio>
EOD
        }
    }
 	print $fp <<"EOD";
  </body>
</html>
EOD
	close($fp);
	close($infp);
}

sub transcode {
	our $base     = dirname(__FILE__);
	our $pdftomapping = "$base/../pdftomapping";

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
	
	# iBooks向け
	my $ibooks      = 0;
	
	# 音声あり 
	our $audio      = 0;

	# Kindle向け
	our $kindle      = 0;
	
	# 画像直接参照
	our $imagespine = 0;
	
	# ブランクページの削除
	my $skipBlankPage = 0;
	
	# サンプルのみ変換
	my $sample = 0;
	
	# 単一PDFで最初のページだけカバーにする
	my $extractcover = 0;
	
	# 表紙を「表紙」という名前で目次の先頭に入れる
	my $coverInToc = 0;
	
	# initial-scaleを付けない
	our $noInitialScale = 0;
	
	# SVG中で使う数値を整数にする
	our $forceint = 0;
	
	our $previewPageOrigin = 1;
	
	# 変換に使うプログラム
	our $program = 'poppler';
	our %pageToProgram = ();
	
	Utils::status('EPubを生成します');
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
		elsif ( $ARGV[$i] eq '-program' ) {
			my $op = $program;
			$program = $ARGV[ ++$i ];
			if ($i < @ARGV - 1) {
				my $pages = $ARGV[ $i + 1 ];
				if ($pages =~ /^[0-9,]+$/) {
					my @list = split(/,/, $pages);
					foreach my $page(@list){
						$pageToProgram{$page} = $program;
					}
					$program = $op;
					++$i;
				}
			}
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
		elsif ( $ARGV[$i] eq '-ibooks' ) {
			$ibooks = 1;
		}
		elsif ( $ARGV[$i] eq '-kindle' ) {
			$kindle = 1;
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
		elsif ( $ARGV[$i] eq '-no-initial-scale' ) {
			$noInitialScale = 1;
		}
		elsif ( $ARGV[$i] eq '-forceint' ) {
			$forceint = 1;
		}
		elsif ( $ARGV[$i] eq '-previewPageOrigin' ) {
			if ($ARGV[ ++$i ] eq '0') {
				$previewPageOrigin = 0;
			}
		}
		elsif ( $ARGV[$i] eq '-extractcover' ) {
			$extractcover = 1;
		}
		elsif ( $ARGV[$i] eq '-cover-in-toc' ) {
			$coverInToc = 1;
		}
	}

	my $dir        = $_[0];
	my $contentsID = basename($dir);

	my $pdfdir = "$dir/$contentsID.pdf";
	if ( !( -f $pdfdir ) ) {
		$pdfdir = "$dir/magazine";
	}

	my $metafile  = "$dir/$contentsID.xml";
	my $staticdir = "$base/static";
	my $insertdir = "$dir/ins";
	my $textlinks = "$dir/textlinks.txt";
	my $appendixdir = "$dir/appendix";
	my $workdir   = "$dir/work";
	our $outdir    = "$workdir/epub";
	my $outfile   = "$workdir/$contentsID" . "_eEPUB3.epub";
	my $opf       = $contentsID . "_opf.opf";
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
			$publisher = Utils::trim( xmlescape( $publisher ) );
		}

		$publisher_kana =
		  $xp->findvalue("/Content/PublisherInfo/Kana/text()")->value;
		if ($publisher_kana) {
			$publisher_kana =
			  Utils::trim( xmlescape( $publisher_kana ) );
		}

		$name = $xp->findvalue("/Content/MagazineInfo/Name/text()")->value;
		if ($name) {
			$name = Utils::trim( xmlescape( $name ) );
		}

		$kana = $xp->findvalue("/Content/MagazineInfo/Kana/text()")->value;
		if ($kana) {
			$kana = Utils::trim( xmlescape( $kana ) );
		}

		$cover_date = $xp->findvalue("/Content/CoverDate/text()")->value;
		if ($cover_date) {
			$cover_date = Utils::trim( xmlescape( $cover_date ) );
		}

		$sales_date = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($sales_date) {
			( $sales_yyyy, $sales_mm, $sales_dd ) =
			  ( $sales_date =~ /(\d+)-(\d+)-(\d+)/ );
		}

		$introduce = $xp->findvalue("/Content/IntroduceScript/text()")->value;
		if ($introduce) {
			$introduce = Utils::trim( xmlescape( $introduce ) );
		}

		$issued = $xp->findvalue("/Content/SalesDate/text()")->value;
		if ($issued) {
			$issued = Utils::trim( xmlescape( $issued ) );
		}

		$ppd = Utils::trim(
			$xp->findvalue("/Content/ContentInfo/PageOpenWay/text()")->value ) + 0;
		$ppd = ( $ppd == 1 ) ? 'ltr' : 'rtl';

		$orientation = Utils::trim(
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

		$datatype = Utils::trim( $xp->findvalue("/Content/DataType/text()")->value );
		if ( !$datatype ) {
			$datatype = 'magazine';
		}
	
		# サンプルだけ出力
		if ($sample) {
			my $samples = $xp->find("/Content/ContentInfo/PreviewPageList/PreviewPage");
			foreach my $node ($samples->get_nodelist) {
				my ($xp2, $i, $startPage, $endPage);
				$xp2 = XML::XPath->new(context => $node);
				$startPage = Utils::trim($xp2->findvalue("StartPage/text()")->value) - $previewPageOrigin;
				$endPage = Utils::trim($xp2->findvalue("EndPage/text()")->value) - $previewPageOrigin;
				for ($i = $startPage; $i <= $endPage; ++$i) {
					$samplePages{$i} = 1;
				}
				if ($endPage > $maxSamplePage) {
					$maxSamplePage = $endPage;
				}
			}

            if ($maxSamplePage == 0) {
                print STDERR
"サンプルページがありません\n";
                return -1;
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
EOD
if ($kindle) {
	print $fp <<"EOD";
    <meta name="primary-writing-mode" content="horizontal-rl"/>
EOD
}
	print $fp <<"EOD";
    <title>$name</title>
    <link rel="stylesheet" href="tocstyle/tocstyle.css" type="text/css"/>
  </head>
  <body>
  <nav epub:type="toc" id="toc">
    <ol>
EOD

		if ($coverInToc && !$xp->exists( "/Content/ContentInfo/IndexList/Index[StartPage/text()='1']" )) {
			# 表紙を目次に入れる
			
			my $file;
			if ($imagespine) {
				$file = "00000.$imageSuffix";
			}
			elsif ($epub2) {
				$file = "00000.xhtml";
			}
			else {
				$file = "00000.svg";
			}
			print $fp <<"EOD";
		<li><a href="$file">表紙</a></li>
EOD
		}
		
		foreach my $index ( $indexList->get_nodelist ) {
			my $title = Utils::trim( $xp->findvalue( "Title/text()", $index )->value );
			$title = xmlescape( $title );
			my $startPage =
			  Utils::trim( $xp->findvalue( "StartPage/text()", $index )->value ) - 1;
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
			# EPub2目次
			
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
			if ($coverInToc && !$xp->exists( "/Content/ContentInfo/IndexList/Index[StartPage/text()='1']" )) {
				# 表紙を目次に入れる
				
				my $file;
				if ($imagespine) {
					$file = "00000.$imageSuffix";
				}
				else {
					$file = "00000.xhtml";
				}
				++$i;
				print $fp <<"EOD";
	<navPoint id="t0" playOrder="$i">
	  <navLabel>
        <text>表紙</text>
      </navLabel>
      <content src="$file"/>
    </navPoint>
EOD
			}
			foreach my $index ( $indexList->get_nodelist ) {
				my $title =
				  Utils::trim( $xp->findvalue( "Title/text()", $index )->value );
				$title = xmlescape( $title );
				my $startPage =
				  Utils::trim( $xp->findvalue( "StartPage/text()", $index )->value ) -
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
			  Utils::trim( $xp->findvalue( "PageNo/text()", $pageContent )->value ) +
			  0;
			my $pageKbn = Utils::trim(
				$xp->findvalue( "PageKbn/text()", $pageContent )->value ) + 0;
			my $viewHeight = Utils::trim(
				$xp->findvalue( "ViewHeight/text()", $pageContent )->value );
			my $Dpi = Utils::trim(
				$xp->findvalue( "Resolution/text()", $pageContent )->value );
			my $qf =
			  Utils::trim( $xp->findvalue( "Quality/text()", $pageContent )->value );
			my $fmt = Utils::trim(
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
		my %opts = {};
		my $viewHeight = $pageToHeight{$page};
		if ( !$viewHeight && !$pageToDpi{$page}) {
			$viewHeight = $view_height;
		}
		if ( !$viewHeight ) {
			$viewHeight = $pageToDpi{$page};
			$opts{r} = $viewHeight;
		}
		else {
			if ( $viewHeight == -1 ) {
				$opts{r} = $dpi;
			}
			else {
				$opts{h} = $viewHeight;
			}
		}
		if ( $pageToQuality{$page} ) {
			$opts{qf} = $pageToQuality{$page};
		}
		else {
			$opts{qf} = $default_qf;
		}
		my $suffix;
		if ( $pageToFormat{$page} ) {
			$suffix = $pageToFormat{$page};
			if ($suffix eq 'jpeg') {
				$suffix = 'jpg';
			}
		}
		else {
			$suffix = $imageSuffix;
		}
		$opts{suffix} = $suffix;
		$opts{aaVector} = $aaVector;
		return ($viewHeight, $suffix, \%opts);
	}

    sub handle_audio_links {
        our %mapping;

		my ($pdfdir, $textlinks, $single, $extractcover) = @_;

        my $count = 0;
        open(LINKS, "< $textlinks");
        binmode LINKS, ":utf8";
        while(my $line = <LINKS>) {
            chomp($line);

            my @line_data = split(/,/, $line);

            my $page = @line_data[0];
            my $needle = @line_data[1];
            my $link = @line_data[2];

            my $file = $pdfdir;
            my $file_page = $page;
            if ($single && $extractcover) {
                ++$file_page;
            }
            if (!$single) {
                $file = sprintf( "$pdfdir/%05d.pdf", $page );
                $file_page = 1;
            }
            my ($text, @bounds) = Utils::pdftotext($file, $file_page);

            my $x1 = -1;
            my $y1 = -1;
            my $x2 = 0;
            my $y2 = 0;
            my $pos = 0;
            my $ix = 0;
            my $found = 0;
            while ($ix != -1) {
                my $strlen = 0;
                if (length $text > 0) {
                    $ix = index $text, $needle, $pos;
                    $strlen = length($needle);
                    if ($ix == -1) {
                        my $needle2 = $needle;
                        $needle2 =~ s/\s//g;
                        $strlen = length($needle2);
                        $ix = index $text, $needle2, $pos;
                    }

                    if ($ix != -1) {
                        for (my $i = 0; $i < $strlen; $i ++) {
                            if ($x1 < 0 || $x1 > $bounds[$ix + $i][0]) {
                                $x1 = $bounds[$ix + $i][0];
                            }
                            if ($y1 < 0 || $y1 > $bounds[$ix + $i][1]) {
                                $y1 = $bounds[$ix + $i][1];
                            }

                            if ($x2 < $bounds[$ix + $i][0] + $bounds[$ix + $i][2]) {
                                $x2 = $bounds[$ix + $i][0] + $bounds[$ix + $i][2];
                            }
                            if ($y2 < $bounds[$ix + $i][1] + $bounds[$ix + $i][3]) {
                                $y2 = $bounds[$ix + $i][1] + $bounds[$ix + $i][3];
                            }
                         }

                         $found = 1;
                    }
                }
                else {
                    $ix = -1;
                    if ($#line_data + 1 > 3) {
                        my $w = @line_data[7];
                        my $h = @line_data[8];
                        $x1 = @line_data[3] / $w;
                        $y1 = @line_data[4] / $h;
                        $x2 = @line_data[5] / $w;
                        $y2 = @line_data[6] / $h;

                        $found = 1;
                    }
                }

                my $cx = $x2 - $x1;
                my $cy = $y2 - $y1;

                push @{$mapping{$page}}, [$x1, $y1, $cx, $cy, $link, $count];
                $pos = $ix + $strlen;
                $count ++;
            }

            if (!$found) {
                print STDERR "debug: $needle @ $page not found!\n$text\n";
            }
        }
        close(LINKS);
    }

    our %mapping = (); # リンク

	# PDFから画像に変換する
	{
	    our %mapping;

		# 画像に変換
		my $dh;
		my ( $w, $h );
		if ( -d $pdfdir ) {
			# ページ分割されたPDF
			Utils::status('ページ分割されたPDFを処理します');
			$extractcover = 0;

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
				
				Utils::status($num);
				
				# リンクの抽出
				open(CMD, "$pdftomapping $pdfdir/$file |");
				{
					while (<CMD>) {
					    if (/^PAGE: ([0-9]+)$/) {
					    	if ($1 != 1) {
					    		last;
					    	}
					    	@{$mapping{$num + 0}} = ();
					    }
					    elsif (/^LINK: ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) URI: (.+)$/) {
					    	push @{$mapping{$num + 0}}, [$1, $2, $3, $4, $5];
					    }
					}
				}
				close(CMD);
				
				my ( $viewHeight, $suffix, $opts ) = imageOptions( $num + 0 );
				my $p = $pageToProgram{$num + 0};
				if (!$p) {
					$p = $program;
				}
				Utils::pdftoimage($p, "$pdfdir/$file", "$outdir/$num.$suffix", $opts);
				if ($?) {
					print STDERR
"$dir: $file を画像に変換する際にエラーが発生しました。(1)\n";
				}
			}
			
			# 音声へのリンク
			if ( -f $textlinks ) {
                handle_audio_links($pdfdir, $textlinks, 0);
			}
			
			if (! $skipBlankPage) {
				foreach my $num ( keys( %blankPages ) ) {
					if ($sample && !$samplePages{$num}) {
						next;
					}
					my ( $viewHeight, $suffix, $opts ) = imageOptions( $num );
					if ($blankPages{$num} == 2 || -f "$outdir/$num.$suffix") {
						next;
					}
					$num = sprintf("%05d", $num);
					if (-f "$dir/BlankImage/blank.pdf") {
						# ブランクページがあれば、それを使う
						my $p = $pageToProgram{$num + 0};
						if (!$p) {
							$p = $program;
						}
						Utils::pdftoimage($p, "$dir/BlankImage/blank.pdf", "$outdir/$num.$suffix", $opts);
					}
					else {
						# 直前のページから白紙ページを生成
						my $outfile = "$outdir/$num.$suffix";
						for (my $i = $num; $i >= 0; --$i) {
							my $file = "$outdir/".sprintf("%05d", $i).'.'.$suffix;
							if ( -f $file ) {
								system "convert -colorize 100,100,100 -negate $file $outfile";
								last;
							}
						}
						if ( !( -f $outfile ) ) {
							for (my $i = $num; $i < $num + 100; ++$i) {
								my $file = "$outdir/".sprintf("%05d", $i).'.'.$suffix;
								if ( -f $file ) {
									system "convert -colorize 100,100,100 -negate $file $outfile";
									last;
								}
							}
						}
					}
				}
			}
		}
		else {
			# 単一のPDF
			
			Utils::status('ページ分割されていないPDFを処理します');
			
			# リンクの抽出
			open(CMD, "$pdftomapping $pdfdir |");
			{
				my $i = 0;
				while (<CMD>) {
				    if (/^PAGE: ([0-9]+)$/) {
				    	$i = $1;
						if ($extractcover) {
							--$i;
						}
				    	@{$mapping{$i}} = ();
				    }
				    elsif (/^LINK: ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) URI: (.+)$/) {
				    	push @{$mapping{$i}}, [$1, $2, $3, $4, $5];
				    }
				}
			}
			close(CMD);
			
			# 音声へのリンク
			if ( -f $textlinks ) {
                handle_audio_links($pdfdir, $textlinks, 1, $extractcover);
			}

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
				
				Utils::status($i);
				
				my ( $viewHeight, $suffix, $opts ) = imageOptions($i);
				my $p = $pageToProgram{$i};
				if (!$p) {
					$p = $program;
				}
				if ($blankPages{$i}) {
					my $num = sprintf("%05d", $i);
					if (-f "$dir/BlankImage/blank.pdf") {
						# ブランクページがあれば、それを使う
						Utils::pdftoimage($p, "$dir/BlankImage/blank.pdf", "$outdir/$num.$suffix", $opts);
					}
					else {
						Utils::pdftoimage($p, "$pdfdir", "$outdir/", $opts, $i);
						system "convert -colorize 100,100,100 -negate $outdir/$num.$suffix $outdir/$num.$suffix";
					}
				}
				else {
					my $page = $i;
					if ($extractcover) {
						++$page;
					}
					Utils::pdftoimage($p, "$pdfdir", "$outdir/", $opts, $page);
					if ($extractcover) {
						move sprintf( "$outdir/%05d.$suffix", $page ), sprintf( "$outdir/%05d.$suffix", $page - 1 );
					}
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
		
		# カバー
		my ( $viewHeight, $suffix, $opts ) = imageOptions(0);
		if ( -f "$dir/cover.pdf" || $extractcover ) {
			my $p = $pageToProgram{0};
			if (!$p) {
				$p = $program;
			}
			if ($extractcover) {
				Utils::pdftoimage($p, $pdfdir, "$outdir/cover", $opts, 1);
				move "$outdir/cover00001.$suffix", "$outdir/00000.$suffix";
			}
			else {
				Utils::pdftoimage($p, "$dir/cover.pdf", "$outdir/00000.$suffix", $opts);
			}
			if ($?) {
				print STDERR
"$dir: cover.pdf を画像に変換する際にエラーが発生しました。(3)\n";
				last;
			}
			( $w, $h ) = imgsize("$outdir/00000.$suffix");
			
			# リンクの抽出
			if (!$extractcover) {
				open(CMD, "$pdftomapping $dir/cover.pdf |");
				{
					while (<CMD>) {
					    if (/^PAGE: ([0-9]+)$/) {
					    	if ($1 != 1) {
					    		last;
					    	}
					    	@{$mapping{0}} = ();
					    }
					    elsif (/^LINK: ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) URI: (.+)$/) {
					    	push @{$mapping{0}}, [$1, $2, $3, $4, $5];
					    }
					}
				}
				close(CMD);
			}
		}
		elsif ( -f "$dir/cover.jpg" ) {
			my $image = Image::Magick->new;
			$image->Read("$dir/cover.jpg");
			if ($viewHeight > 0) {
				$image->Scale(geometry => $viewHeight.'x'.$viewHeight);
			}
			else {
				$image->Scale(geometry => '2068x2068');
			}
			$image->Write("$outdir/00000.jpg");
		}
		
		# 音声ファイル等のコピー
		if ( -e $appendixdir ) {
			opendir $dh, $appendixdir;
			while (my $file = readdir $dh) {
				if ( $file =~ m/^(\.|\.\.)$/g ) {
					next;
				}
				File::Copy::Recursive::rcopy "$appendixdir/$file", "$outdir/$file";
			}
			closedir($dh);
		}
		
		# 挿入するページ
		if ( -e $insertdir ) {
			my ( $viewHeight, $suffix, $opts ) = imageOptions(-1);
			opendir $dh, $insertdir;
			@files = grep { /^add_\-?[0-9]+\-[0-9]+\.pdf$/ } readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				my ($name) = ( $file =~ /^add_(.+)\.pdf$/ );
				mkdir( "$outdir/$name", 0755 );
				for (my $i = 1;; ++$i) {
					Utils::pdftoimage($program, "$insertdir/$file", "$outdir/$name/main", $opts, $i);
					( -f sprintf( "$outdir/$name/main%05d.$suffix", $i ) ) or last;
				}
				
				# リンクの抽出
				open(CMD, "$pdftomapping $insertdir/$file |");
				{
					my $i = 0;
					while (<CMD>) {
					    if (/^PAGE: ([0-9]+)$/) {
					    	$i = $1;
					    	@{$mapping{$name.$i}} = ();
					    }
					    elsif (/^LINK: ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) ([\-\.0-9]+) URI: (.+)$/) {
					    	push @{$mapping{$name.$i}}, [$1, $2, $3, $4, $5];
					    }
					}
				}
				close(CMD);
			
				if ($imagespine == 0) {
					for (my $i = 1;; ++$i) {
						my $file = sprintf( "$outdir/$name/main%05d.$suffix", $i );
						( -f $file ) or last;
						wrapimage( $file,  sprintf( "$outdir/$name/main%05d.svg", $i ), $w, $h, 0, $kobo, @{$mapping{$name.$i}} );
					}
				}
			}
		}
		
		# SVGでくるむ
		if ($imagespine == 0) {
			opendir $dh, "$outdir";
			@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				my ($i) = ( $file =~ /^(\d+)\.[jp][pn]g$/ );
				wrapimage( "$outdir/$file", "$outdir/$i.svg", $w, $h,
					( $i % 2 == ( ( $ppd eq 'rtl' ) ? 0 : 1 ) ), $kobo, @{$mapping{$i+0}} );
			}
		}

		# 挿入するコンテンツ
		if ( -e $insertdir) {
			opendir $dh, $insertdir;
			@files = sort grep { /^\-?[0-9]+\-[0-9]+$/ } readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				system "cp -r $insertdir/$file $outdir";
			}
		}
		system "cp -r $staticdir/* $outdir";
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
EOD
		print $fp <<"EOD";
         prefix="prism: http://prismstandard.org/namespaces/basic/2.1
EOD
		if (!$epub2) {
			print $fp <<"EOD";
         layout: http://xmlns.sony.net/e-book/prs/layoutoptions/
EOD
		}
		if ($epub2) {
			# EPUB3 Fixed Layout
			print $fp <<"EOD";
         rendition: http://www.idpf.org/vocab/rendition/#
EOD
		}
		if ($ibooks) {
			print $fp <<"EOD";
         ibooks: http://vocabulary.itunes.apple.com/rdf/ibooks/vocabulary-extensions-1.0/
EOD
		}
        if ($audio) {
            print $fp <<"EOD";
             access: http://www.access-company.com/2012/layout#
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
EOD
		if (!$epub2) {
			print $fp <<"EOD";
    <meta property="layout:fixed-layout">true</meta>
    <meta property="layout:orientation">$orientation</meta>
    <meta property="layout:viewport">width=$width, height=$height</meta>
EOD
		}
		print $fp <<"EOD";
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
		if ($ibooks) {
			print $fp <<"EOD";
    <meta property="ibooks:binding">false</meta>
EOD
		}
        if ($audio) {
			print $fp <<"EOD";
    <meta property='access:mediaplayer'>external</meta>
EOD
        }

		print $fp <<"EOD";
  </metadata>
  <manifest>
EOD

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
			$basename =~ /^[0-9\-]+\/main[0-9]*\.svg$/      and return;
			$basename =~ /^[0-9\-]+\/main[0-9]*\.html$/      and return;
			if ($imagespine) {
				$basename =~ /^[^\/]*\.png$/      and return;
				$basename =~ /^[^\/]*\.jpg$/      and return;
				$basename =~ /^[0-9\-]+\/main[0-9]*\.png$/      and return;
				$basename =~ /^[0-9\-]+\/main[0-9]*\.jpg$/      and return;
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
			elsif (/^.*\.mp4$/) {
				print $fp "audio/mp4";
			}
			elsif (/^.*\.mp3$/) {
				print $fp "audio/mpeg";
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
			my $l = 1;
			while (1) {
				my $exist = 0;
				for (my $k = 0;; ++$k) {
					my $name;
					my $id;
					if ($k == 0) {
						$name = sprintf( "%05d-%05d/main", $i, $j );
						$id = "t$i-$j";
					}
					else {
						$name = sprintf( "%05d-%05d/main%05d", $i, $j, $k );
						$id = "t$i-$j-$k";
					}
					my $file;
					if (-f "$outdir/$name.html") {
						$file = "$name.html";
						print $fp
		"    <item id=\"$id\" href=\"$file\" media-type=\"application/xhtml+xml\"/>\n";
					}
					elsif (-f "$outdir/$name.svg") {
						$file = "$name.svg";
						print $fp
		"    <item id=\"$id\" href=\"$file\" media-type=\"image/svg+xml\"/>\n";
					}
					elsif (-f "$outdir/$name.png") {
						$file = "$name.png";
						print $fp
		"    <item id=\"$id\" href=\"$file\" media-type=\"image/png\"/>\n";
					}
					elsif (-f "$outdir/$name.jpg") {
						$file = "$name.jpg";
						print $fp
		"    <item id=\"$id\" href=\"$file\" media-type=\"image/jpeg\"/>\n";
					}
					else {
						if ($k == 0) {
							next;
						}
						last;
					}
					$exist = 1;
					push @items, [ $id, $file, $l ];
					++$l;
				}
				if ($exist == 0) {
					last;
				}
				++$j;
			}
		}

		# 各ページ
		$i = -1;
		my $max = $files[-1];
		$max =~ s/\..+$//;
		insert();
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
			}
			else {
				my $svgfile = sprintf("$outdir/%05d.svg", $i);
				if ( -f  $svgfile ) {
					my $file;
					if ($epub2) {
						# EPUB3 Fixed Layout
						wrapsvg($svgfile, sprintf( "$outdir/%05d.xhtml", $i, $name), $name, @{$mapping{$i+0}});
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
				}
			}
			insert();
		}
		$i = 99999;
		insert();

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

sub outputCover {
    my ($dir, $destdir) = @_;

	our $base = dirname(__FILE__);
	my $contentsID = basename($dir);

	our $pdftoppm = "$base/../../poppler/utils/pdftoppm";
	my $workdir = "$dir/work";
	our $epubdir = "$workdir/epub";

	mkdir $workdir;
	mkdir $destdir;

    my $thumbnail_height = 480;
    for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
        if ( $ARGV[$i] eq '-thumbnail-height' ) {
            $thumbnail_height = $ARGV[ ++$i ] + 0;
        }
    }

    if (-f "$dir/cover.pdf") {
        system "$pdftoppm -cropbox -l 1 -scale-to $thumbnail_height -jpeg $dir/cover.pdf $workdir/cover";
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
        elsif(-d "$dir/appendix") {
            my $dh;
            opendir($dh, "$dir/appendix");
            my @files = sort grep {/^[^\.].*\.jpg$/} readdir($dh);
            closedir($dh);
            if (@files) {
                $file = "$dir/appendix/".$files[0];
            }
        }
        elsif(-d $epubdir) {
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
}


