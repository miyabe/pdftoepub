package Utils;
use File::Basename;

require Exporter;
@ISA	= qw(Exporter);

use utf8;
use strict;

# テキストのトリム
sub trim {
	my $val = shift;
	$val =~ s/^\s*(.*?)\s*$/$1/;
	return $val;
}

# 現在の状態を一時ファイルに書き出し
sub status($) {
	my $text = shift;
	my $fp;
	open( $fp, ">> /tmp/pdftoepub-$$" );
	binmode $fp, ":utf8";
	print $fp "$text\n";
	close($fp);
	print "$text\n";
}

sub deletestatus {
	unlink "/tmp/pdftoepub-$$";
}

# PDF画像変換
sub pdftoimage($$$%;$$) {
	my $program = shift;
	my $inFile = shift;
	my $outFile = shift;
	my $opts = shift;
	my $f = shift || 0;
	my $l = shift || $f;

	if ($program eq 'mupdf') {
		# muPDF
		my $options = "";
		if ($$opts{r}) {
			$options = "-r $$opts{r}";
		}
		if ($$opts{h} && $$opts{w}) {
			$options .= " -w $$opts{w} -h $$opts{h}";
		}
		elsif ($$opts{h}) {
			$options .= " -h $$opts{h}";
		}
		
		if (($$opts{aaVector} eq "no")) {
			$options = " -b0";
		}
		
		my $suffix = $$opts{suffix};
		my $mudraw = dirname(__FILE__)."/../../mupdf/build/debug/mudraw";
		
		my $ext = "";
		if ($$opts{suffix} eq "jpg") {
			$ext = ".png";
		}
		
		my $file;
		if ($f == -1) {
			$file = $outFile."%05d.".$suffix;
			system "$mudraw $options -o $file"."$ext $inFile";
		}
		elsif ($f == 0) {
			$file = $outFile;
			system "$mudraw $options -o $file"."$ext $inFile 1";
		}
		else {
			$file = $outFile."%05d.".$suffix;
			system "$mudraw $options -o $file"."$ext $inFile $f-$l";
		}
		if ($$opts{suffix} eq "jpg") {
			if (!$$opts{qf}) {
				$$opts{qf} = 98;
			}
			if ($f == 0) {
				if (-f $file.$ext) {
					system "convert $file"."$ext -quality $$opts{qf} $file";
					unlink($file.$ext);
				}
			}
			else {
				if ($f == -1) {
					$f = 1;
				}
				while(1) {
					my $src = sprintf($file.$ext, $f);
					if (! -f $src) {
						last;
					}
					my $dest = sprintf($file, $f);
					system "convert $src -quality $$opts{qf} $dest";
					unlink($src);
					++$f;
				}
			}
		}
	}
	else {
		# poppler
		my $pdftoppm = dirname(__FILE__)."/../../poppler/utils/pdftoppm";
		
		my $options;
		if ($$opts{suffix} eq "jpg") {
			$options = "-jpeg -jpegcompression q=$$opts{qf}";
		}
		else {
			$options = "-png";
		}
		if ($$opts{r}) {
			$options .= " -r $$opts{r}";
		}
		if ($$opts{h} && $$opts{w}) {
			if ($$opts{h} == $$opts{w}) {
				$options .= " -scale-to $$opts{h}";
			}
			else {
				$options .= " -scale-to-x $$opts{w} -scale-to-y $$opts{h}";
			}
		}
		elsif ($$opts{h}) {
			$options .= " -scale-to-y $$opts{h} -scale-to-x -1";
		}
		if (($$opts{aaVector} eq "no")) {
			$options .= " -aaVector $$opts{aaVector}";
		}
		else {
			$options .= " -aaVector yes";
		}
		
		if ($f == -1) {
			system "$pdftoppm -cropbox $options $inFile $outFile";
		}
		elsif ($f == 0) {
			system "$pdftoppm -cropbox $options $inFile > $outFile";
		}
		else {
			system "$pdftoppm  -f $f -l $l -cropbox $options $inFile $outFile";
		}
	}
}