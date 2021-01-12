
# gcc -O2 -c -fPIC -o dht11.o dht11.c && gcc -O2 -fPIC -shared -o libdht11.so dht11.o 

all: libdht11.so compiled/dht11_rkt.zo

dht11.o: dht11.c
	gcc -g -O2 -c -fPIC -o dht11.o dht11.c

libdht11.so: dht11.o
	gcc -O2 -fPIC -shared -o libdht11.so dht11.o

compiled/dht11_rkt.zo: dht11.rkt
	raco make -v dht11.rkt 
