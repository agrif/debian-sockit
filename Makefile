SOURCES=sockit-guide.tex appendix-sdcard.tex

LATEX=xelatex -shell-escape

.PHONY : all clean example extras

all : ${SOURCES:.tex=.pdf}

clean :
	rm -f ${SOURCES:.tex=.pdf}
	rm -rf $(addprefix _minted-,${SOURCES:.tex=})
	rm -f ${SOURCES:.tex=.aux}
	rm -f ${SOURCES:.tex=.log}
	rm -f ${SOURCES:.tex=.out}
	rm -f ${SOURCES:.tex=Notes.bib}
	rm -f example.zip extras.zip

example :
	find example -path '*/.*' -prune -o -type f -print | zip example.zip -@

extras :
	find extras -path '*/.*' -prune -o -type f -print | zip extras.zip -@

%.pdf : %.tex sockitguide.cls
	${LATEX} $*
	${LATEX} $*
