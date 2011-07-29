#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poppler.h>
#include <cairo.h>

int main(int argc, char *argv[])
{
    GError *error;
    const char *out_file;
    cairo_surface_t *surface;
    cairo_t *cr;
    cairo_status_t status;
	double width = 200, height = 200;

    if (argc != 2) {
        printf ("Usage: svgtest output_file.svg\n");
        return 0;
    }

    out_file = argv[1];
    surface = cairo_svg_surface_create (out_file, width, height);
	
    cr = cairo_create (surface);
    
    {
		const char *utf8 = "poppler cairo";
		double x,y;
		cairo_select_font_face (cr, "Courier",
		    CAIRO_FONT_SLANT_NORMAL,
		    CAIRO_FONT_WEIGHT_NORMAL);
		cairo_set_font_size (cr, 20.0);
		x=20.0; y=20.0;
		cairo_move_to (cr, x, y);
		cairo_show_text (cr, utf8);
	}
    {
		const char *utf8 = "poppler cairo";
		double x,y;
		cairo_select_font_face (cr, "Times",
		    CAIRO_FONT_SLANT_NORMAL,
		    CAIRO_FONT_WEIGHT_NORMAL);
		cairo_set_font_size (cr, 20.0);
		x=20.0; y=50.0;
		cairo_move_to (cr, x, y);
		cairo_show_text (cr, utf8);
	}
	
    status = cairo_status(cr);
    if (status)
        printf("%s\n", cairo_status_to_string (status));

    cairo_destroy (cr);

    cairo_surface_destroy (surface);

    return 0;
}