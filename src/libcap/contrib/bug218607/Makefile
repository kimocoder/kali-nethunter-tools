topdir=$(shell pwd)/../..
include ../../Make.Rules

all: threadcpp

test: all
	./threadcpp

# This binary will only run from this location because we use an rpath
# to find the in-tree build of libpsx.so.
threadcpp: thread.cpp ../../libcap/libpsx.so
	g++ -I../../libcap -o $@ $< -Wl,-rpath,../../libcap -lpsx -lpthread

../../libcap/libpsx.so:
	$(MAKE) -C ../../libcap libpsx.so

clean:
	rm -f threadcpp *~
