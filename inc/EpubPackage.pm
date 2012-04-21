package EpubPackage;
use Archive::Zip;

require Exporter;
@ISA	= qw(Exporter);

use utf8;
use strict;

sub epub_package {
	my $dir = $_[0];
	my $file = $_[1];
	
	if (-e $file) {
		unlink $file;
	}
	my $zip = Archive::Zip->new();
	$zip->addFile("$dir/mimetype", 'mimetype');
	my ($mimetype) = $zip->members();
	$mimetype->desiredCompressionLevel(0);
	$zip->addTree($dir, '', sub { !($_ =~ /.*\/mimetype$/) and !($_ =~ /.*\/size$/) });
	$zip->writeToFileNamed($file);
}