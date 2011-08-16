# パスの設定
export PIXMAN_DIR=PIXMANのディレクトリのパス
export CAIRO_DIR=CAIROのディレクトリのパス
export POPPLER_DIR=POPPLERのディレクトリのパス

export PIXMAN_DIR=`pwd`/pixman
export CAIRO_DIR=`pwd`/cairo
export POPPLER_DIR=`pwd`/poppler

# pkg-configのための環境変数を設定
export PKG_CONFIG_PATH=$PIXMAN_DIR:$CAIRO_DIR:$POPPLER_DIR
export PKG_CONFIG_TOP_BUILD_DIR=
pkg-config --cflags cairo poppler-glib

# 実行時のライブラリパスを設定
export LD_LIBRARY_PATH=$CAIRO_DIR/src/.libs:$PIXMAN_DIR/pixman/.libs:$POPPLER_DIR/glib/.libs

■ pixman cairoのビルド
# Gitからソースを取得
git clone git://anongit.freedesktop.org/git/pixman.git
git clone git://github.com/miyabe/cairo.git

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

■ popplerのビルド
cd $POPPLER_DIR
./autogen.sh
make clean
./configure CAIRO_CFLAGS="-I$CAIRO_DIR/ -I$CAIRO_DIR/src/" CAIRO_LIBS="-L$CAIRO_DIR/src/.libs/ -lcairo" CFLAGS="-I/usr/include/glib-2.0 -I/usr/include/glib-2.0/include" LIBS="-lglib-2.0" --datarootdir=/usr/share
make

■ サンプルプログラムのコンパイルと実行
# pdftoepub
gcc -o pdftoepub pdftoepub.c `pkg-config --cflags cairo poppler-glib` -L$CAIRO_DIR/src/.libs -L$POPPLER_DIR/glib/.libs -lcairo -lpoppler-glib -pthread -lgdk-x11-2.0 -lgdk_pixbuf-2.0 -lm -lpangocairo-1.0 -lpango-1.0 -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -lrt -lglib-2.0; ./pdftoepub work/PD1213P044.pdf work/PD1213P044


# 実行
./pdftosvg test.pdf test.svg 1

./svgtest test.pdf

■ cairoの修正内容
Webkitで画像の表示がおかしくなる問題を回避するため、patternのpatternTransformをuseのtransformに移した。

Webkitでは﹂﹁﹄﹃←↓→↑に相当する文字が、縦書きで勝手に回転されるため、cairoで出力する際にあらかじめ逆方向に回転させるようにした。

出力されるSVGのビューポートは設定通りで、幅と高さは常に100%とした。

<font-face>への対応、外部にフォントファイルを出力できるようにソースの各所を修正した。

show_text_glyphの呼び出しに対応した。
show_text_glyphだけを呼び出した場合は<font-face>、
show_glyphだけを呼び出した場合は<symbol>によりテキストを出力する。

縦書き、横書きフォントを内部的に判別できるようにした。

・ 既知の問題
show_text_glyphとshow_glyphの混合呼び出しには対応していない。おそらく不正確なSVGが出力される。

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
画像の解像度を落とさないようにした。

cairoへの出力でshow_glyphではなくshow_text_glyphを呼び出すようにした。

■ SVG-OTF変換について
CIDに変換し、単一化する必要がある

fontforge -c 'open($1);' font.svg
