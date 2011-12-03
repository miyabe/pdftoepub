#!/usr/bin/perl
use File::Basename;
use File::Path;
use Image::Size;

sub images {
	my $target = shift;
	print "-- $target\n";
	
	# プログラムのベースディレクトリ
	our $base = dirname(__FILE__);
	
	my $workdir = "$target/work";
	mkdir $workdir;
	my $imagesdir = "$workdir/images";
	rmtree $imagesdir;
	mkdir $imagesdir;
	
	my $contentsID = basename($target);
	
	my $pdfdir = "$target/$contentsID.pdf";
	if (-f $pdfdir) {
		my ($count) = grep {/^Pages:(.*)$/} qx/$base\/..\/poppler\/utils\/pdfinfo $pdfdir/;
		($count) = ($count =~ /^Pages:*(.*)$/);
		$count += 0;
		for (my $j = 1; $j <= $count; $j++) {
			system "$base/../poppler/utils/pdfimages -f $j -l $j $pdfdir $imagesdir/$j";
			print "page $j\n";
			for (my $i = 0;; $i++) {
				my $ppm = sprintf("$imagesdir/$j-%03d.ppm", $i);
				if (!(-f $ppm)) {
					$ppm = sprintf("$imagesdir/$j-%03d.pbm", $i);
					if (!(-f $ppm)) {
						last;
					}
				}
				my ($w, $h) = imgsize($ppm);
				print "$w x $h\n";
			}
		}
	}
	else {
		$pdfdir = "$target/magazine";
		if (!(-d $pdfdir)) {
			return;
		}
		opendir $dh, $pdfdir;
		my @files = sort grep {/^\d{5}\.pdf$/} readdir $dh;
		closedir($dh);
		unshift @files, "../cover.pdf";
		
		foreach my $file (@files) {
			my ($num) = ($file =~ /^(\d{5})\.pdf$/);
			$num = $num+0;
			print "page $num\n";
			system "$base/../poppler/utils/pdfimages $pdfdir/$file $imagesdir/$num";
			for (my $i = 0;; $i++) {
				my $ppm = sprintf("$imagesdir/$num-%03d.ppm", $i);
				if (!(-f $ppm)) {
					$ppm = sprintf("$imagesdir/$num-%03d.pbm", $i);
					if (!(-f $ppm)) {
						last;
					}
				}
				my ($w, $h) = imgsize($ppm);
				print "$w x $h\n";
			}
		}
	}
}

my $src = $ARGV[0];
if ($src =~ /^.+\/$/) {
	my $dir;
	opendir($dir, $src);
	my @files = grep { !/^\.$/ and !/^\.\.$/ and -d "$src$_"} readdir $dir;
	closedir($dir);
	foreach my $file (@files) {
		eval{
			images("$src$file");
		};
		if ($@) {
			print STDERR "$src: 処理を中断しました。エラー: $@";
		}
	}
}
else {
	images($src);
}
