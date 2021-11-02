#include <stdio.h>
#include <getopt.h>
#include <inttypes.h>
#include <errno.h>
#include <stdlib.h>

#include "ecur.h"

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
	fprintf(stderr, "usage: %s [-hst] [-a <dst_ip>]\n", nm);
	fprintf(stderr, "       -h            : this message\n");
	fprintf(stderr, "       -t            : run basic test (connection to target required)\n");
	fprintf(stderr, "       -s            : print networking stats for target\n");
	fprintf(stderr, "       -a dst_ip     : set target ip (dot notation)\n");
}

int
main(int argc, char **argv)
{
int                 rval          = 1;
const char         *dip           = "10.10.10.10";
uint16_t            dprt          = 4096;
Ecur                e             = 0;
uint32_t            hbibas        = (7<<19);
uint32_t            locbas        = (6<<19);
int                 testFailed    = 0;
int                 printNetStats = 0;
int                 opt;

	while ( (opt = getopt(argc, argv, "ha:ts")) > 0 ) {
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
		}
	}

	if ( ! (e = ecurOpen( dip, dprt, 1 )) ) {
		fprintf(stderr, "Unable to connect to Firmware\n");
		goto bail;
	}

	if ( testFailed ) {
		testFailed = ecurTest( e, hbibas );
	}

	if ( printNetStats ) {
		ecurPrintNetStats( e, locbas );
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
