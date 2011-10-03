■ ビルド方法
# Debian squeeze でビルド・動作を確認しています

# 以下のコマンドでGitによりpixman, cairo, poppler, pdftoepubのソースを取得します。pixmanには手を加えていませんが、cairoをビルドするために必要です。

git clone git://anongit.freedesktop.org/git/pixman.git
git clone git://github.com/miyabe/cairo.git
git clone git://github.com/miyabe/poppler.git
git clone git://github.com/miyabe/pdftoepub.git

# ビルドの準備のために、以下の環境変数を設定しておきます。

export PIXMAN_DIR=[PIXMANのディレクトリのパス]
export CAIRO_DIR=[CAIROのディレクトリのパス]
export POPPLER_DIR=[POPPLERのディレクトリのパス]
export PDFTOEPUB_DIR=[PDFTOEPUBのディレクトリのパス]

# 例えばfooディレクトリにpixman, cairo, popplerを落とした場合は、fooディレクトリ内で以下を実行します。

export PIXMAN_DIR=`pwd`/pixman
export CAIRO_DIR=`pwd`/cairo
export POPPLER_DIR=`pwd`/poppler
export PDFTOEPUB_DIR=`pwd`/pdftoepub

# pkg-configのための環境変数を設定。

export PKG_CONFIG_PATH=$PIXMAN_DIR:$CAIRO_DIR:$POPPLER_DIR
export PKG_CONFIG_TOP_BUILD_DIR=
pkg-config --cflags cairo poppler-glib

# 実行時のライブラリパスを設定。
export LD_LIBRARY_PATH=$CAIRO_DIR/src/.libs:$PIXMAN_DIR/pixman/.libs:$POPPLER_DIR/glib/.libs

# pixmanをビルド
cd $PIXMAN_DIR
./autogen.sh
./configure
make

# cairoをビルド
cd $CAIRO_DIR
./autogen.sh
make clean
./configure pixman_CFLAGS="-I$PIXMAN_DIR/pixman/" pixman_LIBS="-L$PIXMAN_DIR/pixman/.libs/ -lpixman-1"
make

# popplerをビルド
# libfreetype6-dev, libglib2.0-dev, poppler-data, pango-graphiteパッケージを入れておく必要があります。
cd $POPPLER_DIR
./autogen.sh
make clean
./configure CAIRO_VERSION="1.9.14" CAIRO_CFLAGS="-I$CAIRO_DIR/ -I$CAIRO_DIR/src/ -I/usr/include/freetype2" CAIRO_LIBS="-L$CAIRO_DIR/src/.libs/ -lcairo" POPPLER_GLIB_CFLAGS="-I/usr/include/glib-2.0 -I/usr/lib/glib-2.0/include -I$CAIRO_DIR/ -I$CAIRO_DIR/src/" POPPLER_GLIB_LIBS="-lglib-2.0" --datarootdir=/usr/share
make

# pdftoepubをビルド
cd $PDFTOEPUB_DIR
make

■ ツールの説明
・pdftosvg PDF 出力先ディレクトリ [SVGフォント出力(true|false)]
PDFをSVGファイルに変換します。SVGファイルは１ページ目から順に 1.svg, 2.svg, 3.svg ... という名前で生成されます。通常はフォントは各SVGファイルの中に含まれますが、３番目の引数にtrueを設定すると、出力先ディレクトリにfontsディレクトリを作成し、その中に複数のSVGフォントが font-0.svg, font-1.svg, font-2.svg ... という名前で生成され、各ページのSVGから参照されます。

・tootf.pe SVGファイル
SVGファイルをOTFファイルに変換するFontForgeスクリプトです。実行するためにはFontForgeが必要です。

・pdftepub.pl PDF XMLメタデータ 挿し込むデータディレクトリ
PDFからEPUBを生成するPerlスクリプトです。pdftosvgによるSVGへの変換、tootf.peによるSVGフォントからOTFへの変換を行い、EPUBファイルを生成します。生成されるEPUBファイルは、PDFの拡張子を.epubに置き換えたものになります。

EPUBに挿し込むデータは挿し込みデータディレクトリにEPUB内と同じディレクトリ構成で配置します。EPUBに挿し込むページは ページ番号-通し番号/main.html という名前で配置しておきます。例えば 3-1/main.html, 3-2/main.html, 3-3/main.html ... という名前で配置すると、それぞれのコンテンツが順に3ページと4ページの間に挿入されます。1ページの前に挿入する場合は 0-1/main.html のようにします。

■ cairoの修正内容
以下のファイルを修正しています。
・cairo-svg-surface.c
・cairo-svg.h
・cairo-svg-surface-private.h

Webkitで画像の表示がおかしくなる問題を回避するため、画像を表示する場合、useのtransformで拡大縮小し、patternのx, yで平行移動するようにした。

出力されるSVGのビューポートは設定通りで、幅と高さは常に100%とした。

<font-face>への対応、外部にフォントファイルを出力できるようにソースの各所を修正した。

show_text_glyphの呼び出しに対応した。
show_text_glyphだけを呼び出した場合は<font-face>、show_glyphだけを呼び出した場合は<symbol>によりテキストを出力する。

path, transform, 色, グリフのパスをそれぞれ別の精度で出力できるようにした（ソース中の#defineで設定）。

stroke-dasharray の要素に 0 を出力するとchromeで点線が消えてしまうので、最小値を0.2に強制。

・ 次の関数が加えられています

/*
画像をファイルに書きだす関数を設定します。
cairo_svg_surface_tに対してこれを呼び出しておくと、画像をSVG内に埋め込まずに、
write_image_funcにより外部ファイルに出力することができます。

@surface: 画像 #cairo_surface_t
@write_image_func: 画像をファイルに書きだす関数へのポインタ #cairo_write_image_func_t
@write_image_closure: ユーザーのデータ
*/
cairo_public void
cairo_svg_surface_set_write_image_func (cairo_surface_t *surface,
  cairo_write_image_func_t write_image_func,
  void *write_image_closure);


/*
ユーザーが定義してcairo_svg_surface_set_write_image_funcに渡すための、
画像をファイルに書きだすための関数です。
書きだしたファイル名を(通常はsprintfで)filenameに出力します。

@closure: ユーザーのデータ
@surface: 画像 #cairo_surface_t
@filename: 出力先のファイル名
*/
typedef cairo_status_t (*cairo_write_image_func_t) (void *closure,
  cairo_surface_t *surface,
  char *filename);

/*
フォントファイルを別ファイルとして出力するためのcairo_svg_surface_tを作成します。
共通のフォントファイルを持つSVGを出力するために、同じcairo_svg_fontfile_tに対して何度も呼ぶことができます。

@filename: SVGファイル名
@width: 幅
@height: 高さ
@fontfile: フォントファイル #cairo_svg_fontfile_t
*/
cairo_surface_t *
cairo_svg_surface_create_with_fontfile (const char	*filename,
			  double	 width,
			  double	 height,
			  cairo_svg_fontfile_t *fontfile);

/*
cairo_svg_surface_create_with_fontfileで使用するためのフォントファイル(cairo_svg_fontfile_t)を作成します。

@filename: フォントファイル名
*/
cairo_svg_fontfile_t *
cairo_svg_fontfile_create (const char   *filename);

/*
フォントデータをファイルに出力した後、破棄します。

@fontfile: フォントファイル #cairo_svg_fontfile_t
*/
void
cairo_svg_fontfile_finish (cairo_svg_fontfile_t   *fontfile);

■ popplerの修正内容
・CairoOutputDev.css
cairoが対応している場合は、常にshow_text_glyphを呼び出すようにした。

画像を72dpiに縮小していたが、これを2.6倍（187.2dpi）にした。

・CairoFontFace.cc
cairo_font_face_tをキャッシュしているが、縦書き横書き（wmode）が違う場合でも同じフォントとして扱われ、縦書き横書きが混在した場合に縦書き部分に横書きフォントが使われてしまうバグがあったので、GtkFontのgetWModeが返す値もキャッシュのキーに加えた。

・pdftocairo.cc
ファイル名の形式をname_0000.jpgにした
-scale-to-x, -scale-to-yを指定したとき、アスペクト比をそのままで最小の解像度になるようにした

■ ブックリスタ
ちび見の生成
pdftocairo -f [最初のページ] -l [最後のページ] -scale-to-x 198 -scale-to-y 285 -jpeg [PDF] [JPEGファイル]
ちら見の生成
pdftocairo -f [最初のページ] -l [最後のページ] -scale-to 480 -jpeg [PDF] [JPEGファイル]
