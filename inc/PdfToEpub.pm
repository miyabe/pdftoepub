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
# (入力ファイル, 出力ファイル, 幅, 高さ, 左ページフラグ, koboフラグ, use_foldersフラグ, ハイパーリンク)
sub wrapimage {
	my ( $infile, $outfile, $w, $h, $left, $kobo, $use_folders, @links ) = @_;

	# 画像のサイズを求める
	my ( $ww, $hh ) = imgsize($infile);
	if ( $hh != $h ) {
		$w = int($w * $hh / $h);
		$h = $hh;
	}
	if ( $w > $ww ) {
		$h = int($h * $ww / $w);
		$w = $ww;
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
	if ($use_folders) {
		$file = "../image/$file";
	}
	my $fp;
	open( $fp, "> $outfile" );
	binmode $fp, ":utf8";

    our $use_img;
    if (!$use_img) {
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
    }
    else {
        # use img instead of svg to support access viewer
        print $fp <<"EOD";
<div>
<img width="$ww" height="$hh" style="width:100%;height:100%;" src="$file" usemap="#links_map" />
<map name="links_map">
EOD

        for my $link (@links) {
            my $lx = $$link[0] * $ww;
            my $ly = $$link[1] * $hh;
            my $lw = $$link[2] * $ww;
            my $lh = $$link[3] * $hh;
            my $href = xmlescape($$link[4]);
            my $id = $$link[5];
            $lx += $x;

            my $lx2 = $lx + $lw;
            my $ly2 = $ly + $lh;

            $lx = int($lx + .5);
            $ly = int($ly + .5);
            $lw = int($lw + .5);
            $lh = int($lh + .5);
            $lx2 = int($lx2 + .5);
            $ly2 = int($ly2 + .5);

            our $audio;
            if ($href =~ m/.*\.mp3$/ ) {
                print $fp <<"EOD";
    <area onclick='\$("#track$id")[0].play()' shape="rect" coords="$lx,$ly,$lx2,$ly2"/>
EOD
                $audio = 1;
            }
            else {
                print $fp <<"EOD";
    <area href="$href" shape="rect" coords="$lx,$ly,$lx2,$ly2"/>
EOD
            }
        }

        print $fp <<"EOD";
</map>
</div>
EOD

    }

	close($fp);
}

# SVGをXHTMLでくるむ
sub wrapsvg {
	my ( $infile, $outfile, $name, @links ) = @_;

    our $use_img;
    my $width;
    my $height;
    my $xp =
      XML::XPath->new( filename => $infile );

    if (!$use_img) {
        my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
        ( $width, $height ) =
          ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );
    }
    else {
        $width = $xp->findvalue('/div/img/@width')->value;
        $height = $xp->findvalue('/div/img/@height')->value;
    }

	my $infp;
	open( $infp, "< $infile" );
	binmode $infp, ":utf8";
	my $fp;
	open( $fp, "> $outfile" );
	binmode $fp, ":utf8";

	my $viewport;

	our $ibooks;
#	if ($ibooks) {
#		$viewport = "width=device-width";
#	}
#	else {
		$viewport = "width=$width, height=$height";
#	}

	our $noInitialScale;
	if (!$noInitialScale) {
		$viewport .= ", initial-scale=1.0";
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
	our $use_folders;
	my $css_path = $use_folders ? "../style/style.css" : "./style/style.css";
	print $fp <<"EOD";
    <meta name="viewport" content="$viewport" />
    <title>$name</title>
    <link rel="stylesheet" href="$css_path" type="text/css"/>
EOD

    # check if we have audio links
    my $has_audio_links;
    $has_audio_links = 0;
	for my $link (@links) {
        my $href = xmlescape($$link[4]);

        if ($href =~ m/.*\.mp3$/ ) {
            $has_audio_links = 1;
            last;
        }
    }

    my $count = @links;
    if ($count > 0 && $has_audio_links) {
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
EOD

    if (!$use_img) {
        print $fp <<"EOD";
    <div>
EOD
        <$infp>;
    }

	while(<$infp>) {
		print $fp $_;
	}

    if (!$use_img) {
        print $fp <<"EOD";
    </div>
EOD
    }

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
	our $view_height = 2048;

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
	our $ibooks      = 0;

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

  # use IMG instead of SVG
  our $use_img = 0;

  # 内容をitemsフォルダに分ける
	our $use_folders = 0;

	# 必ずXHTMLを使う
	our $use_xhtml = 0;

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
            print STDERR "debug: extractcover \n";
			$extractcover = 1;
		}
		elsif ( $ARGV[$i] eq '-cover-in-toc' ) {
			$coverInToc = 1;
		}
		elsif ( $ARGV[$i] eq '-use-img' ) {
			$use_img = 1;
		}
		elsif ( $ARGV[$i] eq '-use-folders' ) {
			$use_folders = 1;
			$use_xhtml = 1;
			$use_img = 1;
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
	my $textlinks = "$dir/textlinks.txt";
	my $appendixdir = "$dir/appendix";
	my $workdir = "$dir/work";
	our $outdir = "$workdir/epub";
	my $outfile = "$workdir/$contentsID" . "_eEPUB3.epub";
	my $opf = $use_folders ? "item/standard.opf" : $contentsID . "_opf.opf";
	our $itemdir = $use_folders ? "$outdir/item" : $outdir;
	our $imagedir = $use_folders ? "$itemdir/image" : $outdir;
	our $xhtmldir = $use_folders ? "$itemdir/xhtml" : $outdir;
	our $navFile = $use_folders ? "navigation-documents.xhtml" : "nav.xhtml";
	my $raster = 0;
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
	mkpath( "$imagedir", 0, 0755 );
	if ($epub2 || $use_xhtml) {
		mkpath( "$xhtmldir", 0, 0755 );
	}

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
		$orientation, $modified,       $modified_version,
        $datatype
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
        $modified_version = time2str( "%Y.%m%d.%H%M", time, "GMT" );

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
		open( $fp, "> $itemdir/$navFile" );
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
    <link rel="stylesheet" href="style/tocstyle.css" type="text/css"/>
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
				if ($use_folders) {
					$file = "image/$file";
				}
			}
			elsif ($epub2 || $use_xhtml) {
				$file = "00000.xhtml";
				if ($use_folders) {
					$file = "xhtml/$file";
				}
			}
			else {
				$file = "00000.svg";
				if ($use_folders) {
					$file = "image/$file";
				}
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
				if ($use_folders) {
					$file = "image/$file";
				}
			}
			elsif ($epub2 || $use_xhtml) {
				$file = sprintf( "%05d.xhtml", $startPage );
				if ($use_folders) {
					$file = "xhtml/$file";
				}
			}
			else {
				$file = sprintf( "%05d.svg", $startPage );
				if ($use_folders) {
					$file = "image/$file";
				}
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

			open( $fp, "> $itemdir/toc.ncx" );
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
					if ($use_folders) {
						$file = "image/$file";
					}
				}
				else {
					$file = "00000.xhtml";
					if ($use_folders) {
						$file = "xhtml/$file";
					}
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
					if ($use_folders) {
						$file = "image/$file";
					}
				}
				else {
					$file = sprintf( "%05d.xhtml", $startPage );
					if ($use_folders) {
						$file = "xhtml/$file";
					}
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
				$opts{w} = 1536;
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
        our %has_audio;

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
                if (length($needle) > 0) {
                    print STDERR "debug: needle is $needle @ $page\n";
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
                if ($link =~ m/.*\.mp3$/ ) {
                    $has_audio{$page} = 1;
                }

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
    our %has_audio = ();

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
				Utils::pdftoimage($p, "$pdfdir/$file", "$imagedir/$num.$suffix", $opts);
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
					if ($blankPages{$num} == 2 || -f "$imagedir/$num.$suffix") {
						next;
					}
					$num = sprintf("%05d", $num);
					if (-f "$dir/BlankImage/blank.pdf") {
						# ブランクページがあれば、それを使う
						my $p = $pageToProgram{$num + 0};
						if (!$p) {
							$p = $program;
						}
						Utils::pdftoimage($p, "$dir/BlankImage/blank.pdf", "$imagedir/$num.$suffix", $opts);
					}
					else {
						# 直前のページから白紙ページを生成
						my $outfile = "$imagedir/$num.$suffix";
						for (my $i = $num; $i >= 0; --$i) {
							my $file = "$imagedir/".sprintf("%05d", $i).'.'.$suffix;
							if ( -f $file ) {
								system "convert -colorize 100,100,100 -negate $file $outfile";
								last;
							}
						}
						if ( !( -f $outfile ) ) {
							for (my $i = $num; $i < $num + 100; ++$i) {
								my $file = "$imagedir/".sprintf("%05d", $i).'.'.$suffix;
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
						Utils::pdftoimage($p, "$dir/BlankImage/blank.pdf", "$imagedir/$num.$suffix", $opts);
					}
					else {
						Utils::pdftoimage($p, "$pdfdir", "$imagedir/", $opts, $i);
						system "convert -colorize 100,100,100 -negate $imagedir/$num.$suffix $imagedir/$num.$suffix";
					}
				}
				else {
					my $page = $i;
					if ($extractcover) {
						++$page;
					}
					Utils::pdftoimage($p, "$pdfdir", "$imagedir/", $opts, $page);
					if ($extractcover) {
						move sprintf( "$imagedir/%05d.$suffix", $page ), sprintf( "$imagedir/%05d.$suffix", $page - 1 );
					}
				}
				if ($?) {
					print STDERR
"$dir: $pdfdir を画像に変換する際にエラーが発生しました。(2)\n";
				}

				( -f sprintf( "$imagedir/%05d.$suffix", $i ) ) or last;
			}
		}

		opendir $dh, "$imagedir";
		my @files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
		closedir($dh);
		( $w, $h ) = imgsize( "$imagedir/" . $files[0] );

		# カバー
		my ( $viewHeight, $suffix, $opts ) = imageOptions(0);
		if ( -f "$dir/cover.pdf" || $extractcover ) {
			my $p = $pageToProgram{0};
			if (!$p) {
				$p = $program;
			}
			if ($extractcover) {
				Utils::pdftoimage($p, $pdfdir, "$imagedir/cover", $opts, 1);
				move "$imagedir/cover00001.$suffix", "$imagedir/00000.$suffix";
			}
			else {
				Utils::pdftoimage($p, "$dir/cover.pdf", "$imagedir/00000.$suffix", $opts);
			}
			if ($?) {
				print STDERR
"$dir: cover.pdf を画像に変換する際にエラーが発生しました。(3)\n";
				last;
			}
			( $w, $h ) = imgsize("$imagedir/00000.$suffix");

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
				$image->Scale(geometry => '1536x'.$viewHeight);
			}
			else {
				$image->Scale(geometry => '1536x2048');
			}
			$image->Write("$imagedir/00000.jpg");
		}

		# 音声ファイル等のコピー
		if ( -e $appendixdir ) {
			opendir $dh, $appendixdir;
			while (my $file = readdir $dh) {
				if ( $file =~ m/^(\.|\.\.)$/g ) {
					next;
				}
				File::Copy::Recursive::rcopy "$appendixdir/$file", "$itemdir/$file";
			}
			closedir($dh);
		}

		# SVGでくるむ
		if ($imagespine == 0) {
			opendir $dh, "$imagedir";
			@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dh;
			closedir($dh);
			foreach my $file (@files) {
				my ($i) = ( $file =~ /^(\d+)\.[jp][pn]g$/ );
				wrapimage( "$imagedir/$file", "$imagedir/$i.svg", $w, $h,
					( $i % 2 == ( ( $ppd eq 'rtl' ) ? 0 : 1 ) ), $kobo, $use_folders, @{$mapping{$i+0}} );
			}
		}

		system "cp -r $staticdir/* $itemdir";
	}

	my @files;
	{
		my $dir;
		opendir( $dir, $imagedir );
		if ($imagespine == 0 && !$use_img) {
			@files = sort grep { /^\d{5}\.svg$/ } readdir($dir);
		}
		else {
			@files = sort grep { /^\d{5}\.[jp][pn]g$/ } readdir $dir;
		}
		closedir($dir);
	}

	# Check SVG viewBox.
  our $use_img;
	my ( $width, $height );
	{
		if ($imagespine == 0 && !$use_img) {
			my $xp = XML::XPath->new( filename => "$imagedir/" . $files[0] );
			my $viewBox = $xp->findvalue('/svg/@viewBox')->value;
            ( $width, $height ) = ( $viewBox =~ /^0 0 (\d+) (\d+)$/ );
		} else {
			( $width, $height ) = imgsize( "$imagedir/" . $files[0] );
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
	if (!$epub2) {
			# EPUB3 Fixed Layout
			# 固定レイアウト、見開き
            my $wxh = $width . "x"  . $height;
			print $fp <<"EOD";
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">landscape</meta>
    <meta name="original-resolution" content="$wxh" />
EOD
		}
		if ($kindle) {
			print $fp <<"EOD";
	<meta name="fixed-layout" content="true" />
	<meta name="orientation-lock" content="none" />
	<meta name="book-type" content="comic" />
	<meta name="primary-writing-mode" content="horizontal-rl" />
	<meta name="RegionMagnification" content="false" />
	<meta name="cover" content="cover" />
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
"    <item id=\"nav\" href=\"$navFile\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n";

		# nav
		if ($epub2) {
			print $fp
"    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n";
		}

		our $i = 0;

		#--------------------------------------------
		#ファイルが見つかる度に呼び出される
		#--------------------------------------------
		our $itemTags = "";
		sub wanted {
			# 通常ファイル以外は除外
			-f $_ or return;
			my $basename = substr( $File::Find::name, length($itemdir) + 1 );
			$basename =~ /^size$/         and return;
			$basename =~ /^mimetype$/     and return;
			$basename =~ /^.*\.opf$/      and return;
			$basename =~ /^nav\.xhtml$/   and return;
			$basename =~ /^navigation-documents\.xhtml$/   and return;
			$basename =~ /^toc\.ncx$/     and return;
			$basename =~ /^.+\.epub$/     and return;
			$basename =~ /^META-INF\/.*$/ and return;
			$basename =~ /^[^\/]*\.svg$/      and return;
			$basename =~ /^image\/[0-9\-]+\.svg$/      and return;
			if ($imagespine) {
				$basename =~ /^[^\/]*\.png$/      and return;
				$basename =~ /^[^\/]*\.jpg$/      and return;
			}

			my $is_image = 0;
			++$i;
			my $media_type = "";
			if (/^.*\.png$/) {
				$media_type = "image/png";
				$is_image = 1;
			}
			elsif (/^.*\.gif$/) {
				$media_type = "image/gif";
				$is_image = 1;
			}
			elsif (/^.*\.jpg$/) {
				$media_type = "image/jpeg";
				$is_image = 1;
			}
			elsif (/^.*\.svg$/) {
				$media_type = "image/svg+xml";
				$is_image = 1;
			}
			elsif (/^.*\.css$/) {
				$media_type = "text/css";
			}
			elsif (/^.*\.js$/) {
				$media_type = "text/javascript";
			}
			elsif (/^.*\.html$/ || /^.*\.xhtml$/) {
				$media_type = "application/xhtml+xml";
			}
			elsif (/^.*\.otf$/) {
				$media_type = "font/otf";
			}
			elsif (/^.*\.mp4$/) {
				$media_type = "audio/mp4";
			}
			elsif (/^.*\.mp3$/) {
				$media_type = "audio/mpeg";
			}
			elsif (/^.*\.txt$/) {
				$media_type = "text/plain";
			}

			# カバーページ
			if ($is_image) {
				if ($use_folders) {
					if (!($basename =~ /^image\/00000\..+$/)) {
						if ($basename =~ /^image\/00001\..+$/) {
							if ( -f "00000.png" || -f "00000.gif" || -f "00000.jpg" || -f "00000.svg" ) {
								$is_image = 0;
							}
						}
						else {
							$is_image = 0;
						}
					}
				}
				else {
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
				}
				if ($is_image) {
					$itemTags = "    <item id=\"cover\" href=\"$basename\" media-type=\"$media_type\" properties=\"cover-image\"/>\n".$itemTags;
					return;
				}
			}
			$itemTags .= "    <item id=\"r$i\" href=\"$basename\" media-type=\"$media_type\"/>\n";
		}

		#-- ディレクトリを指定(複数の指定可能) --#
		my @directories_to_search = ($itemdir);

		#-- 実行 --#
		find( \&wanted, @directories_to_search );
		print $fp $itemTags;

		our @items = ();

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
				if (-f sprintf("$imagedir/%05d.jpg", $i)) {
					$file = sprintf( "%05d.jpg", $i );
					$mime_type = "image/jpeg";
				}
				elsif (-f sprintf("$imagedir/%05d.png", $i)) {
					$file = sprintf( "%05d.png", $i );
					$mime_type = "image/png";
				}
				else {
					next;
				}
				if ($use_folders) {
					$file = "image/$file";
				}
				print $fp
"    <item id=\"$id\" href=\"$file\" media-type=\"$mime_type\"/>\n";
				push @items, [ $id, $file, $i ];
			}
			else {
				my $svgfile = sprintf("$imagedir/%05d.svg", $i);
				if ( -f  $svgfile ) {
					my $file;
                    our $use_img;
                    our %has_audio;

					if ($epub2 || $use_xhtml) {
						wrapsvg($svgfile, sprintf( "$xhtmldir/%05d.xhtml", $i, $name), $name, @{$mapping{$i+0}});
						unlink $svgfile;
						$file = sprintf( "%05d.xhtml", $i );
						if ($use_folders) {
							$file = "xhtml/$file";
						}

            my $properties = "";

            if (!$use_img) {
                $properties .= "svg";
            }

            if ($has_audio{$i+0}) {
                if (length($properties) > 0) {
                    $properties .= " ";
                }
                $properties .= "scripted";
            }

            print $fp
"    <item id=\"$id\" href=\"$file\"";
                        if (length $properties > 0) {
                            print $fp
" properties=\"$properties\"";
                        }
                        print $fp
" media-type=\"application/xhtml+xml\"/>\n";
					}
					else {
						$file = sprintf( "%05d.svg", $i );
						if ($use_folders) {
							$file = "image/$file";
						}
						print $fp
"    <item id=\"$id\" href=\"$file\" media-type=\"image/svg+xml\"/>\n";
					}
					push @items, [ $id, $file, $i ];
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
			if ($i == 0) {
				$props = "rendition:page-spread-center";
			}
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
    print STDERR "extracting cover\n";

    my ($dir, $destdir) = @_;

	our $base = dirname(__FILE__);
	my $contentsID = basename($dir);

	our $pdftoppm = "$base/../../poppler/build/utils/pdftoppm";
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
            print STDERR "debug: cover.jpg found\n";

            $file = "$dir/cover.jpg";
        }
        elsif (-d "$dir/appendix") {
            print STDERR "debug: extracting cover from appendix\n";

            my $dh;
            opendir($dh, "$dir/appendix");
            my @files = sort grep {/^[^\.].*\.jpg$/} readdir($dh);
            closedir($dh);
            if (@files) {
                $file = "$dir/appendix/".$files[0];
            }
        }

        if (! -f $file && -d $epubdir) {
            print STDERR "debug: extracting cover from $epubdir\n";

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
        else {
            print STDERR "debug: cover not found\n";
        }
    }
}
