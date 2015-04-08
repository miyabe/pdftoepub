CFLAGS = `pkg-config --cflags poppler-glib glib-2.0 libxml-2.0`
LIBS = -lpoppler-glib -pthread -lgdk-x11-2.0 -lgdk_pixbuf-2.0 -lm -lpango-1.0 -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -lrt -lglib-2.0 -lxml2

all: pdftomapping

pdftomapping: pdftomapping.c
	gcc -o pdftomapping pdftomapping.c $(CFLAGS) $(LIBS)
	