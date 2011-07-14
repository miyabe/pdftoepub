■ pixman cairoのビルド
export PIXMAN_DIR=/home/miyabe/workspaces/pdftosvg/pixman
export CAIRO_DIR=/home/miyabe/workspaces/pdftosvg/cairo

cd $PIXMAN_DIR
./autogen.sh
./configure
make

cd $CAIRO_DIR
./autogen.sh
make clean
./configure pixman_CFLAGS="-I$PIXMAN_DIR/pixman/" pixman_LIBS="-L$PIXMAN_DIR/pixman/.libs/ -lpixman-1"
make

■ pdftosvgのコンパイル
export PKG_CONFIG_PATH=$PIXMAN_DIR:$CAIRO_DIR
export PKG_CONFIG_TOP_BUILD_DIR=
pkg-config --cflags cairo poppler-glib

gcc -o pdftosvg pdftosvg.c `pkg-config --cflags cairo poppler-glib` -L$CAIRO_DIR/src/.libs  -lcairo -lpoppler-glib -pthread -lgdk-x11-2.0 -lgdk_pixbuf-2.0 -lm -lpangocairo-1.0 -lpango-1.0 -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -lrt -lglib-2.0

export LD_LIBRARY_PATH=$CAIRO_DIR/src/.libs:$PIXMAN_DIR/pixman/.libs

./pdftosvg test.pdf test.svg 1

■ 次の関数が加えられています
@closure: ユーザーのデータ
@surface: 画像 #cairo_surface_t
@filename: 出力先のファイル名

typedef cairo_status_t (*cairo_write_image_func_t) (void *closure,
  cairo_surface_t *surface,
  char *filename);


@surface: 画像 #cairo_surface_t
@write_image_func: 画像をファイルに書きだす関数 #cairo_write_image_func_t
@write_image_closure: ユーザーのデータ

cairo_public void
cairo_svg_surface_set_write_image_func (cairo_surface_t *surface,
  cairo_write_image_func_t write_image_func,
  void *write_image_closure);
