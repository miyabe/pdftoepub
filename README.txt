■ ビルド方法
# Debian wheezy でビルド・動作を確認しています

# Packages

apt-get install git pkg-config automake libtool bzip2 autoconf gettext make g++ zip unzip

apt-get install libxext-dev libcurl4-openssl-dev imagemagick libmagickcore-dev zlib1g-dev libpng12-dev libfreetype6-dev libglib2.0-dev poppler-data pango-graphite libjpeg-dev libxrender-dev libfontconfig1-dev libopenjpeg-dev libxcb-render-util0-dev libxcb-render0-dev libpoppler-glib-dev libxml2-dev libgtk2.0-dev libgtk2.0 liblcms2-dev libhtml-html5-entities-perl libgconf2-4 libjpeg-progs

apt-get install php php-mysql php-sybase php-imagick php-pear php-dev libssh2-1 libssh2-1-dev

pear install Archive_Tar

apt-get install libxi-dev freeglut3-dev

apt-get install libossp-uuid-perl libarchive-zip-perl libxml-xpath-perl libimage-size-perl perlmagick uuid-dev
cpan install Data::UUID XML::XPath Image::Size Archive::Zip File::Copy::Recursive HTML::HTML5::Entities

apt-get install openjdk-7-jre

apt-get install ruby1.9.1 bundler

# 以下のコマンドでGitによりpoppler, freetype2, mupdf, pdftoepubのソースを取得します。

git clone https://github.com/miyabe/poppler.git
git clone git://git.sv.nongnu.org/freetype/freetype2.git
git clone https://github.com/ArtifexSoftware/mupdf
git clone https://github.com/miyabe/pdftoepub.git

# ビルドの準備のために、以下の環境変数を設定しておきます。

export POPPLER_DIR=[POPPLERのディレクトリのパス]
export PDFTOEPUB_DIR=[PDFTOEPUBのディレクトリのパス]
export FREETYPE_DIR=[FREETYPEのディレクトリのパス]
export MUPDF_DIR=[FREETYPEのディレクトリのパス]

# 例えばfooディレクトリにpixman, cairo, popplerを落とした場合は、fooディレクトリ内で以下を実行します。

export POPPLER_DIR=`pwd`/poppler
export PDFTOEPUB_DIR=`pwd`/pdftoepub
export FREETYPE_DIR=`pwd`/freetype2
export MUPDF_DIR=`pwd`/mupdf

# pkg-configのための環境変数を設定。

export PKG_CONFIG_PATH=$POPPLER_DIR
export PKG_CONFIG_TOP_BUILD_DIR=
pkg-config --cflags cairo poppler-glib

# 実行時のライブラリパスを設定。
export LD_LIBRARY_PATH=$POPPLER_DIR/glib/.libs:$FREETYPE_DIR/objs/.libs

# freetypeをビルド
cd $FREETYPE_DIR
./autogen.sh
make clean
./configure
make

# popplerをビルド
cd $POPPLER_DIR
mkdir build
cd build
cmake ..
make

# mupdfをビルド
cd $MUPDF_DIR
git submodule update --init
make clean
make

# pdftoepubをビルド
cd $PDFTOEPUB_DIR
make

■ パッケージツール
実行にはimagemagickが必要です。

あらかじめ、次のディレクトリ構成を準備しておいてください
[ID]は書誌IDです。
[ID]/[ID].xml -書誌データXML
[ID]/m_[ID].xml -サンプル属性XML
[ID]/appendix -追加データ
[ID]/textlinks.txt -リンクの設定

変換対象のPDFは次の２通りの配置方法があります。

全てのページを１つのPDFにまとめる場合：
[ID]/[ID].pdf

１ページ１PDFに分割する場合：
[ID]/magazine/00001.pdf
[ID]/magazine/00002.pdf
...

・pdftoepub.pl ディレクトリ名 出力先 [-view-height ビュー高さ] [-dpi 解像度] [-aaVector yes|no] [-program poppler|mupdf [pages]] \
[-quality 画質] [-png] [-epub2] [-kobo] [-ibooks] [-kindle] [-imagespine] [-skipBlankPage] [-sample] [-no-initial-scale] \
[-thumbnail-height サムネイル高さ] [-extractcover] [-cover-in-toc] [-use-folders]

PDFからEPUBを生成するPerlスクリプトです。
ディレクトリ名の最後に / を付けると、さらにディレクトリ中にある複数のディレクトリを処理します。

[ID]/appendix内にはPDFに追加で格納するファイルを入れてください。
サポートするファイルは音声（.mp3, .mp4）です。
appendix直下のデータがepubのアーカイブのルートの直下に格納されます。

[ID]/textlinks.txtは
ページ番号,テキスト,URL
という形式のUTF-8エンコーディングのCSVで記述してください。
指定したページの、テキストに一致する部分にURLに対するリンクを設定します。
ページ番号は、分割されていないPDFに対しては必ず1から開始します。

実行中に /tmp/pdftoepub-[プロセスID] というファイルが生成されます。正常終了した時点で、このファイルは削除されます。
エラーなど異常終了した場合はこのファイルは残り続けます。

-view-height, -aaVectorオプションはコマンドラインの最後に付けて下さい。

-view-heightは、画像の高さをピクセル数で指定します。デフォルトは2048です。画像の幅は常に1536までに制限されます。

-dpiは出力結果の解像度をdpi単位で指定します。
-view-heightと-dpiの両方を指定すると、後のほうが優先されます

-aaVectorは、文字以外のオブジェクトをアンチエイリアスするかどうかを指定します。
デフォルトはyesでアンチエイリアスをしますが、noを指定するとアンチエイリアスをしません。

-programは、PDFから画像に変換するプログラムを指定します。
popplerまたはmupdfのいずれかを指定可能です。デフォルトはpopplerです。
[pages]に、カンマ区切りのページを指定することができます。ページを指定すると、そのページだけ指定したプログラムで処理されます。
0ページは表紙で、本文は1ページから開始します。

-qualityは、JPEG画像のデフォルト画質で、1から100の値を設定します。デフォルトは98です。PNGには無関係です。

-pngを付けるとPNG形式で出力します。

-epub2を付けるとEPUB2互換形式で出力します。各ページはXHTMLになります。

-koboを付けると画像の中寄せ位置調整をしません。

-ibooksを付けるとOPFに<meta property="ibooks:binding">false</meta>タグを加えます。XHTMLのviewportはwidth=device-widthとなります。

-kindleを付けるとXHTMLに<meta name="primary-writing-mode" content="horizontal-rl"/>タグを加えます（-epub2出力かnav.xhtmlのみ）。

-imagespineを付けると、各ページが画像になります。これはEPUBとしては不正なものになります。

-skipBlankPageを付けると、XMLよりブランク（PageKbn=3または99）とされたページを飛ばします（出力しません）。
-skipBlankPageを付けない場合、ブランクページを出力します。
BlankImage/blank.pdfがあれば、それをブランクページとして使います。それがない場合は直前のページを、さらにそれもない場合は直後のページを白塗したものをブランクページとします。

-sampleを付けると、表紙とサンプルページだけ出力します。

-no-initial-scaleを付けると、ビューポートにinitial-scaleを設定しません。

-thumbnail-heightは、表紙サムネイルの高さをピクセル数で指定します。デフォルトは480です。

-previewPageOrigin 0をつけると、XMLのPreviewPageが0ベースとなります。デフォルトでは1ベースです。

-forceintを付けると、SVGのrectタグの座標値を四捨五入して整数にします。

-extractcoverを付けると、PDFの最初のページをカバーとして扱い、PDFの２ページ目が本文の１ページとなります。
このオプションは全てのページを１つのPDFにまとめる場合だけ有効です。

-cover-in-tocを付けると、表紙を「表紙」という名前で目次の先頭に入れます。
書誌データXMLにStartPageが1の目次項目が既にある場合は何もしません。

-use-foldersを付けると画像等を別のディレクトリに格納します。各ページはXHTMLになります。

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

・epubtojson.php [-xml 書誌情報XMLファイル] [-resolution 解像度] EPUBファイル 出力先ディレクトリ
EPUBファイルから配信フォーマットを生成します。

実行には、PHP, Imagemagick. Archive_Tarが必要です。
Ubuntu/Debianでは php5-imagick パッケージをインストールして下さい。
また、以下のコマンドでPearからArchive_Tarをインストールしてください。
sudo pear install Archive_Tar

meta.jsonのデータ
ItemId -EPUBファイル名の XXXX_eEPUB3.epub の XXXX の部分
ISBN -EPUBのopfのdc:identifier
JDCN -EPUBのopfのdc:identifier
BookId -EPUBのopfのdc:identifier
ItemNamedc -EPUBのopfの:title
PublisherName -EPUBのopfのdc:publisher
Authors -EPUBのopfのdc:publisherおよびdc:creator
PageNumber -EPUBのopfのopf:spine内のopf:itemrefの数
SamplePageRange -書誌情報XMLのPreviewPageで最も範囲が広いもの
UpdateDateTime -JSON出力時の時刻
TOC -EPUBのncxまたはnavファイル
PageInfo -EPUBのopfのopf:meta(property属性が"rendition:spread"のもの)とopf:manifestおよびopf:spine内の情報。colorは画像の平均彩度から判定
PageFlipDirection -EPUBのopfのopf:spineのpage-progression-direction属性
Resolution - -resolutionオプションの値。-resolutionオプションを省略した場合は1600。-resolutionオプションに0を指定した場合は出力しない。

thumbnail.jpgファイル -EPUBのカバーページまたは最初のページの縮小画像
images -各ページの縮小画像

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

■ popplerの修正内容
ビルドには以下が必要
https://packages.ubuntu.com/ja/bionic/amd64/libopenjp2-7-dev/download

・CairoOutputDev.css
cairoが対応している場合は、常にshow_text_glyphを呼び出すようにした。

・CairoFontEngine.cc
cairo_font_face_tをキャッシュしているが、縦書き横書き（wmode）が違う場合でも同じフォントとして扱われ、縦書き横書きが混在した場合に縦書き部分に横書きフォントが使われてしまうバグがあったので、GtkFontのgetWModeが返す値もキャッシュのキーに加えた。

・pdftocairo.cc
ファイル名の形式をname_0000.jpgにした

・GfxFont.cc
縦書きフォントの中央合わせでフォントの幅を考慮してなかった箇所を修正。
450のような100の倍数でないフォントウェイトがエラーとされていたので、柔軟に解釈するように修正。

・pdftoppm.cc
ファイル名の形式を00000.jpgにした
-scale-to-x, -scale-to-yを指定したとき、アスペクト比をそのままで最小の解像度になるようにした

・Stream.cc
1ビット画像のPredictor = 2の処理にバグがあったため修正。

・Splash.cc
pipeSetXYでバッファ外に描画しないように修正

・Annot.cc
アノテーションの境界を描画しないように修正

■ mupdfの修正内容
・mudraw.c
指定したページの範囲外のページを描画しないように修正。

・font.c
日本語のフォント数が多いファイルを扱えるようにMAX_BBOX_TABLE_SIZEを4096から65536に拡大。

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
