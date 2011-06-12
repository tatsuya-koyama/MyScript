#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use Image::Magick;
use File::Find;
use File::Path;

our $DEBUG_MODE = 1;

#my $srcDir  = "./NinjaImage/old";
my $srcDir  = "./NinjaTrueImage";
my $destDir = "./TexturePackResult";
my @dirs    = ();
my $numDir  = 0;
my $numPng  = 0;

sub putLine { print "\n", '-' x 100, "\n"; }

print "Image::Magick::VERSION = ", $Image::Magick::VERSION, "\n";


#----- 対象ディレクトリ以下にあるサブディレクトリ名を網羅して保持
&putLine();
print "target directory: $srcDir\n";
File::Find::find( \&getTargetDirName, $srcDir );
sub getTargetDirName {
	my $dirName = $File::Find::name;
	if (-d $_  &&  $dirName ne $srcDir) {
		$dirName =~ s{^${srcDir}\/}{};
		print " - $dirName\n";
		push @dirs, $dirName;
		++$numDir;
	}
	elsif (-f $_  &&  $_ =~ /\.png$/) {
		++$numPng;
	}
}
print "\nfound $numDir sub directories and $numPng png files.\n";


#----- 出力結果の置き場として、ディレクトリ構造のコピーを作成
#----- (すでに出力ディレクトリがあったら削除)
&putLine();
if (-d $destDir) {
	File::Path::rmtree( [$destDir] ) or die "$!: $destDir";
	print "removed directory: $destDir\n";
}

mkdir "$destDir";
for my $i (@dirs) {
	mkdir "$destDir/$i";
}
print "copied directory tree from [$srcDir] to [$destDir]\n";


#----- サブディレクトリごとに画像をまとめる
&putLine();
{
	my $dirCount  = 0;
	my $fileCount = 1;
	for my $i (@dirs) {
		++$dirCount;
		printf( "(%2d/%2d) ", $dirCount, scalar(@dirs) );
		&packTexturesBL( $srcDir, $destDir, $i, 512, "test", \$fileCount );
	}
}

&putLine();
print "ok. \n";
exit;


#-------------------------------------------------------------------------------
sub packTexturesBL {
	my ($srcDir, $destDir, $targetSubDir, $canvasSize, $outFileName, $rFileCount) = @_;
	
	#----- サブディレクトリ内の PNG ファイルの画像情報を取得
	my $pngs   = {};
	my @files  = glob "$srcDir/$targetSubDir/*.png";
	my $numPng = scalar( @files );
	for my $i (@files) {
		my $fileName = File::Basename::basename( $i );
		$pngs->{ $fileName } = Image::Magick->new;
		$pngs->{ $fileName }->Read( $i );
	}
	printf( "packing: (%3d png files) $srcDir/$targetSubDir\n", $numPng );
	
	
	#========== 画像を空のキャンバスにしきつめていく
	#========== (とりあえず高さ順に採番して Bottom-Left 法) (ここでは Top-Left だけど)
	my @blStables    = ( {x => 0, y => 0} ); # BL 安定点
	my @existPosList = (); # 画像の置かれた位置情報
	my @pngList      = ();
	
	#----- 背の高い画像から処理していく
	for my $i (keys %$pngs) { push @pngList, $pngs->{$i}; }
	@pngList = sort {$b->Get('height') <=> $a->Get('height')} @pngList;
	
	
	my $destImg = '';
	my $img     = '';
	while (scalar( @pngList ) > 0) {
		unless ($destImg) {$destImg = &makeBlankCanvas( $canvasSize );}
		unless ($img    ) {$img = &chooseImageBL( \@pngList, \@blStables, \@existPosList, $destImg );}
		my $pos = &choosePositionBL( \@blStables, \@existPosList, $img, $destImg );
		
		if ($pos) {
			#----- 置けた
			&putImage( $pos, \@existPosList, $img, $destImg );
			$img = '';
		} else {
			#----- もう置けない
			unless (&isThereImagesInCanvas( \@blStables )) {
				#----- どうやっても収まらないなら仕方ないのでキャンバス拡張してやり直す
				my $newCanvasSize = $destImg->Get('width') * 2;
				$destImg = &makeBlankCanvas( $newCanvasSize );
				print "extend canvas size: $newCanvasSize x $newCanvasSize\n";
			}
			else {
				#----- キャンバスを保存
				&writeImage( $destDir, $targetSubDir, $destImg, $outFileName, $$rFileCount );
				$destImg = '';
				@blStables = ( {x => 0, y => 0} );
				@existPosList = ();
				++$$rFileCount;
			}
		}
	}
	
	#----- 最後にしきつめていたキャンバスを保存
	if (&isThereImagesInCanvas( \@blStables )) {
		&writeImage( $destDir, $targetSubDir, $destImg, $outFileName, $$rFileCount );
		++$$rFileCount;
	}
}

#-------------------------------------------------------------------------------
sub makeBlankCanvas {
	my ($canvasSize) = @_;
	
	my $destImg = Image::Magick->new;
	$destImg->Set( size => "${canvasSize}x${canvasSize}" );
	$destImg->ReadImage( 'xc:none' ); # 透明なキャンバス
	
	return $destImg;
}

#-------------------------------------------------------------------------------
sub chooseImageBL {
	my ($imgList, $blStables, $existPosList, $destImg) = @_;
	
	my $size   = $destImg->Get( 'width' );
	
	for (my $i = 0;  $i < scalar(@$imgList);  $i++) {
		my $img    = @$imgList[$i];
		my $width  = $img->Get( 'width'  );
		my $height = $img->Get( 'height' );
		
		for (my $j = 0;  $j < scalar(@$blStables);  $j++) {
			my $bl = @$blStables[$j];
			
			#----- 基本的にはソート順に返すが、置けない場合は置けるやつを先に返す
			next if ($bl->{x} + $width  > $size
			     ||  $bl->{y} + $height > $size);
			next if (&isCollided(
				{
					x => $bl->{x},
					y => $bl->{y},
					w => $width,
					h => $height,
				},
				$existPosList
			));
			
			splice( @$imgList, $i, 1 );
			return $img;
		}
	}
	
	return shift @$imgList;
}

#-------------------------------------------------------------------------------
sub choosePositionBL {
	my ($blStables, $existPosList, $img, $destImg) = @_;
	
	#----- 高さ順、同じ高さなら左優先でソート
	@$blStables = sort {$a->{y} <=> $b->{y}  ||  $a->{x} <=> $b->{x}} @$blStables;
	
	my $size   = $destImg->Get( 'width' );
	my $width  = $img->Get( 'width'  );
	my $height = $img->Get( 'height' );
	
	if ($DEBUG_MODE) {
		print '-' x 10 . scalar(@$blStables) . ", w:$width, h:$height\n";
		for my $i (@$blStables) {
			print "x: $i->{x}, y: $i->{y} \n";
		}
		print "\n\n";
	}
	
	#----- BL 安定点の中から置ける場所を探す
	for (my $i = 0;  $i < scalar(@$blStables);  $i++) {
		
		my $bl = @$blStables[$i];
		next if ($bl->{x} + $width  > $size
		     ||  $bl->{y} + $height > $size);
		next if (&isCollided(
			{
				x => $bl->{x},
				y => $bl->{y},
				w => $width,
				h => $height,
			},
			$existPosList
		));
		
		#----- 置ける！
		splice( @$blStables, $i, 1 );
		
		#----- 画像を置くことによって生まれる新しい BL 安定点を追加
		push @$blStables, {x => $bl->{x} + $width, y => $bl->{y}          };
		push @$blStables, {x => $bl->{x},          y => $bl->{y} + $height};
		return $bl;
	}
	
	#----- 置けない
	return '';
}

#-------------------------------------------------------------------------------
sub isCollided {
	my ($targetRect, $existPosList) = @_;
	
	my $x = $targetRect->{x};
	my $y = $targetRect->{y};
	my $w = $targetRect->{w};
	my $h = $targetRect->{h};
	
	for my $i (@$existPosList) {
		if (($i->{x} < $x + $w)  &&  ($x < $i->{x} + $i->{w})
		&&  ($i->{y} < $y + $h)  &&  ($y < $i->{y} + $i->{h})) {
			return 1;
		}
	}
	return '';
}

our $gPutCount = 0; # for debug
#-------------------------------------------------------------------------------
sub putImage {
	my ($position, $existPosList, $srcImg, $destImg) = @_;
	
	my $x = $position->{x};
	my $y = $position->{y};
	my $width  = $srcImg->Get( 'width'  );
	my $height = $srcImg->Get( 'height' );
	
	$destImg->Composite(
		image   => $srcImg,
		compose => 'Over',
		x       => $x,
		y       => $y,
	);
	
	push @$existPosList, {
		x => $x,
		y => $y,
		w => $width,
		h => $height,
	};
	
	if ($DEBUG_MODE) {
		++$gPutCount;
		$destImg->Annotate(
			font => "/Library/Fonts/Ricty-Regular.ttf",
			pointsize => 15,
			fill => "#000000",
			#text => "[$gPutCount]($position->{x}, $position->{y})",
			text => "[$gPutCount]",
			x    => $position->{x},
			y    => $position->{y} + 15,
		);
		$destImg->Annotate(
			font => "/Library/Fonts/Ricty-Regular.ttf",
			pointsize => 12,
			fill => "#000000",
			text => $srcImg->Get('width') . "," . $srcImg->Get('height'),
			x    => $position->{x},
			y    => $position->{y} + 30,
		);
		$destImg->Draw(
			stroke    => '#990000',
			fill      => 'none',
			primitive => 'rectangle',
			points    => "$x, $y,".($x + $width).",".($y + $height),
		);
	}
}

#-------------------------------------------------------------------------------
sub writeImage {
	my ($destDir, $targetSubDir, $destImg, $fileName, $fileNo) = @_;
	
	binmode STDOUT;
	my $outFileName = sprintf( "$destDir/$targetSubDir/$fileName%03d.png", $fileNo );
	$destImg->Write( "png:$outFileName" );
}

# 作業中のキャンバスに１枚でも画像がしきつめられているか
#-------------------------------------------------------------------------------
sub isThereImagesInCanvas {
	my ($blStables) = @_;
	my $res = !( scalar(@$blStables) == 1
	             && $$blStables[0]->{x} == 0
	             && $$blStables[0]->{y} == 0 );
	return $res;
}

