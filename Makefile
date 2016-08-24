.PHONY : all clean

PANDOC=pandoc
PANDOC_ARGS=-s -S --self-contained --toc -c templates/style.css

PAGES=pages/00-frontmatter.md pages/99-A-debian.md
TARGETS=guide.html guide.pdf guide.md guide.rtf

all : ${TARGETS}

clean :
	rm -f ${TARGETS}

guide.% : ${PAGES}
	${PANDOC} -f markdown -o $@ ${PAGES} ${PANDOC_ARGS}
