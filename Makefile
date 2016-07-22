.PHONY : all clean

all : guide.html

clean :
	rm -f guide.html

%.html : %.md template_head.html template_tail.html
	markdown_py $< -o html5 -x smarty -x toc | cat template_head.html - template_tail.html > $@
