#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>

#include <poppler.h>
#include <cairo.h>
#include <cairo-svg.h>

#define CAIRO_PATCH

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

void write_svg(const char* out_file, PopplerPage *page
#ifdef CAIRO_PATCH
	, cairo_svg_fontfile_t *fontfile
#endif
) {
    double width, height;
    cairo_surface_t *surface;
    write_image_data_t data;
    cairo_t *cr;
    cairo_status_t status;
    char *tmpChar;

    poppler_page_get_size (page, &width, &height);
      
#ifdef CAIRO_PATCH
    if (fontfile != NULL) {
    	surface = cairo_svg_surface_create_with_fontfile (out_file, width, height, fontfile);
    }
    else {
    	surface = cairo_svg_surface_create (out_file, width, height);
    }
#else
    surface = cairo_svg_surface_create (out_file, width, height);
#endif
    cairo_svg_surface_restrict_to_version(surface, CAIRO_SVG_VERSION_1_2);
    status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
      abort();
    }
	
    data.counter = 0;

    data.filename = out_file;
    tmpChar = (char*)strrchr(out_file, '/');
    if (tmpChar == NULL) {
	    data.basename = (const char*)out_file;
    }
    else {
    	data.basename = (const char*)(tmpChar + 1);
    }
    
#ifdef CAIRO_PATCH
    cairo_svg_surface_set_write_image_func(surface, write_image_func, (void*)&data);
#endif

    cr = cairo_create (surface);
    cairo_rectangle (cr, 0, 0, (int)width, (int)height);
    cairo_clip (cr);
    cairo_new_path (cr);
    
    poppler_page_render (page, cr);

    status = cairo_status(cr);
    if (status)
        printf("%s\n", cairo_status_to_string (status));

    cairo_destroy (cr);

    status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
      abort();
    }

    GList *mapping = poppler_page_get_link_mapping (page);
    gint n_links = g_list_length (mapping);
    GList *l;
    for (l = mapping; l; l = g_list_next (l)) {
    	PopplerLinkMapping *lmapping = (PopplerLinkMapping*)l->data;
		double x = lmapping->area.x1;
		double y = lmapping->area.y1;
		y = height - y;
		double w = lmapping->area.x2 - lmapping->area.x1;
		double h = lmapping->area.y2 - lmapping->area.y1;
		y -= h;
    	switch (lmapping->action->type) {
    	case POPPLER_ACTION_GOTO_DEST: {
    		PopplerActionGotoDest *dest = (PopplerActionGotoDest*)lmapping->action;
    		char uri[256];
    		sprintf(uri, "%d.svg", dest->dest->page_num);
    		cairo_svg_surface_link(surface,
    				uri, x, y, w, h);
    	}
    		break;

    	case POPPLER_ACTION_URI:
    	{
    		PopplerActionUri *auri = (PopplerActionUri*)lmapping->action;
    		cairo_svg_surface_link(surface,
    				auri->uri, x, y, w, h);
    	}
        	break;
    	}
    }
    poppler_page_free_link_mapping (mapping);

    cairo_surface_destroy (surface);

    g_object_unref (page);
}

int main(int argc, char *argv[])
{
    PopplerDocument *document;
    PopplerPage *page;
    GError *error;
    const char *pdf_file;
    const char *out_dir;
    char out_file[256];
    char font_file[256];
    
    FILE *fp;
    char filename[256];
    
    gchar *absolute, *dir, *uri;
    int page_num, num_pages;
#ifdef CAIRO_PATCH
    cairo_svg_fontfile_t *fontfile = NULL;
#endif
    char *tmpChar;

    if (argc < 3 && argc > 4) {
        printf ("Usage: pdftosvg input_file.pdf dir [separate_fonts]\n");
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

#ifdef CAIRO_PATCH
    if (argc == 4) {
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
    }
#endif
    
    for (page_num = 1; page_num <= num_pages ;page_num++) {
      page = poppler_document_get_page (document, page_num - 1);
      if (page == NULL) {
	  printf("poppler fail: page not found\n");
	  return 1;
      }
      sprintf(out_file, "%s/%d.svg", out_dir, page_num);
      write_svg(out_file, page
#ifdef CAIRO_PATCH
		, fontfile
#endif
      );
    }
    g_object_unref (document);
    
#ifdef CAIRO_PATCH
    if (fontfile != NULL) {
    	cairo_svg_fontfile_finish(fontfile, font_file);
    }
#endif

    return 0;
}
