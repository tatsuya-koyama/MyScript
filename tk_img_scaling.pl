#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use Image::Magick;

if (@ARGV < 3) {
	print 'USAGE: perl ./tk_img_scaling.pl PATH            GEOMETORY  QUALITY', "\n";
	print '  ex.: perl ./tk_img_scaling.pl "images/*.png"  "256x256"  75', "\n";
	die;
}

print "Image::Magick::VERSION = ", $Image::Magick::VERSION, "\n";

my @files = glob $ARGV[0];
my $numFile = @files;

my $dirName = dirname( $ARGV[0] );
if (!-d "$dirName/newImage"){
	mkdir "$dirName/newImage";
}



my ($im, $status);
#----- instanciate
$im = Image::Magick->new;


my $count = 0;
for my $filePath (@files) {
	my $fileName = basename( $filePath );
	
	#----- instanciate
	$im = Image::Magick->new;
	
	++$count;
	printf( "(%3d %%) $dirName ::: $fileName\n", ($count / $numFile * 100) );
	
	#----- read image file
	$status = $im->Read( $filePath );
	warn( $status ) if( $status );
	
	#----- resize
	# 縦横比維持する
	$im->Scale( $ARGV[1] ); #----- ex. '256x256'
	
	#----- output image file
	$im->Set( quality => $ARGV[2] );
	$status = $im->Write( "$dirName/newImage/$fileName" );
	warn( $status ) if( $status );
	
	#----- destruct
	undef $im;
}

print "--- complete.\n";


