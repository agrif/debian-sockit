SOURCES=readme.tex sdcard.tex

LATEX=xelatex -shell-escape

.PHONY : all clean

all : ${SOURCES:.tex=.pdf}

clean :
	rm -f ${SOURCES:.tex=.pdf}
	rm -rf $(addprefix _minted-,${SOURCES:.tex=})
	rm -f ${SOURCES:.tex=.aux}
	rm -f ${SOURCES:.tex=.log}
	rm -f ${SOURCES:.tex=.out}
	rm -f ${SOURCES:.tex=Notes.bib}

%.pdf : %.tex sockitguide.cls
	${LATEX} $*
	${LATEX} $*
