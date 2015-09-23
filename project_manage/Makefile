all: setproject getproject

project.o: project.c project.h
	gcc -Wall -Werror -c -g project.c -o project.o

setproject: setproject.c project.o
	gcc -Wall -Werror -g project.o setproject.c -o setproject

getproject: getproject.c project.o
	gcc -Wall -Werror -g project.o getproject.c -o getproject

clean:
	rm *.o -f
	rm getproject setproject -f
