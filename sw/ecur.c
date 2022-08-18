#include <stdio.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <inttypes.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>
#include <stdarg.h>

#include "ecur.h"

/* Ethercat EoE / UDP register access */

#define PROTO_VERSION 1

/* EoE size limit minus headers */
#define BUFSZ (1472 - 14 - 20 - 8)

#define SEQ_MSK 0xf

#define STATUS_SIZE sizeof(uint16_t)
#define HEADER_SIZE sizeof(uint16_t)

#define STATUS_ERR        0x8000
#define STATUS_NELMS_MSK  0x07ff

typedef enum EcurCmd { VER = 1, RDW = 2 } EcurCmd;

typedef enum EcurData { D8, D16, D32 } EcurData;

#define MAX_READERS 256

typedef struct EcurReader {
	EcurReadCallback    cb;
	void               *closure;
    union  {
		void      *vp;
		uint8_t   *d8p;
		uint16_t  *d16p;
		uint32_t  *d32p;
	}                   datp;
	unsigned            nelms;
	EcurData            type;
} EcurReader;

typedef struct EcurRec {
	int               sd;
	unsigned         seq;
	int              dbg;
	uint8_t          xbuf[BUFSZ];
	unsigned         xlen;
	uint8_t          rbuf[BUFSZ];
	unsigned         rlen;
	EcurReader       readers[MAX_READERS];
	unsigned         numReaders;
} *Ecur;

static void flushReaders(Ecur e, unsigned from, int err)
{
	while ( from < e->numReaders ) {
		if ( e->readers[from].cb ) {
			e->readers[from].cb( e->readers[from].datp.vp, err, e->readers[from].closure );
		}
		from++;
	}
	e->numReaders = 0;
}

static inline void ecurMkReqHdr(Ecur e, EcurCmd cmd)
{
	e->xbuf[0] = ( cmd << 4 ) | PROTO_VERSION;
	e->xbuf[1] = 0x00 | (e->seq & SEQ_MSK);
	e->xlen    = HEADER_SIZE;
	e->rlen    = HEADER_SIZE;
	e->seq     = (e->seq + 1) & SEQ_MSK;
	flushReaders( e, 0, ECUR_ERR_INTERNAL );
}


static int
ecurXfer(Ecur e)
{
int             retry;
int             put, got;
fd_set          fds;
struct timespec tout;
unsigned        xlen = e->xlen;

	e->xlen = 0;

	for ( retry = 0; retry < 3; retry++ ) {
		put = send( e->sd, e->xbuf, xlen, 0 );
		if ( put < 0 ) {
			perror("ecurXfer: send failed");
			return put;
		}
		FD_ZERO( &fds );
		FD_SET( e->sd, &fds );
		tout.tv_sec  = 1;
		tout.tv_nsec = 0;
		got = pselect( e->sd + 1, &fds, 0, 0, &tout, 0 );
		if ( got < 0 ) {
			perror("ecurXfer: select failed");
			return got;
		} else if( got > 0 ) {
			got = recv( e->sd, e->rbuf, sizeof(e->rbuf), 0 );
			if ( got < 0 ) {
				e->rlen = 0;
				perror("ecurXfer: recv failed");
			} else {
				e->rlen = got;
			}
			return got;
		}
	}
	return 0;
}

int
ecurPrint(Ecur e, int level, const char *fmt, ... )
{
va_list ap;
int     rv = 0;
	va_start( ap, fmt );
	if ( e->dbg > level ) {
		rv = vfprintf(stdout, fmt, ap);
	}
	va_end( ap );
	return rv;
}

void
ecurClose(Ecur e)
{
	if ( e ) {
		flushReaders( e, 0, ECUR_ERR_INTERNAL );
		if ( e->sd >= 0 ) {
			close( e->sd );
		}
		free( e );
	}
}

Ecur
ecurOpen(const char *destIP, unsigned destPort, int verbosity)
{
Ecur                e;
struct sockaddr_in  a;
int                 got;

	if ( (e = malloc( sizeof(*e) ) ) ) {

		e->seq            = 0;
		e->dbg            = verbosity;
		e->xlen           = 0;
		e->rlen           = 0;
		e->numReaders     = 0;

		a.sin_family      = AF_INET;
		a.sin_addr.s_addr = INADDR_ANY;
		a.sin_port        = 0;

		if ( ( e->sd = socket( AF_INET, SOCK_DGRAM, 0 ) ) < 0 ) {
			perror("ecurOpen(): Error creating socket");
			goto bail;
		}

		if ( bind(e->sd, (struct sockaddr*)&a, sizeof(a)) ) {
			perror("ecurOpen(): Unable to bind socket to local address");
			goto bail;
		}

		a.sin_addr.s_addr = inet_addr( destIP );
		a.sin_port        = htons( destPort );

		if ( connect( e->sd, (struct sockaddr*) &a, sizeof(a) ) ) {
			perror("ecurOpen(): Unable to connect UDP socket with destination");
			goto bail;
		}

		ecurMkReqHdr(e, VER);

		got = ecurXfer( e );
		if ( got > 1 ) {
			unsigned seq = e->rbuf[1] & SEQ_MSK;
			unsigned cmd = ( e->rbuf[0] >> 4 ) & 0xf;
			unsigned ver = ( e->rbuf[0] >> 0 ) & 0xf;
			ecurPrint(e, 0, "ecurOpen(): Version check reply: seq %d, cmd %d, version %d\n", seq, cmd, ver);
			if ( ver != PROTO_VERSION ) {
				fprintf( stderr,"ecurOpen() Error: Firmware expects protocol version %d, we use %d\n", ver, PROTO_VERSION );
				goto bail;
			}
		} else {
			fprintf(stderr, "ecurOpen() Error: no response to version check\n");
			goto bail;
		}
	} else {
		perror("ecurOpen malloc failed");
	}

	return e;

bail:
	ecurClose( e );
	return 0;
}

/* Lane Codes */
typedef enum EcurLaneCode {
	LC_B0 = 0, /* byte 0 (bits  7 ..  0 of double-word) */
	LC_B1 = 1, /* byte 1 (bits 15 ..  8 of double-word) */
	LC_B2 = 2, /* byte 2 (bits 23 .. 16 of double-word) */
	LC_B3 = 3, /* byte 3 (bits 31 .. 24 of double-word) */
	LC_W0 = 4, /* word   (lower 16-bit  of double-word) */
	LC_W1 = 5, /* word   (upper 16-bit  of double-word) */
	LC_DW = 6  /* double-word                           */
} EcurLaneCode;

#define OP_READ (1<<31)
#define OP_WRITE 0

static int
ecurQOp(
	Ecur                e,
	uint32_t            wordAddr,
	EcurLaneCode        laneCode,
	void               *data,
	unsigned            burstCnt,
    int                 rdnwr,
	EcurReadCallback    cb,
	void               *closure)
{
unsigned reqSz, datSz, repSz;
int         i,j;
uint16_t    d16;
uint32_t    d32;
EcurReader *reader;

	if ( burstCnt > 256 || burstCnt < 1 ) {
		fprintf(stderr, "ecurQOp() Error: invalid burst count\n");
		return ECUR_ERR_INVALID_COUNT;
	}
	if ( ( wordAddr & 0xfff00000 ) != 0 ) {
		fprintf(stderr, "ecurQOp() Error: word address not supported by protocol (too big)\n");
		return ECUR_ERR_INVALID_ADDR;
	}

	reqSz = 4;
    repSz = 0;
   	datSz = (burstCnt << (LC_DW == laneCode ? 2 : 1 ));

	if ( ! rdnwr ) {
		reqSz += datSz;
	} else {
		repSz += datSz;
	}

	if ( 0 == e->xlen ) {
		ecurMkReqHdr(e, RDW);
	}

	if ( e->xlen + reqSz > sizeof( e->xbuf ) ) {
		fprintf(stderr, "ecurQOp() Error: request does not fit in buffer\n");
		return ECUR_ERR_NOSPACE_REQ;
	}

	if ( e->rlen + repSz > sizeof( e->rbuf ) - STATUS_SIZE ) {
		fprintf(stderr, "ecurQOp() Error: reply would not fit in buffer\n");
		return ECUR_ERR_NOSPACE_REP;
	}

	wordAddr = (laneCode << 28) | ( (burstCnt - 1) << 20 ) | wordAddr;
	if ( rdnwr != OP_WRITE ) {
		wordAddr |= OP_READ;
	}
	for ( i = 0; i < sizeof( wordAddr ); i++ ) {
		e->xbuf[e->xlen] = (wordAddr & 0xff);
		e->xlen++;
		wordAddr         = (wordAddr >> 8);
	}
	if ( rdnwr ) {
		if ( MAX_READERS == e->numReaders ) {
			fprintf(stderr, "ecurQOp() Error: reply would not fit in buffer\n");
			return ECUR_ERR_NOSPACE_REP;
		}
		reader          = & e->readers[e->numReaders];
		reader->cb      = cb;
		reader->closure = closure;
		reader->datp.vp = data;
		reader->nelms   = burstCnt;
		reader->type    = ( laneCode <= LC_B3 ? D8 : ( laneCode <= LC_W1 ? D16 : D32 ) );
		e->rlen        += repSz;
		e->numReaders++;
	} else {
		switch ( laneCode ) {
			case LC_B0:
			case LC_B1:
			case LC_B2:
			case LC_B3:
				for ( i = 0; i < burstCnt; i++ ) {
					e->xbuf[e->xlen] = ((uint8_t*) data)[i];
					e->xlen         += 2;
				}
				break;

			case LC_W0:
			case LC_W1:
				for ( i = 0; i < burstCnt; i++ ) {
					d16 = ((uint16_t*) data)[i];
					e->xbuf[e->xlen] = (d16 >> 0) & 0xff;
					e->xlen++;
					e->xbuf[e->xlen] = (d16 >> 8) & 0xff;
					e->xlen++;
				}
				break;

			case LC_DW:
				for ( i = 0; i < burstCnt; i++ ) {
					d32 = ((uint32_t*) data)[i];
					for ( j = 0; j < sizeof( d32 ); j++ ) {
						e->xbuf[e->xlen] = (d32 & 0xff);
						e->xlen++;
						d32              = (d32 >> 8);
					}
				}
				break;
		}
	}
	return 0;
}

static unsigned
processReader(Ecur e, EcurReader *r, unsigned ridx, unsigned len)
{
unsigned i;
unsigned nelms;

	nelms = ( len >> (D32 == r->type ? 2 : 1 ) );

	if ( nelms > r->nelms ) {
		nelms = r->nelms;
	}

	switch ( r->type ) {
		case D8:
			for ( i = 0; i < nelms; i++ ) {
				r->datp.d8p[i] = e->rbuf[ridx];
				ridx+=2;
			}
			break;
		case D16:
			for ( i = 0; i < nelms; i++ ) {
				r->datp.d16p[i] = ( e->rbuf[ridx+1] << 8 ) | e->rbuf[ridx];
				ridx+=2;
			}
			break;
		case D32:
			for ( i = 0; i < nelms; i++ ) {
				r->datp.d32p[i] = ( e->rbuf[ridx+3] << 24 ) | ( e->rbuf[ridx+2] << 16 ) | ( e->rbuf[ridx+1] << 8 ) | e->rbuf[ridx];
				ridx+=4;
			}
			break;
	}

	if ( r->cb ) {
		r->cb( r->datp.vp, nelms, r->closure );
	}

	return ridx;
}

static int
ecurProcessReply(Ecur e)
{
uint16_t status;
unsigned nelmsOK;
unsigned rdr  = 0;
int      rval = ECUR_ERR_INVALID_REP;
unsigned ridx, eidx;

	if ( e->rlen < HEADER_SIZE + STATUS_SIZE ) {
		fprintf(stderr, "ecurProcessReply() Error: not enough data received\n");
		flushReaders( e, rdr, rval );
		goto bail;
	}

	status = ( e->rbuf[e->rlen - STATUS_SIZE + 1] << 8 ) | e->rbuf[e->rlen - STATUS_SIZE];

	if ( ( status & STATUS_ERR ) ) {
		ecurPrint( e, 0, "ecurProcessReply() -- errors were encountered on the target\n");
		goto bail;
	}

	nelmsOK        = ( status & STATUS_NELMS_MSK );
	rdr            = 0;
	ridx           = HEADER_SIZE;
	eidx           = e->rlen - STATUS_SIZE;

	while ( ridx < eidx && rdr < e->numReaders ) {
		ridx = processReader( e, & e->readers[rdr], ridx, eidx - ridx );
		rdr++;
	}
	if ( rdr < e->numReaders ) {
		fprintf(stderr, "ecurProcessReply(): warning -- not all readers could be satisfied due to errors\n");
	}
	if ( ridx < eidx ) {
		fprintf(stderr, "ecurProcessReply(): error -- more data than expected\n");
		goto bail;
	}

	rval = nelmsOK;

bail:
	flushReaders( e, rdr, rval );
	return rval;
}

int
ecurExecute( Ecur e )
{
	if ( ecurXfer( e ) <= 0 ) {
		fprintf(stderr, "ecurExecute() Error -- UDP transfer failed\n");
		flushReaders( e, 0, ECUR_ERR_IO );
		return ECUR_ERR_IO;
	}
	return ecurProcessReply( e );
}

int ecurQRead8(Ecur e, uint32_t addr, uint8_t *data, unsigned n, EcurReadCallback cb, void *closure)
{
EcurLaneCode lc;
	switch ( addr & 3 ) {
		case 0: lc = LC_B0; break;
		case 1: lc = LC_B1; break;
		case 2: lc = LC_B2; break;
		case 3: lc = LC_B3; break;
	}
	return ecurQOp( e, addr >> 2, lc, (void*)data, n, OP_READ, cb, closure );
}

int ecurQRead16(Ecur e, uint32_t addr, uint16_t *data, unsigned n, EcurReadCallback cb, void *closure)
{
EcurLaneCode lc;
	switch ( addr & 3 ) {
		case 0: lc = LC_W0; break;
		case 2: lc = LC_W1; break;
		default:
			fprintf(stderr, "ecurQRead16() Error: misaligned word address\n");
			return ECUR_ERR_INVALID_ADDR;
	}
	return ecurQOp( e, addr >> 2, lc, (void*)data, n, OP_READ, cb, closure );
}

int ecurQRead32(Ecur e, uint32_t addr, uint32_t *data, unsigned n, EcurReadCallback cb, void *closure)
{
	if ( addr & 3 ) {
		fprintf(stderr, "ecurQRead32() Error: misaligned word address\n");
		return ECUR_ERR_INVALID_ADDR;
	}
	return ecurQOp( e, addr >> 2, LC_DW, (void*)data, n, OP_READ, cb, closure );
}

int ecurQWrite8 (Ecur e, uint32_t addr, uint8_t *writeData, unsigned n)
{
EcurLaneCode lc;
	switch ( addr & 3 ) {
		case 0: lc = LC_B0; break;
		case 1: lc = LC_B1; break;
		case 2: lc = LC_B2; break;
		case 3: lc = LC_B3; break;
	}
	return ecurQOp( e, addr >> 2, lc, (void*) writeData, n, OP_WRITE, 0, 0 );
}

int ecurQWrite16(Ecur e, uint32_t addr, uint16_t *writeData, unsigned n)
{
EcurLaneCode lc;
	switch ( addr & 3 ) {
		case 0: lc = LC_W0; break;
		case 2: lc = LC_W1; break;
		default:
			fprintf(stderr, "ecurQWrite16() Error: misaligned word address\n");
			return ECUR_ERR_INVALID_ADDR;
	}
	return ecurQOp( e, addr >> 2, lc, (void*) writeData, n, OP_WRITE, 0, 0 );
}

int ecurQWrite32(Ecur e, uint32_t addr, uint32_t *writeData, unsigned n)
{
	if ( addr & 3 ) {
		fprintf(stderr, "ecurQWrite32() Error: misaligned word address\n");
		return ECUR_ERR_INVALID_ADDR;
	}
	return ecurQOp( e, addr >> 2, LC_DW, (void*) writeData, n, OP_WRITE, 0, 0 );
}

static void cbGetN(void *addr, int n, void *c)
{
	*(int*)c = n;
}

int
ecurRead8(Ecur e, uint32_t addr, uint8_t *data, unsigned n)
{
int got;
int st;
	if ( (st = ecurQRead8( e, addr, data, n, cbGetN, (void*)&got )) ) {
		fprintf(stderr, "ecurRead8() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}

int
ecurRead16(Ecur e, uint32_t addr, uint16_t *data, unsigned n)
{
int got;
int st;
	if ( (st = ecurQRead16( e, addr, data, n, cbGetN, (void*)&got ) )) {
		fprintf(stderr, "ecurRead16() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}


int
ecurRead32(Ecur e, uint32_t addr, uint32_t *data, unsigned n)
{
int got;
int st;
	if ( (st = ecurQRead32( e, addr, data, n, cbGetN, (void*)&got )) ) {
		fprintf(stderr, "ecurRead32() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}

int
ecurWrite8(Ecur e, uint32_t addr, uint8_t *data, unsigned n)
{
int st;
	if ( (st = ecurQWrite8( e, addr, data, n )) ) {
		fprintf(stderr, "ecurWrite8() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}

int
ecurWrite16(Ecur e, uint32_t addr, uint16_t *data, unsigned n)
{
int st;
	if ( (st = ecurQWrite16( e, addr, data, n )) ) {
		fprintf(stderr, "ecurWrite16() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}


int
ecurWrite32(Ecur e, uint32_t addr, uint32_t *data, unsigned n)
{
int st;
	if ( (st = ecurQWrite32( e, addr, data, n )) ) {
		fprintf(stderr, "ecurWrite32() Error -- failed to queue request\n");
		return st;
	}
	return ecurExecute( e );
}


static const char *statLbl[] = {
	"mbxPkts",
	"rxpPDOs",
	"eoeFrgs",
	"eoeFrms",
	"eoeDrps",
	"nMacDrp",
	"nShtDrp",
	"nArpHdr",
	"nIP4Hdr",
	"nUnkHdr",
	"nArpDrp",
	"nArpReq",
	"nIP4Drp",
	"nPinReq",
	"nUdpReq",
	"nUnkIP4",
	"nIP4Mis",
	"nPinDrp",
	"nPinHdr",
	"nUdpMis",
	"nUdpHdr",
	"nPktFwd",
};

void
ecurPrintNetStats(Ecur e, uint32_t locbas)
{
uint32_t            stat[22];
int                 got;
int                 i;
uint32_t            a;

	a = 0 | locbas;
	if ( (got = ecurRead32( e, a, stat, sizeof(stat)/sizeof(stat[0]))) < 0 ) {
		printf("Error: ecurRead32() for statistics failed\n");
	}
	for ( i = 0; i < got; i++ ) {
		printf("%s: %5" PRId32 "\n", statLbl[i], stat[i]);
	}
}
