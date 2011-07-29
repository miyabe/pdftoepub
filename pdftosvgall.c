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
	const char *pdf_files[] = {
		"PD1213/PD1213P044.pdf",
		"PD1213/PD1213P045.pdf",
		"PD1213/PD1213P046.pdf",
		"PD1213/PD1213P047.pdf",
		"PD1213/PD1213P048.pdf",
		"PD1213/PD1213P049.pdf",
	};
	const char *out_files[] = {
		"PD1213/out/PD1213P044.svg",
		"PD1213/out/PD1213P045.svg",
		"PD1213/out/PD1213P046.svg",
		"PD1213/out/PD1213P047.svg",
		"PD1213/out/PD1213P048.svg",
		"PD1213/out/PD1213P049.svg",
	};
	int i;
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
    write_image_data_t data;
    
	fontfile = cairo_svg_fontfile_create("font.svg");

for(i = 0; i < 6; ++i){
    g_type_init ();
    error = NULL;

	pdf_file = pdf_files[i];
	out_file = out_files[i];
	page_num = 1;
	
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
 
    surface = cairo_svg_surface_create_with_fontfile (out_file, width, height, fontfile);
    //surface = cairo_svg_surface_create (out_file, width, height);
    
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
        printf("ERR %s\n", cairo_status_to_string (status));

    cairo_destroy (cr);

    cairo_surface_destroy (surface);

    g_object_unref (document);
}
    
    cairo_svg_fontfile_finish(fontfile);

    return 0;
}