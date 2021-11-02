CFLAGS=-O2 -Wall

all: ecurcli

ecur.o ecurcli.o:%.o:%.c ecur.h
	$(CC) $(CFLAGS) -c $<

ecurcli: ecurcli.o ecur.o
	$(CC) $(CFLAGS) -o $@ $^

clean:
	$(RM) ecur.o ecurcli

.PHONY: clean
