<?php
/**
 * PHP5.4からでないと対応していないUnicodeアンエスケープをPHP5.3でもできるようにしたラッパー関数
 * @param mixed   $value
 * @param int     $options
 * @param boolean $unescapee_unicode
 */
function json_xencode($value, $options = 0, $unescapee_unicode = true)
{
	$v = json_encode($value, $options);
	if ($unescapee_unicode) {
		$v = unicode_encode($v);
		// スラッシュのエスケープをアンエスケープする
		$v = preg_replace('/\\\\\//', '/', $v);
	}
	return $v;
}

/**
 * Unicodeエスケープされた文字列をUTF-8文字列に戻す。
 * 参考:http://d.hatena.ne.jp/iizukaw/20090422
 * @param unknown_type $str
 */
function unicode_encode($str)
{
	return preg_replace_callback("/\\\\u([0-9a-zA-Z]{4})/", "encode_callback", $str);
}

function encode_callback($matches) {
	return mb_convert_encoding(pack("H*", $matches[1]), "UTF-8", "UTF-16");
}
?>