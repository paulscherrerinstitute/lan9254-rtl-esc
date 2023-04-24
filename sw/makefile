CFLAGS=-O2 -Wall -g -I.
RANLIB=ranlib

all: libecur.a

ecur.o:%.o:%.c ecur.h
	$(CC) $(CFLAGS) -c $<

libecur.a: ecur.o
	$(AR) r $@ $^
	$(RANLIB) $@

clean:
	$(RM) ecur.o libecur.a

.PHONY: clean
