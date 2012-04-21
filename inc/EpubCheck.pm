package EpubCheck;
use File::Basename;
use File::Temp;

require Exporter;
@ISA	= qw(Exporter);

use utf8;
use strict;

sub epub_check {
	my $file = $_[0];
	my $base = dirname(__FILE__)."/java";
	
	my $tmp = tmpnam();
	my $status = system "java -jar \"$base/epubcheck-3.0b4.jar\" $file 2> $tmp";
	
	my $fp;
	open $fp, "< $tmp";
	my $err = 0;
	while (<$fp>) {
		print STDERR $_;
		if (!$err && $_) {
			$err = 1;
		}
	}
	close $fp;
	if ($status) {
		print STDERR "$file: EPUBチェッカの実行時にエラーがありました。\n";
		$err = 1;
	}
	unlink $tmp;
	return $err;
}