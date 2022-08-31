CFLAGS=-O2 -Wall -g -I.

all: ecurcli spiFlashRead

ecur.o ecurcli.o:%.o:%.c ecur.h
	$(CC) $(CFLAGS) -c $<

ecurcli: ecurcli.o ecur.o
	$(CC) $(CFLAGS) -o $@ $^

spiFlashRead: spiFlashRead.o ecur.o
	$(CC) $(CFLAGS) -o $@ $^

clean:
	$(RM) ecur.o ecurcli spiFlashRead

.PHONY: clean
