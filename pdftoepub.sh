#!/bin/sh
./pdftoepub $1 $2
./tootf.pe $2/fonts/*.svg
rm $2/fonts/*.svg