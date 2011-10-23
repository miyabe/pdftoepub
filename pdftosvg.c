#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>

#include <jpeglib.h>
#include <libxml/SAX.h>

#include <poppler.h>
#include <cairo.h>
#include <cairo-svg.h>

#define CAIRO_PATCH

#define VIEW_HEIGHT 2068.0

void cairo_surface_write_to_jpg (cairo_surface_t *sf, char *name){
	unsigned char *pixels = cairo_image_surface_get_data(sf);
	int stride = cairo_image_surface_get_stride(sf);

	FILE *fp = fopen(name, "wb");

	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	cinfo.err = jpeg_std_error(&jerr);
	jpeg_create_compress(&cinfo);
	jpeg_stdio_dest(&cinfo, fp);

	unsigned char line[stride];
	JSAMPROW row_pointer[1];
	row_pointer[0] = (JSAMPROW)&line;

	cinfo.image_width = (int)cairo_image_surface_get_width (sf);
	cinfo.image_height = (int)cairo_image_surface_get_height (sf);
	cinfo.input_components = 3;
	cinfo.in_color_space = JCS_RGB;

	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, 100, TRUE);
	jpeg_start_compress(&cinfo, TRUE);

	int i, j, k;
	for ( i = 0; i < cinfo.image_height; i++ ) {
		k = 0;
		for ( j = 0; j < stride; j += 4 ) {
			line[k] = pixels[j + 2];
			line[k + 1] = pixels[j + 1];
			line[k + 2] = pixels[j];
			k += 3;
		}
		jpeg_write_scanlines(&cinfo, row_pointer, 1);
		pixels += stride;
	}

	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);

	fclose(fp);
}

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
  if (status != CAIRO_STATUS_SUCCESS)
	return status;

  struct stat buf;
  stat(filename, &buf);
  if (1/*buf.st_size > 1000000*/) {
	  cairo_surface_t *png = cairo_image_surface_create_from_png(filename);
	  remove(filename);
	  sprintf(filename, "%s-%d.jpg", data->filename, data->counter);
	  cairo_surface_write_to_jpg (png, filename);
	  sprintf(filename, "%s-%d.jpg", data->basename, data->counter);
	  cairo_surface_destroy(png);
  }
  else {
	  sprintf(filename, "%s-%d.png", data->basename, data->counter);
  }
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

void write_image(int page_num, const char *out_dir, PopplerPage *page)
{
    char out_file[256];
    double s, width, height;
    cairo_surface_t *surface;
    cairo_t *cr;
    cairo_status_t status;

    poppler_page_get_size (page, &width, &height);
    s = VIEW_HEIGHT / height;
    width *= s;
    height = VIEW_HEIGHT;

    surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, width, height);

    status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
      abort();
    }

    cr = cairo_create (surface);
    cairo_rectangle (cr, 0, 0, (int)width, (int)height);
    cairo_clip (cr);
    cairo_new_path (cr);
    cairo_scale(cr, s, s);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);

    poppler_page_render (page, cr);

    status = cairo_status(cr);
    if (status)
        printf("%s\n", cairo_status_to_string (status));

    cairo_destroy (cr);

    status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
      abort();
    }

	 sprintf(out_file, "%s/%05d.png", out_dir, page_num);
    cairo_surface_write_to_png(surface, out_file);

    struct stat buf;
    stat(out_file, &buf);
    if (1/* buf.st_size > 1000000 */) {
  	   cairo_surface_t *png = cairo_image_surface_create_from_png(out_file);
       remove(out_file);
	   sprintf(out_file, "%s/%05d.jpg", out_dir, page_num);
      cairo_surface_write_to_jpg(surface, out_file);
      cairo_surface_destroy(png);
    }

    cairo_surface_destroy (surface);
}

void OnStartElement(void* user_data, const xmlChar* name, const xmlChar** atts) {
	int *elements = user_data;
	(*elements)++;
}

void write_svg(int page_num, const char *out_dir, PopplerPage *page
#ifdef CAIRO_PATCH
	, cairo_svg_fontfile_t *fontfile
#endif
) {
    char out_file[256];
    double s, width, height;
    cairo_surface_t *surface;
    write_image_data_t data;
    cairo_t *cr;
    cairo_status_t status;
    char *tmpChar;
    char filename[256];

	sprintf(out_file, "%s/%05d.svg", out_dir, page_num);

    poppler_page_get_size (page, &width, &height);
    s = VIEW_HEIGHT / height;
    width *= s;
    height = VIEW_HEIGHT;

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
    cairo_svg_surface_restrict_to_version(surface, CAIRO_SVG_VERSION_1_1);
    status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
      abort();
    }
	
    data.counter = 0;

    sprintf(filename, "%s/images/%05d", out_dir, page_num);
    data.filename = filename;
    data.basename = filename + strlen(out_dir) + 1;;

#ifdef CAIRO_PATCH
    cairo_svg_surface_set_write_image_func(surface, write_image_func, (void*)&data);
#endif

    cr = cairo_create (surface);
    cairo_rectangle (cr, 0, 0, (int)width, (int)height);
    cairo_clip (cr);
    cairo_new_path (cr);
    cairo_scale(cr, s, s);
    
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
    		sprintf(uri, "%05d.svg", dest->dest->page_num);
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

    int elements;
    xmlSAXHandler sax;
    memset(&sax, 0, sizeof(sax));
    sax.startElement = OnStartElement;
    xmlSAXUserParseFile(&sax, &elements, out_file);

    if (0/*elements > 500000*/) {
		remove(out_file);
		int i;
		for(i = 1; ; ++i) {
			sprintf(filename, "%s/images/%05d-%d.png", out_dir, page_num, i);
			if (remove(filename))
				break;
		}
		write_image(page_num, out_dir, page);
    }

    g_object_unref (page);
}

int main(int argc, char *argv[])
{
    PopplerDocument *document;
    PopplerPage *page;
    GError *error;
    const char *pdf_file;
    const char *out_dir;
    char font_file[256];
    
    FILE *fp;
    char filename[256];
    
    gchar *absolute, *dir, *uri;
    int page_num, num_pages;
#ifdef CAIRO_PATCH
    cairo_svg_fontfile_t *fontfile = NULL;
#endif
    char *tmpChar;

    if (argc < 3 && argc > 5) {
        printf ("Usage: pdftosvg input_file.pdf dir [separate_fonts] [page]\n");
        return 0;
    }

    pdf_file = argv[1];
    out_dir = argv[2];
    g_type_init ();
    error = NULL;
    
    mkdir(out_dir, S_IRWXU | S_IRWXG | S_IRWXO);
	sprintf(font_file, "%s/images", out_dir);
	mkdir(font_file, S_IRWXU | S_IRWXG | S_IRWXO);

#ifdef CAIRO_PATCH
    if (argc >= 4 && strcmp(argv[3], "true") == 0) {
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

    if (strcmp(".pdf", pdf_file + strlen(pdf_file) - 4) == 0) {
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

		int start = 1, end = num_pages;
		if (argc >= 5) {
			start = end = atoi(argv[4]);
		}
		for (page_num = start; page_num <= end ;page_num++) {
		  page = poppler_document_get_page (document, page_num - 1);
		  if (page_num == start) {
			  double width, height;
			  char filename[256];
			  poppler_page_get_size (page, &width, &height);
			  width *= VIEW_HEIGHT / height;
			  height = VIEW_HEIGHT;
			  sprintf(filename, "%s/size", out_dir);
			  fp = fopen(filename, "w");
			  fprintf(fp, "%d %d", (int)width, (int)height);
			  fclose(fp);
		  }
		  if (page == NULL) {
		  printf("poppler fail: page not found\n");
		  return 1;
		  }
		  write_svg(page_num, out_dir, page
	#ifdef CAIRO_PATCH
			, fontfile
	#endif
		  );
		}
		g_object_unref (document);
    }
    else {
    	char firstPage = 1;
    	DIR *dir = opendir(pdf_file);
    	struct dirent *ent;
		while ((ent = readdir(dir)) != NULL) {
			if (strcmp(ent->d_name, "..") == 0)
				continue;
			if (strcmp(ent->d_name, ".") == 0) {
				page_num = 0;
				sprintf(filename, "%s/../cover.pdf", pdf_file);
				fp = fopen(filename, "r");
				if (fp == NULL)
					continue;
				fclose(fp);
			}
			else {
				if (sscanf(ent->d_name, "%05d.pdf", &page_num) == 0)
					continue;
				sprintf(filename, "%s/%s", pdf_file, ent->d_name);
			}

			if (g_path_is_absolute(filename)) {
				absolute = g_strdup (filename);
			} else {
				gchar *dir = g_get_current_dir ();
				absolute = g_build_filename (dir, filename, (gchar *) 0);
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
			if (num_pages != 1) {
				  printf("not single page pdf\n");
				  return 1;
			}
			page = poppler_document_get_page (document, 0);
			if (page == NULL) {
			  printf("poppler fail: Page not found\n");
			  return 1;
			}
			if (page_num >= 1 && firstPage) {
			  double width, height;
			  char filename[256];
			  poppler_page_get_size (page, &width, &height);
			  width *= VIEW_HEIGHT / height;
			  height = VIEW_HEIGHT;
			  sprintf(filename, "%s/size", out_dir);
			  fp = fopen(filename, "w");
			  fprintf(fp, "%d %d", (int)width, (int)height);
			  fclose(fp);
			  firstPage = 0;
			}
			write_svg(page_num, out_dir, page
		#ifdef CAIRO_PATCH
				, fontfile
		#endif
			);
		}
		closedir(dir);
    }
    
#ifdef CAIRO_PATCH
    if (fontfile != NULL) {
    	cairo_svg_fontfile_finish(fontfile, font_file);
    }
#endif

    return 0;
}
