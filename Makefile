
# gcc -O2 -c -fPIC -o dht11.o dht11.c && gcc -O2 -fPIC -shared -o libdht11.so dht11.o

all: libdht11.so compiled/main_rkt.zo

dht11.o: dht11.c
	gcc -g -O2 -c -fPIC -o dht11.o dht11.c

libdht11.so: dht11.o
	gcc -O2 -fPIC -shared -o libdht11.so dht11.o

compiled/main_rkt.zo: main.rkt
	raco make -v main.rkt
