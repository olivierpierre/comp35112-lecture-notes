SRCS=$(shell ls src/*.md)

all:
	mdbook build -d 

serve:
	google-chrome http://localhost:3000/ &
	mdbook serve

deploy:
	mdbook build -d ../website/lecture-notes

spellcheck:
	$(foreach f,$(SRCS), \
		aspell -l EN_GB -c $(f) -p ./../.aspell.txt;)