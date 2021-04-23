OUT=GT-prog2021
.SUFFIXES: .tex .pdf

FILES=$(shell ls -1 *.tex)

all: $(OUT).pdf

$(OUT).pdf:	$(FILES)
	pdflatex -synctex=1 -shell-escape -interaction=nonstopmode $(OUT).tex

clean:
	$(RM) *.synctex.gz *.log *.out *.aux

.PHONY: debs
debs:
	sudo apt install texlive-latex-extra  texlive-lang-cyrillic  
