#!/usr/bin/php
<?php
require('php/util.inc.php');

# コマンドライン
if (count($argv) !== 3) {
	echo "./epubtojson.php [入力EPUBファイル] [出力ディレクトリ]
";
	exit;
}
$file = $argv[1];
$outdir = $argv[2];

# 出力先
$imagedir = "$outdir/images/original";
@mkdir($imagedir, 0755, true);

# JSONオブジェクト作成開始
$json = array();

# コンテンツID
$content_id = basename($file);
if (preg_match('/^(.+)_eEPUB3\\.epub$/', $content_id, &$matches) === 1) {
	$content_id = $matches[1];
	$json['ItemId'] = $content_id;
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
if (!empty($isbn[0])) {
	$json['ISBN'] = (string)$isbn[0];
}

# JDCNがあれば取得する
$jdcn = $opf->xpath("/opf:package/opf:metadata/dc:identifier[@opf:scheme='JDCN']/text()");
if (!empty($jdcn[0])) {
	$json['JDCN'] = (string)$jdcn[0];
}

# BookIDがあれば取得する
$bookid = $opf->xpath('/opf:package/@unique-identifier');
if (!empty($bookid[0])) {
	$bookid = (string)$bookid[0];
	$bookid = $opf->xpath("/opf:package/opf:metadata/dc:identifier[@id='$bookid']/text()");
	if (!empty($bookid[0])) {
		$json['BookID'] = (string)$bookid[0];
	}
}

# ItemName
$title = $opf->xpath("/opf:package/opf:metadata/dc:title/text()");
if (!empty($title[0])) {
	$json['ItemName'] = (string)$title[0];
}

# PublisherName
$publisher = $opf->xpath("/opf:package/opf:metadata/dc:publisher/text()");
if (!empty($publisher[0])) {
	$json['PublisherName'] = (string)$publisher[0];
}

# Author
$creators = $opf->xpath("/opf:package/opf:metadata/dc:creator/text()");
if (!empty($creators)) {
	$authors = array();
	foreach($creators as $creator) {
		$authors[] = (string)$creator;
	}
	$json['Authors'] = $authors;
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
$pageinfo = array();
$href_to_id = array();
$i = 0;
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
	if (preg_match('/^.+(\\..+)$/', $image, &$matches) === 1) {
		$suffix = $matches[1];
	}
	else {
		die("画像のファイル名が不正です:".$image);
	}
	++$i;
	$id = sprintf('%04d00', $i);
	$href_to_id[$href] = $id;
	$imagefile = "$imagedir/$id".$suffix;
	copy("zip://{$file}#{$base}{$image}", $imagefile);
	
	if ($cover_image === NULL) {
		$cover_image = $image;
	}
	
	#TODO spread
	$info = array(
			'id' => $id
	);
	
	$imagefile = realpath($imagefile);
	$out = exec("convert $imagefile -colorspace HSB -channel g -separate +channel -format %[fx:mean] info:");
	$info['color'] = $color = ($out > 0.02);
	
	if (!empty($properties)) {
		if (strpos($properties, 'page-spread-left') !== FALSE) {
			$info['page-spread'] = 'left';
		}
		else if (strpos($properties, 'page-spread-right') !== FALSE) {
			$info['page-spread'] = 'right';
		}
	}
	
	$pageinfo[] = $info;
}

#TODO thumbnail.jpg
if ($cover_image !== NULL) {
	$im = new Imagick("zip://{$file}#{$base}{$cover_image}");
	$im->setCompressionQuality(80);
	$im->setImageFormat('jpeg');
	$im->thumbnailImage(300, 300, TRUE);
	$im->writeImage("$outdir/thumbnail.jpg");
}

# PageNumer
$json['PageNumer'] = count($pageinfo);

#TODO SamplePageRange

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
if (!empty($ppd)) {
	$json['PageFlipDirection'] = ($ppd == 'ltr') ? 'right' : 'left';
}

file_put_contents("$outdir/meta.json", json_xencode($json));
?>