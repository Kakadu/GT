NAME=vkr

.PHONY: $(NAME).pdf clean

all: $(NAME).pdf

FILES_TEX=$(NAME).tex intro.tex related.tex

$(NAME).pdf: $(FILES_TEX)
	xelatex $<
	bibtex $(NAME).aux
	xelatex $<
	xelatex $<

clean:
	$(RM) *.bak *.out

aspell:
	aspell --mode=tex -l ru --home-dir=. --personal=personal_dict.txt  -c $(FILE)

