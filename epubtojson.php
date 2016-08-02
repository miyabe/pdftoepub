#!/usr/bin/php
<?php
require('php/util.inc.php');
require('Archive/Tar.php');

# コマンドライン
$err = FALSE;
$resolution = 1600;
for($i = 1; $i < count($argv); ++$i) {
	if ($argv[$i] == '-xml') {
		if (!isset($argv[++$i])) {
			$err = TRUE;
			break;
		}
		$xmlfile = $argv[$i];
	}
	else if ($argv[$i] == '-resolution') {
		if (!isset($argv[++$i])) {
			$err = TRUE;
			break;
		}
		$resolution = (int)$argv[$i];
	}
	else if (empty($file)) {
		$file = $argv[$i];
	}
	else if (empty($outdir)) {
		$outdir = $argv[$i];
	}
	else {
		$err = TRUE;
		break;
	}
}
if ($err || empty($file) || empty($outdir)) {
	echo "./epubtojson.php [-xml 書誌情報XML] 入力EPUBファイル 出力ディレクトリ\n";
	exit;
}

# 出力先
$imagedir = "$outdir/images/original";
@mkdir($imagedir, 0755, true);

# JSONオブジェクト作成開始
$json = array();

# コンテンツID
$content_id = basename($file);
if (preg_match('/^(.+)_eEPUB3\\.epub$/', $content_id, $matches) === 1) {
	$content_id = $matches[1];
	$json['ItemId'] = $content_id;
}
else {
	$content_id = '';
}

# XML読み込み
$xml = FALSE;
if (!empty($xmlfile)) {
	$xml = simplexml_load_file($xmlfile);
}

# OPF読み込み
$container = simplexml_load_file("zip://{$file}#META-INF/container.xml");
$container->registerXPathNamespace('cn', 'urn:oasis:names:tc:opendocument:xmlns:container');
$opf = $container->xpath("//cn:rootfile[@media-type='application/oebps-package+xml']/@full-path");
$opf = (string)$opf[0];
$base = dirname($opf);
if (empty($base) || $base == '.') {
	$base = '';
}
else {
	$base .= '/';
}

$opf = simplexml_load_file("zip://{$file}#{$opf}");
$opf->registerXPathNamespace('opf', 'http://www.idpf.org/2007/opf');
$opf->registerXPathNamespace('dc', 'http://purl.org/dc/elements/1.1/');

# ISBNがあれば取得する
$isbn = $opf->xpath("/opf:package/opf:metadata/dc:identifier[@opf:scheme='ISBN']/text()");
if (!empty($isbn)) {
	$json['ISBN'] = (string)$isbn[0];
}

# JDCNがあれば取得する
$jdcn = $opf->xpath("/opf:package/opf:metadata/dc:identifier[@opf:scheme='JDCN']/text()");
if (!empty($jdcn)) {
	$json['JDCN'] = (string)$jdcn[0];
}

# BookIDがあれば取得する
$bookid = $opf->xpath('/opf:package/@unique-identifier');
if (!empty($bookid)) {
	$bookid = (string)$bookid[0];
	$bookid = $opf->xpath("/opf:package/opf:metadata/dc:identifier[@id='$bookid']/text()");
	if (!empty($bookid[0])) {
		$json['BookID'] = (string)$bookid[0];
	}
}

# ItemName
$title = $opf->xpath("/opf:package/opf:metadata/dc:title/text()");
if (!empty($title)) {
	$json['ItemName'] = (string)$title[0];
}

# PublisherName
$authors = array();
$publisher = $opf->xpath("/opf:package/opf:metadata/dc:publisher/text()");
if (!empty($publisher)) {
	$authors[] = $json['PublisherName'] = (string)$publisher[0];
}

# Author
$creators = $opf->xpath("/opf:package/opf:metadata/dc:creator/text()");
if (!empty($creators)) {
	foreach($creators as $creator) {
		$authors[] = (string)$creator;
	}
}
if (!empty($authors)) {
	$json['Authors'] = $authors;
}

# Resolution
if ($resolution) {
	$json['Resolution'] = $resolution;
}

# manifestの解析
$cover_image = NULL;
$id_to_item = array();
$items = $opf->xpath("/opf:package/opf:manifest/opf:item");
foreach($items as $item) {
	$id = $item->xpath('@id');
	$id = (string)$id[0];
	$href = $item->xpath('@href');
	$href = (string)$href[0];
	$id_to_item[$id] = $item;
	
	$properties = $item->xpath('@properties');
	if (!empty($properties) && strpos((string)$properties[0], 'cover-image') !== FALSE) {
		$cover_image = $href;
	}
}

# spineの解析
$itemrefs = $opf->xpath("/opf:package/opf:spine/opf:itemref");
$pagelist = array();
$href_to_id = array();
foreach($itemrefs as $itemref) {
	$idref = $itemref->xpath('@idref');
	$idref = (string)$idref[0];
	$properties = $itemref->xpath('@properties');
	if (!empty($properties)) {
		$properties = (string)$properties[0];
	}
	
	# 画像抽出
	$item = $id_to_item[$idref];
	$href = $item->xpath('@href');
	$href = (string)$href[0];
	$type = $item->xpath('@media-type');
	$type = (string)$type[0];
	if ($type == 'image/jpeg' || $type == 'image/png') {
		# 画像直接参照
		$image = $href;
	}
	else if ($type == 'application/xhtml+xml') {
		# XHTML
		$xhtml = simplexml_load_file("zip://{$file}#{$base}{$href}");
		$xhtml->registerXPathNamespace('html', 'http://www.w3.org/1999/xhtml');
		$xhtml->registerXPathNamespace('svg', 'http://www.w3.org/2000/svg');
		$xhtml->registerXPathNamespace('xlink', 'http://www.w3.org/1999/xlink');
		$image = $xhtml->xpath('/html:html/html:body/html:div/svg:svg/svg:image/@xlink:href');
		if (count($image) !== 1) {
			die("HTML内の画像を抽出できませんでした");
		}
		$image = (string)$image[0];
	}
	else if ($type == 'image/svg+xml') {
		# SVG
		$svg = simplexml_load_file("zip://{$file}#{$base}{$href}");
		$svg->registerXPathNamespace('svg', 'http://www.w3.org/2000/svg');
		$svg->registerXPathNamespace('xlink', 'http://www.w3.org/1999/xlink');
		$image = $svg->xpath('/svg:svg/svg:image/@xlink:href');
		if (count($image) !== 1) {
			die("SVG内の画像を抽出できませんでした");
		}
		$image = (string)$image[0];
	}
	else {
		die("ページのMimeTypeが不正です:".$type);
	}
	$filename = basename($image);
	if (preg_match('/^([0-9]+)(\\..+)$/', $filename, $matches) === 1) {
		$i = $matches[1] + 1;
		$suffix = $matches[2];
	}
	else {
		die("画像のファイル名が不正です:".$image);
	}
	
	$id = sprintf('%04d00', $i);
	$imageid = "{$content_id}_{$id}";
	$href_to_id[$href] = $imageid;
	$imagefile = "$imagedir/{$imageid}".$suffix;
	copy("zip://{$file}#{$base}{$image}", $imagefile);
	
	if ($cover_image === NULL) {
		$cover_image = $image;
	}
	
	# PageInfo
	$info = array(
			'id' => $imageid,
	);
	
	# カラー判定
	$imagefile = realpath($imagefile);
	$out = exec("convert $imagefile -colorspace HSB -channel g -separate +channel -format %[fx:mean] info:");
	$info['color'] = $color = ($out > 0.02);
	
	# ページの左右
	if (!empty($properties)) {
		if (strpos($properties, 'page-spread-left') !== FALSE) {
			$info['page-spread'] = 'left';
		}
		else if (strpos($properties, 'page-spread-right') !== FALSE) {
			$info['page-spread'] = 'right';
		}
	}
    
	# ページのスキップ
	if ($xml) {
		$n = $i - 1;
		$pagekbn = $xml->xpath("/Content/PageContentList/PageContent[PageNo='$n']/PageKbn");
		if (!empty($pagekbn)) {
			$pagekbn = (integer) $pagekbn[0];
			if ($pagekbn == 3) {
				$info['skippable'] = TRUE;
			}
		}
	}

    # mark pages that have been worked on
    $page_list[$i] = $info;
}

# fill data for skipped pages
$pages = $xml->xpath("/Content/PageContentList/PageContent");
foreach($pages as $page) {
    $page_no = (int) $page->PageNo;
    $i = $page_no + 1;
    $id = sprintf('%04d00', $i);
    $imageid = "{$content_id}_{$id}";
    if (!array_key_exists($i, $page_list)) {
        $page_kbn = (int) $page->PageKbn;
        $info = array('id' => $imageid);
        if ($page_kbn == 3) { 
            $info['skippable'] = true;
        }
        
        // determine page spread
        if ($i > 1) {
            $prev_page_spread = $page_list[$i - 1]["page-spread"];
            if ($prev_page_spread === "left") {
                $info["page-spread"] = "right";
            }
            else {
                $info["page-spread"] = "left";
            }
        }

        $page_list[$i] = $info;
    }
    
    echo "debug: page-spread=" . $page_list[$i]["page-spread"] . "\n";

    // check for missing files
    $imagefile = "$imagedir/{$imageid}".$suffix;
    echo "debug: imagefile=$imagefile\n";
    if (!file_exists($imagefile)) {
        $pair = $i + 1;
        if ($page_list[$i]["page-spread"] === "left") {
            $pair = $i - 1;
        }
        else if(!array_key_exists($pair, $page_list)) {
            $pair = $i - 1;
        }
        $id = sprintf('%04d00', $pair);
        $imageid = "{$content_id}_{$id}";
        $pairfile = realpath("$imagedir/{$imageid}".$suffix);

        echo "convert $pairfile -threshold -1 -alpha off $imagefile\n";
        exec("convert $pairfile -threshold -1 -alpha off $imagefile");
    }
}

// sort page list array
ksort($page_list);
$pageinfo = array();
foreach($page_list as $info) {
    $pageinfo[] = $info;
}

# thumbnail.jpg
if ($cover_image !== NULL) {
	$im = new Imagick("zip://{$file}#{$base}{$cover_image}");
	$im->setCompressionQuality(80);
	$im->setImageFormat('jpeg');
	$im->thumbnailImage(480, 480, TRUE);
	$im->writeImage("$outdir/thumbnail.jpg");
}

# PageNumber
$json['PageNumber'] = count($pageinfo);

# SamplePageRange
#$max = -1;
#if ($xml) {
#	$previewpages = $xml->xpath('/Content/ContentInfo/PreviewPageList/PreviewPage');
#	if (!empty($previewpages)) {
#		foreach ($previewpages as $previewpage) {
#			$startpage = $previewpage->xpath('StartPage/text()');
#   		$endpage = $previewpage->xpath('EndPage/text()');
#			$startpage = (int)$startpage[0] + 1;
#			if (empty($endpage)) {
#				$endpage = $startpage;
#			}
#			else {
#				$endpage = (int)$endpage[0] + 1;
#			}
#			$range = $endpage - $startpage;
#			if ($max < $range) {
#				$max = $range;
#				if ($range == 1) {
#					$json['SamplePageRange'] = $startpage;
#				}
#				else {
#					$json['SamplePageRange'] = $startpage.'-'.$endpage;
#				}
#			}
#		}
#	}
#}
# UpdateDateTimeを現在時刻に設定
$json['UpdateDateTime'] = date('Y-m-d\TH:i:s');

# TOC
$items = array();
$nav = $opf->xpath("/opf:package/opf:manifest/opf:item[@properties='nav']/@href");
if (empty($nav[0])) {
	# ncxファイル(EPUB2)
	$toc = $opf->xpath("/opf:package/opf:spine/@toc");
	$toc = (string)$toc[0];
	$toc = $opf->xpath("/opf:package/opf:manifest/opf:item[@id='$toc']/@href");
	$toc = (string)$toc[0];
	$ncx = simplexml_load_file("zip://{$file}#{$base}{$toc}");
	$ncx->registerXPathNamespace('ncx', 'http://www.daisy.org/z3986/2005/ncx/');
	$toc = $ncx->xpath("//ncx:navPoint");
	foreach($toc as $item) {
		$item->registerXPathNamespace('ncx', 'http://www.daisy.org/z3986/2005/ncx/');
		$href = $item->xpath("content/@src");
		$label = $item->xpath("ncx:navLabel/ncx:text");
		$id = $href_to_id[(string)$href[0]];
		$items[] = array('label' => (string)$label[0], 'href' => $id);
	}
}
else {
	# navファイル(EPUB3)
	$nav = (string)$nav[0];
	$nav = simplexml_load_file("zip://{$file}#{$base}{$nav}");
	$nav->registerXPathNamespace('html', 'http://www.w3.org/1999/xhtml');
	$nav->registerXPathNamespace('epub', 'http://www.idpf.org/2007/ops');
	$toc = $nav->xpath("//html:*[@epub:type='toc']//html:a");
	foreach($toc as $item) {
		$href = $item->xpath('@href');
		$id = $href_to_id[(string)$href[0]];
		$items[] = array('label' => (string)$item, 'href' => $id);
	}
}

$json['TOC'] = $items;

# PageInfo
$json['PageInfo'] = $pageinfo;

# PageFlipDirection
$ppd = $opf->xpath("/opf:package/opf:spine/@page-progression-direction");
if (is_array($ppd)) {
    $ppd_string = $ppd[0]["page-progression-direction"];
}
else {
    $ppd_string = $ppd;
}
echo "debug: ppd=" . $ppd_string . "\n";
if (!empty($ppd_string)) {
	$json['PageFlipDirection'] = ($ppd_string == 'ltr') ? 'left' : 'right';
}
else {
	$json['PageFlipDirection'] = 'left';
}

# JSON出力
file_put_contents("$outdir/meta.json", json_xencode($json));

# tar出力
$tar = new Archive_Tar($outdir.'.blt');
$tar->createModify($outdir, '', dirname($outdir));
deleteDir($outdir);

function deleteDir($dirPath) {
    if (!is_dir($dirPath)) {
        throw new InvalidArgumentException("$dirPath must be a directory");
    }

    if (substr($dirPath, strlen($dirPath) - 1, 1) != '/') {
        $dirPath .= '/';
    }

    $files = glob($dirPath . '*', GLOB_MARK);
    foreach ($files as $file) {
        if (is_dir($file)) {
            deleteDir($file);
        } else {
            unlink($file);
        }
    }
    rmdir($dirPath);
}
?>
