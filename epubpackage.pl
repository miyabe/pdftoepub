#!/usr/bin/perl
use File::Find;
use Data::UUID;

my $outdir = $ARGV[0];

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
	my $ug = new Data::UUID;
	my $uuid = $ug->to_string($ug->create());

    open($fp, "> $outdir/content.opf");
    print $fp <<"EOD";
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookID">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:language>ja</dc:language>
    <dc:identifier id="BookID" opf:scheme="UUID">$uuid</dc:identifier>
    <dc:title>TITLE</dc:title>
    <dc:creator opf:role="aut">AUTHOR</dc:creator>
  </metadata>
  <manifest>
EOD

# マニフェスト
	#-- ディレクトリを指定(複数の指定可能) --#
	@directories_to_search = ($outdir);

	#-- 実行 --#
	find(\&wanted, @directories_to_search);

	my $i = 0;

	#--------------------------------------------
	#ファイルが見つかる度に呼び出される
	#--------------------------------------------
	sub wanted{
	# 通常ファイル以外は除外
		-f $_ or return;
		my $basename = substr($File::Find::name, length($outdir) + 1);
		$basename =~ /^mimetype$/ and return;
		$basename =~ /^content.opf$/ and return;
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
    
	$i = 1;
    while(-f "$outdir/$i.svg") {
    	print $fp "    <item id=\"t$i\" href=\"$i.svg\" media-type=\"image/svg+xml\"/>\n";
    	++$i;
    }
    
    print $fp <<"EOD";
  </manifest>
  <spine page-progression-direction="rtl">
EOD

	$i = 1;
    while(-f "$outdir/$i.svg") {
    	print $fp "    <itemref idref=\"t$i\"/>\n";
    	++$i;
    }
    
    print $fp <<"EOD";
  </spine>
  <guide>
EOD

	$i = 1;
    while(-f "$outdir/$i.svg") {
    	print $fp "    <reference type=\"text\" href=\"$i.svg\"/>\n";
    	++$i;
    }
    
    print $fp <<"EOD";
  </guide>
</package>
EOD

    close($fp);
}