.PHONY : all clean

PANDOC=pandoc
PANDOC_ARGS=-s --toc

PAGES=00-frontmatter.md 99-A-debian.md
TARGETS=guide.html guide.pdf

all : ${TARGETS}

clean :
	rm -f ${TARGETS}

guide.% : ${PAGES} templates/%.template
	${PANDOC} -f markdown -o $@ ${PAGES} --template templates/$*.template ${PANDOC_ARGS}
