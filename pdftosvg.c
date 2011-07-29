#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poppler.h>
#include <cairo.h>
#include <cairo-svg.h>

typedef struct write_image_data {
	int counter;
	const char* filename;
	const char* basename;
} write_image_data_t;

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

int main(int argc, char *argv[])
{
    PopplerDocument *document;
    PopplerPage *page;
    double width, height;
    GError *error;
    const char *pdf_file;
    const char *out_file;
    gchar *absolute, *uri;
    int page_num, num_pages;
    cairo_svg_fontfile_t *fontfile;
    cairo_surface_t *surface;
    cairo_t *cr;
    cairo_status_t status;
    char *tmpChar;

    if (argc != 4) {
        printf ("Usage: pdftoimage input_file.pdf output_file.svg page\n");
        return 0;
    }

    pdf_file = argv[1];
    out_file = argv[2];
    page_num = atoi(argv[3]);
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
    if (page_num < 1 || page_num > num_pages) {
        printf("page must be between 1 and %d\n", num_pages);
        return 1;
    }


    page = poppler_document_get_page (document, page_num - 1);
    if (page == NULL) {
        printf("poppler fail: page not found\n");
        return 1;
    }

    poppler_page_get_size (page, &width, &height);
 
	//fontfile = cairo_svg_fontfile_create("test_font.svg");
    //surface = cairo_svg_surface_create_with_fontfile (out_file, width, height, fontfile);
    surface = cairo_svg_surface_create (out_file, width, height);
    
    write_image_data_t data;
    data.counter = 0;
    
    data.filename = (const char*)out_file;
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

    g_object_unref (document);
    
    //cairo_svg_fontfile_finish(fontfile);

    return 0;
}