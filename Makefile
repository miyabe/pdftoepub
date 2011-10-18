CFLAGS = `pkg-config --cflags cairo poppler-glib glib-2.0` -I/usr/include/glib-2.0 -I/usr/include/libxml2 -I/usr/include
LIBS = -L$(CAIRO_DIR)/src/.libs -L$(POPPLER_DIR)/glib/.libs -lcairo -lpoppler-glib -pthread -lgdk-x11-2.0 -lgdk_pixbuf-2.0 -lm -lpangocairo-1.0 -lpango-1.0 -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -lrt -lglib-2.0 -lxml2
pdftosvg: pdftosvg.c
	gcc -o pdftosvg pdftosvg.c $(CFLAGS) $(LIBS)

