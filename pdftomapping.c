#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>

#include <poppler.h>

void write_mapping(int page_num, PopplerPage *page) {
	double w, h;
	poppler_page_get_size (page, &w, &h);

    GList *mapping = poppler_page_get_link_mapping (page);
    gint n_links = g_list_length (mapping);
    GList *l;
    
    printf("PAGE: %d\n", page_num);
    for (l = mapping; l; l = g_list_next (l)) {
    	PopplerLinkMapping *lmapping = (PopplerLinkMapping*)l->data;
	   	switch (lmapping->action->type) {
	    	case POPPLER_ACTION_URI: {
	    		PopplerActionUri *auri = (PopplerActionUri*)lmapping->action;
	    		double x1 = lmapping->area.x1 / w;
	    		double y1 = 1.0 - (lmapping->area.y1 / h);
	    		double x2 = lmapping->area.x2 / w;
	    		double y2 = 1.0 - (lmapping->area.y2 / h);
	    		printf("LINK: %f %f %f %f URI: %s\n",
	    			x1, y2, x2 - x1, y1 - y2,
					auri->uri);
	    	}
	        	break;
    	}
    }
    poppler_page_free_link_mapping (mapping);
    g_object_unref (page);
}

int main(int argc, char *argv[]) {
    PopplerDocument *document;
    PopplerPage *page;
    GError *error;
    const char *pdf_file;
    
    gchar *absolute, *dir, *uri;
    int page_num, num_pages;
    char *tmpChar;

    if (argc < 2 && argc > 3) {
        printf ("Usage: pdftomapping input_file.pdf [page]\n");
        return 0;
    }

    pdf_file = argv[1];
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

	int start = 1, end = num_pages;
	if (argc >= 3) {
		start = end = atoi(argv[2]);
	}
	for (page_num = start; page_num <= end ;page_num++) {
	  page = poppler_document_get_page (document, page_num - 1);
	  if (page == NULL) {
		  printf("poppler fail: page not found\n");
		  return 1;
	  }
	  write_mapping(page_num, page);
	}

    return 0;
}
