#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
	
#include <poppler.h>
#include <cairo.h>
#include <cairo-svg.h>

typedef struct write_image_data {
	int counter;
	const char* filename;
	const char* basename;
} write_image_data_t;

/* 画像出力関数 */
static cairo_status_t
write_image_func (void *closure,
		cairo_surface_t *surface,
		char *filename) {
	cairo_status_t status = CAIRO_STATUS_SUCCESS;
	write_image_data_t *data = (write_image_data_t*)closure;
	data->counter++;
	sprintf(filename, "%s-%d.png", data->filename, data->counter);
    status = cairo_surface_write_to_png (surface, filename);
	sprintf(filename, "%s-%d.png", data->basename, data->counter);
	return status;
}

void html_escape(FILE *fp, const char *str) {
	int len = strlen(str);
	int i;
	char c;
	
	for (i = 0; i < len; ++i) {
		c = str[i];
		switch(c) {
			case '<':
			fprintf(fp, "&lt;");
			continue;
			
			case '>':
			fprintf(fp, "&gt;");
			continue;
			
			case '&':
			fprintf(fp, "&amp;");
			continue;
			
			case '\"':
			fprintf(fp, "&quot;");
			continue;
		}
		putc(c, fp);
	}
}

void write_svg(const char* out_file, PopplerPage *page,
	cairo_svg_fontfile_t *fontfile) {
    double width, height;
    cairo_surface_t *surface;
    write_image_data_t data;
    cairo_t *cr;
    cairo_status_t status;
    char *tmpChar;

	poppler_page_get_size (page, &width, &height);
	 
	//surface = cairo_svg_surface_create (out_file, width, height);
	surface = cairo_svg_surface_create_with_fontfile (out_file, width, height, fontfile);
    
    data.counter = 0;
    
    data.filename = out_file;
   	tmpChar = (char*)strrchr(out_file, '/');
   	if (tmpChar == NULL) {
   		data.basename = (const char*)out_file;
   	}
   	else {
    	data.basename = (const char*)(tmpChar + 1);
    }
    cairo_svg_surface_set_write_image_func(surface, write_image_func, (void*)&data);
	
    cr = cairo_create (surface);
    cairo_rectangle (cr, 0, 0, (int)width, (int)height);
    cairo_clip (cr);
    cairo_new_path (cr);
    
    poppler_page_render (page, cr);
    
    g_object_unref (page);

    status = cairo_status(cr);
    if (status)
        printf("%s\n", cairo_status_to_string (status));

    cairo_destroy (cr);

    cairo_surface_destroy (surface);
}

int main(int argc, char *argv[])
{
    PopplerDocument *document;
    PopplerViewerPreferences view_prefs;
    PopplerPage *page;
    GError *error;
    const char *pdf_file;
    const char *out_dir;
    char out_file[256];
    char font_file[256];
    
    FILE *fp;
    char filename[256];
    
    gchar *title, *author, *permanent_id, *update_id;
    gchar *absolute, *dir, *uri;
    int page_num, num_pages;
    cairo_svg_fontfile_t *fontfile;
    char *tmpChar;

    if (argc != 3) {
        printf ("Usage: pdftosvg input_file.pdf dir\n");
        return 0;
    }

    pdf_file = argv[1];
    out_dir = argv[2];
    g_type_init ();
    error = NULL;

    if (g_path_is_absolute(pdf_file)) {
        absolute = g_strdup (pdf_file);
    } else {
        gchar *dir = g_get_current_dir ();
        absolute = g_build_filename (dir, pdf_file, (gchar *) 0);
        free (dir);
    }
    uri = g_filename_to_uri (absolute, NULL, &error);
    free (absolute);
    if (uri == NULL) {
        printf("%s\n", error->message);
        return 1;
    }

    document = poppler_document_new_from_file (uri, NULL, &error);
    if (document == NULL) {
        printf("%s\n", error->message);
        return 1;
    }
    num_pages = poppler_document_get_n_pages (document);
    
    mkdir(out_dir, S_IRWXU | S_IRWXG | S_IRWXO);
/*
    title = poppler_document_get_title (document);
    author = poppler_document_get_author (document);
    poppler_document_get_id (document, &permanent_id, &update_id);
    permanent_id[32] = update_id[32] = 0;
    g_object_get(document, "viewer-preferences", &view_prefs);
    
    // mimetype
    sprintf(filename, "%s/mimetype", out_dir);
    fp = fopen(filename, "w");
    fprintf(fp, "application/epub+zip");
    fclose(fp);
    
    // container.xml
    sprintf(filename, "%s/META-INF", out_dir);
    mkdir(filename, S_IRWXU | S_IRWXG | S_IRWXO);
    sprintf(filename, "%s/META-INF/container.xml", out_dir);
    fp = fopen(filename, "w");
    fprintf(fp, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    fprintf(fp, "<container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\" version=\"1.0\">\n");
    fprintf(fp, "   <rootfiles>\n");
    fprintf(fp, "      <rootfile full-path=\"content.opf\" media-type=\"application/oebps-package+xml\"/>\n");
    fprintf(fp, "   </rootfiles>\n");
    fprintf(fp, "</container>\n");
    fclose(fp);
    
    // toc.xhtml
    sprintf(filename, "%s/toc.xhtml", out_dir);
    fp = fopen(filename, "w");
    fprintf(fp, "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"\n");
    fprintf(fp, "profile=\"http://www.idpf.org/epub/30/profile/content/\">\n");
    fprintf(fp, "<head>\n");
    
    fprintf(fp, "<title>");
    //html_escape(fp, title);
    fprintf(fp, "</title>\n");
    
    fprintf(fp, "</head>\n");
    fprintf(fp, "<body>\n");
    fprintf(fp, "<nav id=\"toc\" epub:type=\"toc\">\n");
    fprintf(fp, "<h1>Table of contents.</h1>\n");
    fprintf(fp, "<ol>\n");
	for (page_num = 0; page_num < num_pages; page_num++) {
	    fprintf(fp, "<li id=\"page-%d\">\n", page_num);
	    fprintf(fp, "<a href=\"%d.svg\">Page %d</a>\n", page_num, page_num);
	    fprintf(fp, "</li>\n");
	}
    fprintf(fp, "</ol>\n");
    fprintf(fp, "</nav>\n");
    fprintf(fp, "</body>\n");
    fprintf(fp, "</html>\n");
    fclose(fp);
    
    // content.opf
    sprintf(filename, "%s/content.opf", out_dir);
    fp = fopen(filename, "w");
    fprintf(fp, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    fprintf(fp, "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"BookID\">\n");
    fprintf(fp, "   <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n");
    fprintf(fp, "             xmlns:opf=\"http://www.idpf.org/2007/opf\">\n");
    fprintf(fp, "      <dc:language>ja</dc:language>\n");
    fprintf(fp, "      <dc:identifier id=\"BookID\" opf:scheme=\"UUID\">%s-%s</dc:identifier>\n", permanent_id, update_id);

    fprintf(fp, "      <dc:title>");
    html_escape(fp, title);
    fprintf(fp, "</dc:title>\n");

    fprintf(fp, "      <dc:creator opf:role=\"aut\">");
    html_escape(fp, author);
    fprintf(fp, "</dc:creator>\n");
    
    fprintf(fp, "   </metadata>\n");
    fprintf(fp, "   <manifest>\n");
    fprintf(fp, "      <item id=\"nav\" href=\"toc.xhtml\" properties=\"nav\" media-type=\"application/xhtml+xml\"/>\n");
    for (page_num = 0; page_num < num_pages; page_num++) {
    	fprintf(fp, "      <item id=\"t%d\" href=\"%d.svg\" media-type=\"image/svg+xml\"/>\n", page_num, page_num);
	}
	fprintf(fp, "      <item id=\"f1\" href=\"font.svg\" media-type=\"image/svg+xml\"/>\n");
    fprintf(fp, "   </manifest>\n");
    fprintf(fp, "   <spine page-progression-direction=\"%s\">\n", (view_prefs & POPPLER_VIEWER_PREFERENCES_DIRECTION_RTL) ? "rtl" : "default");
    for (page_num = 0; page_num < num_pages; page_num++) {
    	fprintf(fp, "      <itemref idref=\"t%d\"/>\n", page_num);
    }
	fprintf(fp, "   </spine>\n");
    fprintf(fp, "   <guide>\n");
    for (page_num = 0; page_num < num_pages; page_num++) {
    	fprintf(fp, "      <reference type=\"text\" href=\"%d.svg\"/>\n", page_num);
    }
    fprintf(fp, "   </guide>\n");
    fprintf(fp, "</package>\n");
    fclose(fp);

    free(title);
    free(author);
    free(permanent_id);
    free(update_id);
*/
    sprintf(font_file, "%s/fonts", out_dir);
    mkdir(font_file, S_IRWXU | S_IRWXG | S_IRWXO);
    tmpChar = (char*)strrchr(font_file, '/');
    if (tmpChar == NULL) {
	    tmpChar = (char*)font_file;
    }
    else {
    tmpChar = (char*)(tmpChar + 1);
    }
	fontfile = cairo_svg_fontfile_create(tmpChar);
    
    for (page_num = 0; page_num < num_pages; page_num++) {
	    page = poppler_document_get_page (document, page_num);
	    if (page == NULL) {
	        printf("poppler fail: page not found\n");
	        return 1;
	    }

	 	sprintf(out_file, "%s/%d.svg", out_dir, page_num);
	 	write_svg(out_file, page, fontfile);
    }
	g_object_unref (document);
   
    cairo_svg_fontfile_finish(fontfile, font_file);

    return 0;
}