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
# libxext-dev
cd $CAIRO_DIR
./autogen.sh
make clean
./configure pixman_CFLAGS="-I$PIXMAN_DIR/pixman/" pixman_LIBS="-L$PIXMAN_DIR/pixman/.libs/ -lpixman-1"
make

# popplerをビルド
# libfreetype6-dev, libglib2.0-dev, poppler-data, pango-graphite, libjpeg-devパッケージを入れておく必要があります。
cd $POPPLER_DIR
./autogen.sh
make clean
./configure CAIRO_VERSION="1.12.4" CAIRO_CFLAGS="-I$CAIRO_DIR/ -I$CAIRO_DIR/src/ -I/usr/include/freetype2" CAIRO_LIBS="-L$CAIRO_DIR/src/.libs/ -lcairo" POPPLER_GLIB_CFLAGS="-I/usr/include/glib-2.0 -I/usr/lib/glib-2.0/include -I/usr/lib/x86_64-linux-gnu/glib-2.0/include -I$CAIRO_DIR/ -I$CAIRO_DIR/src/" POPPLER_GLIB_LIBS="-lglib-2.0" --datarootdir=/usr/share
make

# pdftoepubをビルド
# libxml2-dev libgtk2.0-dev libgtk2.0 libpoppler-glib-dev パッケージを入れておく必要があります。
cd $PDFTOEPUB_DIR
make

■ ツールの説明
・pdftosvg PDF 出力先ディレクトリ [SVGフォント出力(true|false)]
PDFをSVGファイルに変換します。SVGファイルは１ページ目から順に 1.svg, 2.svg, 3.svg ... という名前で生成されます。通常はフォントは各SVGファイルの中に含まれますが、３番目の引数にtrueを設定すると、出力先ディレクトリにfontsディレクトリを作成し、その中に複数のSVGフォントが font-0.svg, font-1.svg, font-2.svg ... という名前で生成され、各ページのSVGから参照されます。

例:
以下のコマンドはtest.pdfをSVGに変換し、結果をTESTディレクトリに出力します

./pdftosvg test.pdf TEST

■ パッケージツール
あらかじめ、次のディレクトリ構成を準備しておいてください
[ID]は書誌IDです。
[ID]/[ID].pdf -変換対象のPDF
[ID]/[ID].xml -書誌データXML
[ID]/m_[ID].xml -サンプル属性XML
[ID]/ins -挿し込みデータ

・pdftoepub.pl ディレクトリ名 出力先 [raster|svg] [-view-height ビュー高さ] [-aaVector yes|no] [-quality 画質] [-png] [-epub2] [-kobo] [-imagespine] [-skipBlankPage]
PDFからEPUBを生成するPerlスクリプトです。
ディレクトリ名の最後に / を付けると、さらにディレクトリ中にある複数のディレクトリを処理します。
raster|svgのいずれかを指定すると、全体をラスター化したもの、SVGにしたもののいずれかを出力します。指定しない場合は両方を出力します。

EPUBに挿し込むデータは挿し込みデータディレクトリ([ID]/ins)にEPUB内と同じディレクトリ構成で配置します。EPUBに挿し込むページは ページ番号-通し番号/main.html という名前で配置しておきます。例えば 3-1/main.html, 3-2/main.html, 3-3/main.html ... という名前で配置すると、それぞれのコンテンツが順に3ページと4ページの間に挿入されます。1ページの前に挿入する場合は 0-1/main.html のようにします。

-view-height, -aaVectorオプションはコマンドラインの最後に付けて下さい。

-view-heightは、rasterで出力される画像の高さをピクセル数で指定します。デフォルトは2048です。

-aaVectorは、rasterで出力されるときに、文字以外のオブジェクトをアンチエイリアスするかどうかを指定します。
デフォルトはyesでアンチエイリアスをしますが、noを指定するとアンチエイリアスをしません。

-qualityは、rasterで出力されるJPEG画像のデフォルト画質で、1から100の値を設定します。デフォルトは98です。PNGには無関係です。

-pngを付けるとPNG形式で出力します。

-epub2を付けるとEPUB2互換形式で出力します。各ページはXHTMLになります。

-koboを付けると画像の中寄せ位置調整をしません。

-imagespineを付けると、各ページが画像になります。これはEPUBとしては不正なものになります。

-skipBlankPageを付けると、XMLよりブランク（PageKbn=3または99）とされたページを飛ばします（出力しません）。

戻り値：単一ファイルを処理する場合　成功した場合 0 エラー発生時 -1
ディレクトリを指定した場合は常に 0　が戻ります

・epub-package.pl ディレクトリ名
ディレクトリをZIPにまとめてEPUBを生成します。

・pdf-images.pl ディレクトリ名
PDF中の画像を抽出してサイズを調べます。
ディレクトリ名の最後に / を付けると、さらにディレクトリ中にある複数のディレクトリを処理します。
抽出した画像は各ディレクトリのwork/imagesに出力されます。
画像サイズは標準出力に出力されます。

・generate-sample.pl ディレクトリ名 出力先
サンプル画像、サムネイルを生成します
ディレクトリ名の最後に / を付けると、さらにディレクトリ中にある複数のディレクトリを処理します。

・epubtojson.php EPUBファイル 出力先ディレクトリ
EPUBファイルから配信フォーマットを生成します。
実行には、PHP, Imagemagickが必要です。
Ubuntu/Debianでは php5-imagick パッケージをインストールして下さい。

■ patchesに含まれるパッチ
epub-patch.pl EPUBファイル
 EPUBファイルのOPFのitemrefのproperties（ページの右左）が単純に互い違いになっていたものを、SVGのファイル名によるページ番号に合わせて修正します。

epub-patch2.pl EPUBファイル
 各SVGに含まれる画像をlayout:viewportに合わせて拡大し、ページの中央（のど）に寄せます。

epub-patch3.pl ディレクトリ
 ディレクトリに含まれるepubとopfの<meta property="layout:orientation">landscape</meta>を削除します。

epub-patch4.pl ディテクトリ
 ディレクトリに含まれるepubのopfの0ページを削除します。

epub-patch5.pl ディレクトリ
 ディレクトリに含まれるepubに<meta property="layout:orientation">～がなければ、<meta property="layout:orientation">auto</meta>を挿入します。

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

・CairoFontFace.cc
cairo_font_face_tをキャッシュしているが、縦書き横書き（wmode）が違う場合でも同じフォントとして扱われ、縦書き横書きが混在した場合に縦書き部分に横書きフォントが使われてしまうバグがあったので、GtkFontのgetWModeが返す値もキャッシュのキーに加えた。

・GfxFont.cc
縦書きフォントの中央合わせでフォントの幅を考慮してなかった箇所を修正。
450のような100の倍数でないフォントウェイトがエラーとされていたので、柔軟に解釈するように修正。

・pdftocairo.cc
ファイル名の形式をname_0000.jpgにした
-scale-to-x, -scale-to-yを指定したとき、アスペクト比をそのままで最小の解像度になるようにした

・pdftoppm.cc
ファイル名の形式を00000.jpgにした
-jpegcompressionというJPEGの画質を指定するオプションを入れた。引数の形式は "q=画質"

・SplashBitmap.cc
compressionStringでJPEGの画質を指定できるようにした。文字列の形式は "q=画質"

・Stream.cc
1ビット画像のPredictor = 2の処理にバグがあったため修正。

・Splash.cc
pipeSetXYでバッファ外に描画しないように修正

■ ブックリスタ
ちび見の生成
pdftocairo -f [最初のページ] -l [最後のページ] -scale-to-x 198 -scale-to-y 285 -jpeg [PDF] [JPEGファイル]
ちら見の生成
pdftocairo -f [最初のページ] -l [最後のページ] -scale-to 480 -jpeg [PDF] [JPEGファイル]

■ 使用するXMLタグ
/Content/PublisherInfo/Name
/Content/PublisherInfo/Kana
/Content/MagazineInfo/Name
/Content/MagazineInfo/Kana
/Content/CoverDate
/Content/SalesDate
/Content/IntroduceScript
/Content/SalesDate
/Content/ContentInfo/PageOpenWay
/Content/ContentInfo/Orientation
/Content/DataType
/Content/ContentInfo/IndexList/Index
/Content/ContentInfo/IndexList/Index/Title
/Content/ContentInfo/IndexList/Index/StartPage
/Content/PageContentList/PageContent
/Content/PageContentList/PageContent/PageNo
/Content/PageContentList/PageContent/PageKbn
/Content/PageContentList/PageContent/ViewHeight
/Content/PageContentList/PageContent/Resolution
/Content/PageContentList/PageContent/Quality
/Content/PageContentList/PageContent/ImageFormat
/Content/ContentInfo/PreviewPageList/PreviewPage
/Content/ContentInfo/PreviewPageList/PreviewPage/StartPage
/Content/ContentInfo/PreviewPageList/PreviewPage/EndPage