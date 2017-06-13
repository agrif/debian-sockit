SOURCES=readme.tex sdcard.tex

LATEX=xelatex -shell-escape

.PHONY : all clean example

all : ${SOURCES:.tex=.pdf}

clean :
	rm -f ${SOURCES:.tex=.pdf}
	rm -rf $(addprefix _minted-,${SOURCES:.tex=})
	rm -f ${SOURCES:.tex=.aux}
	rm -f ${SOURCES:.tex=.log}
	rm -f ${SOURCES:.tex=.out}
	rm -f ${SOURCES:.tex=Notes.bib}
	rm -f example.zip

example :
	find example -path '*/.*' -prune -o -type f -print | zip example.zip -@

%.pdf : %.tex sockitguide.cls
	${LATEX} $*
	${LATEX} $*
