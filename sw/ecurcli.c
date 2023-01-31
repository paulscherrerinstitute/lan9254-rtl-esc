#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <inttypes.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <ctype.h>

#include "ecur.h"

static int getYesNo(const char *msg)
{
struct termios orig;
struct termios tmp;
int            ans     = 'N';
int            restore = -1;


	printf("%s y/[n]?", msg);
    fflush(stdout);

	cfmakeraw( &tmp );
	tmp.c_cc[VMIN] = 1;

	if (     isatty( 1 )
	      && 0 == (restore = tcgetattr( 1, &orig ))
	      && 0 == tcsetattr( 1, TCSANOW, &tmp ) ) {

		if ( 1 != read(1, &ans, 1) ) {
			ans = 'N';
		}
	} else {
		ans = getchar();
	}
	if ( 0 == restore ) {
		tcsetattr( 1, TCSANOW, &orig );
	}
	printf("\n");
	return toupper( ans );
}

static void
p32(void *p, int n, void *c)
{
int i;
	if ( n <= 0 ) {
		printf("Error: Read returned nothing\n");
	} else {
		for ( i = 0; i < n; i++ ) {
			printf("Read: 0x%08" PRIx32 "\n", ((uint32_t*)p)[i]);
		}
	}
}

static int
ecurTest(Ecur e, uint32_t hbibas)
{
uint32_t            d32a[4];
uint32_t            d32;
uint16_t            d16;
uint8_t             d08;
int                 i,got;
int                 failed = 0;
uint32_t            a;

	a = 0x3064 | hbibas;

	got = ecurRead32( e, a, &d32, 1 );
	if ( got < 0 ) {
		fprintf(stderr, "ecurRead32() failed\n");
		failed++;
	} else {
		printf("Read result: 0x%08" PRIx32 "\n", d32);
	}
	if ( d32 != 0x87654321 ) {
		fprintf(stderr, "32-bit read FAILED\n");
		failed++;
	}

	got = ecurRead16( e, a, &d16, 1 );
	if ( got < 0 ) {
		fprintf(stderr, "ecurRead16() failed\n");
		failed++;
	} else {
		printf("Read result: 0x%04" PRIx16 "\n", d16);
	}

	if ( d16 != 0x4321 ) {
		fprintf(stderr, "16-bit read (low) FAILED\n");
		failed++;
	}

	got = ecurRead16( e, a+2, &d16, 1 );
	if ( got < 0 ) {
		fprintf(stderr, "ecurRead16() failed\n");
		failed++;
	} else {
		printf("Read result: 0x%04" PRIx16 "\n", d16);
	}

	if ( d16 != 0x8765 ) {
		fprintf(stderr, "16-bit read (hi) FAILED\n");
		failed++;
	}

	for ( i = 0; i < 4; i++ ) {
		uint8_t exp[] = { 0x21, 0x43, 0x65, 0x87 };

		got = ecurRead8( e, a+i, &d08, 1 );
		if ( got < 0 ) {
			fprintf(stderr, "ecurRead8() failed\n");
			failed++;
		} else {
			printf("Read result: 0x%02" PRIx8 "\n", d08);
		}
		if ( d08 != exp[i] ) {
			fprintf(stderr, "8-bit read [%i] FAILED\n", i);
			failed++;
		}
	}

	a   = 0xf80 | hbibas;
	d08 = 0x01;

	for ( i = 0; i < 4; i++ ) {
		d08++;
		if ( ecurQWrite8( e, a + i, &d08, 1 ) ) {
			fprintf(stderr, "ecurQWrite8() failed\n");
			failed++;
		}
	}
	d16 = 0xaabb;
	if ( ecurQWrite16( e, a + 4, &d16, 1 ) ) {
		failed++;
		fprintf(stderr, "ecurQWrite16() failed\n");
	}
	d16 = 0xccdd;
	if ( ecurQWrite16( e, a + 6, &d16, 1 ) ) {
		failed++;
		fprintf(stderr, "ecurQWrite16() failed\n");
	}
	d32 = 0xdeadbeef;
	if ( ecurQWrite32( e, a + 8, &d32, 1 ) ) {
		failed++;
		fprintf(stderr, "ecurQWrite16() failed\n");
	}
	if ( ecurQRead32( e, a, d32a + 0, 3, p32, 0) ) {
		fprintf(stderr, "ecurQRead32() failed\n");
	}
	if ( ecurExecute( e ) < 0 ) {
		printf("Error: ecurExecute() failed\n");
		failed++;
	}
	if ( d32a[0] != 0x05040302 ) {
		fprintf(stderr, "8-bit write / 32-bit array readback failed\n");
		failed++;
	}
	if ( d32a[1] != 0xccddaabb ) {
		fprintf(stderr, "16-bit write / 32-bit array readback failed\n");
		failed++;
	}
	if ( d32a[2] != 0xdeadbeef ) {
		fprintf(stderr, "32-bit write / 32-bit array readback failed\n");
		failed++;
	}

	if ( ! failed ) {
		printf("Test PASSED\n");
	} else {
		fprintf(stderr, "Test FAILED (%d failures)\n", failed);
	}

	return failed;
}

static void usage(const char *nm)
{
	fprintf(stderr, "usage: %s [-hstVP] [-a <dst_ip>] [-b base] [-w <width>] [-e <evr_reg>[=<value>]]\n", nm);
	fprintf(stderr, "       -h                       : this message\n");
	fprintf(stderr, "       -t                       : run basic test (connection to target required)\n");
	fprintf(stderr, "       -s                       : print networking stats for target\n");
	fprintf(stderr, "       -v                       : increase verbosity\n");
	fprintf(stderr, "       -V                       : show version info\n");
	fprintf(stderr, "       -P                       : power-cycle the target\n");
	fprintf(stderr, "       -a dst_ip                : set target ip (dot notation). Can also be defined by\n");
	fprintf(stderr, "                                  the 'ECUR_TARGET_IP' environment variable\n");
	fprintf(stderr, "       -e <reg>[=<val>]         : EVR register access\n");
	fprintf(stderr, "       -i <ireg>[=<val>]        : EVR indirect register access\n");
	fprintf(stderr, "       -r <reg>[=<val>]         : any register access\n");
    fprintf(stderr, "                                  reg: [<range>@]<offset\n");
    fprintf(stderr, "                                  range selects 0..7 sub-devices\n");
    fprintf(stderr, "                                  (at base-addr (range<<19)).\n");
    fprintf(stderr, "       -b <base>                : explicitly specify a base-address (added to -m or -r value)\n");
	fprintf(stderr, "       -m <mem>[=<val>]         : like 'reg' but uses byte-addresses;\n");
	fprintf(stderr, "                                  note that they still must be word-\n");
	fprintf(stderr, "                                  aligned; this is a convenience option.\n");
	fprintf(stderr, "       -w <width>               : width (1,2,4); must be used with -m\n");
}

static int
doReg(Ecur e, uint32_t a, uint32_t v, int doWrite, unsigned w)
{
uint16_t v16 = (uint16_t)v;
uint8_t  v8  = (uint8_t) v;
int      st;
const char *bitws = (1 == w ? "8" : (2 == w ? "16" : "32"));

	if ( (a & (w - 1)) ) {
		fprintf(stderr, "Error: address (0x%x) not aligned to width (%d)\n", a, w);
		return -1;
	}
	if ( doWrite ) {
		printf("Writing 0x%08" PRIx32 " to 0x%08" PRIx32 "\n", v, a);
		switch ( w ) {
			case 1:   st = ecurWrite8 ( e, a, &v8,  1 ); break;
			case 2:   st = ecurWrite16( e, a, &v16, 1 ); break;
			default:  st = ecurWrite32( e, a, &v,   1 ); break;
		}
		if ( st < 0 ) {
			fprintf(stderr, "Error: ecurWrite%s() failed (address 0x%08" PRIx32 ")\n", bitws, a);
			return -1;
		}
	} else {
		switch ( w ) {
			case 1:   st = ecurRead8 ( e, a, &v8,  1 ); v = v8;  break;
			case 2:   st = ecurRead16( e, a, &v16, 1 ); v = v16; break;
			default:  st = ecurRead32( e, a, &v,   1 );          break;
		}
		if ( st < 1 ) {
			fprintf(stderr, "Error: ecurRead%s() failed (address 0x%08" PRIx32 ")\n", bitws, a);
			return -1;
		} else {
			printf("0x%08" PRIx32 ": 0x%08" PRIx32 " (%" PRId32 ")\n", a, v, v);
		}
	}
	return 0;
}

#define IREG_A ((0xf<<1) | 0)
#define IREG_D ((0xf<<1) | 1)

static int
reg(Ecur e, const char *s, uint32_t bas, int ireg, int shft, int width)
{
char                *ep = 0;
unsigned long       reg;
unsigned long       val     = 0; /* keep compiler happy */
int                 haveVal = 0;
uint32_t            a;
const char         *at;
const char         *op = s;

    if ( (at = strchr( s, '@' )) ) {
        bas = strtoul( s, &ep, 0);
		if ( ep != at ) {
			fprintf(stderr, "Error: invalid range (unable to scan)\n");
			return -1;
		}
		if ( bas >= 8 ) {
			fprintf(stderr, "Error: invalid range (must be 0..7)\n");
			return -1;
		}
		bas <<= 19;

		op = at + 1;
	}

	reg = strtoul(op, &ep, 0);
	if ( ep == op ) {
		fprintf(stderr, "Error: invalid register (unable to scan)\n");
		return -1;
	}
	while ( ' ' == *ep ) ep++;
	if ( *ep ) {
		if ( '=' != *ep ) {
			fprintf(stderr, "Error: invalid assigment ('=' expected)\n");
			return -1;
		}
		op = ep + 1;
		val = strtoul(op, &ep, 0);
		if ( ep == op ) {
			fprintf(stderr, "Error: invalid register value (unable to scan)\n");
			return -1;
		}
		haveVal = 1;
	}

	if ( ireg ) {
        width = 4;
		a = bas | (IREG_A << shft);
        if ( doReg(e, a, reg, 1, width) ) {
			return -1;
		}
		a = bas | (IREG_D << shft);
	} else {
		a = bas | (reg << shft);
	}
    return doReg( e, a, val, haveVal, width );
}

int
main(int argc, char **argv)
{
char               *optstr        = "ha:b:tsve:r:i:m:VPw:";
int                 rval          = 1;
const char         *dip           = "10.10.10.20";
uint16_t            dprt          = 4096;
Ecur                e             = 0;
uint32_t            hbibas        = (7<<19);
uint32_t            escbas        = (6<<19);
uint32_t            locbas        = (3<<19);
uint32_t            evrbas        = (0<<19);
uint32_t            regbas        = (0<<19);
uint32_t            cfgbas        = (0<<19) | (1<<17);
int                 testFailed    = 0;
int                 printNetStats = 0;
int                 verbose       = 0;
int                 printVersion  = 0;
uint32_t           *u32_p         = 0;
uint32_t            val;
uint16_t            val16;
int                 st;
int                 opt;
const char         *at, *arg;
uint32_t            width         = 4;
int                 powerCycle    = 0;

	if ( (arg = getenv("ECUR_TARGET_IP")) ) {
		dip = arg;
	}

	while ( (opt = getopt(argc, argv, optstr)) > 0 ) {
        u32_p = 0;
		switch ( opt ) {

			case 'h':
				rval = 0;
			default:
				usage( argv[0] );
				goto bail;

			case 'a':
				dip = optarg;
				break;

			case 't':
				testFailed = 1;
				break;

			case 's':
				printNetStats = 1;
				break;

			case 'v':
				verbose++;
				break;

            case 'b':
				u32_p = &regbas;
				break;

            case 'w':
                u32_p = &width;
                break;

			case 'V':
				printVersion = 1;
				break;

			case 'P':
				powerCycle = 1;
				break;

			case 'm': /* deal with that later */
			case 'r': /* deal with that later */
			case 'e': /* deal with that later */
			case 'i': /* deal with that later */
				break;
		}
		if ( u32_p && ( 1 != sscanf(optarg, "%" SCNi32, u32_p) ) ) {
			fprintf(stderr, "Error: Unable to scan argument to option %d\n", opt);
			goto bail;
		}
		switch ( width ) {
			case 1: case 2: case 4:
				break;
			default:
				fprintf(stderr, "-w argument must be 1,2 or 4\n");
				goto bail;
        }
	}

	if ( ! (e = ecurOpen( dip, dprt, verbose )) ) {
		fprintf(stderr, "Unable to connect to Firmware at %s:%" PRIu16 "\n", dip, dprt);
		goto bail;
	}

	if ( testFailed ) {
		testFailed = ecurTest( e, hbibas );
	}

	if ( powerCycle ) {
		if ( 'Y' == getYesNo("About to power-cycle the target; proceed") ) {
			printf("<connection might be lost; ignore errors>\n");
			val16 = 0xdead;
			ecurWrite16( e, locbas + 0x8, &val16, 1 );
		}
		/* on success we might never get here */
		rval = 0;
		goto bail;
	}

	if ( printNetStats ) {
		ecurPrintNetStats( e, escbas );
	}

	if ( printVersion ) {
		st = ecurRead32( e, cfgbas + 0x10, &val, 1 );
		if ( st < 0 ) {
			fprintf(stderr, "ecurRead32() failed\n");
		} else {
			printf("Target Firmware Git Hash: 0x%08" PRIx32 "\n", val);
		}
	}

	optind = 1;
	while ( (opt = getopt( argc, argv, optstr )) > 0 ) {

		arg = optarg;

		switch ( opt ) {
			default:
				break;
            case 'i':
			case 'e':
				if ( (at = strchr(optarg, '@')) ) {
					fprintf(stderr, "Warning: range ('@') ignored for EVR access!\n");
					arg = at + 1;
				}
				regbas = evrbas;
				/* fall thru */
			case 'm':
			case 'r':
				if ( reg( e, arg, regbas, (opt == 'i'), (opt == 'm' ? 0 : (1 == width ? 0 : ( 2 == width ? 1 : 2))), width) ) {
					goto bail;
				}
				break;
		}
	}

	if ( ! testFailed ) {
		rval = 0;
	}

bail:
	if ( e ) {
		ecurClose( e );
	}
	return rval;
}
