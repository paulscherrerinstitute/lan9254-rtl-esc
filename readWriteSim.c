#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

#undef  DEBUG

#define STD_LOGIC_1 3
#define STD_LOGIC_0 2

#define MAP_LEN 0xc000

typedef struct AxiHbiRec {
	char              *map;
	volatile uint8_t  *a8;
	volatile uint16_t *a16;
	volatile uint32_t *a32;
} *AxiHbi;


void   axiHbiClose(AxiHbi p)
{
	if ( p ) {
		if ( MAP_FAILED != p->map ) {
			munmap( p->map, MAP_LEN );
		}
		free( p );
	}
}

AxiHbi axiHbiOpen(const char *devn, off_t base, bool fatal)
{
int     fd  = -1;
AxiHbi  rv  = 0;

	if ( ! (rv = (AxiHbi)malloc(sizeof( *rv ) )) ) {
		perror("axiHbiOpen(): No memory");
		goto bail;
	}
	rv->map = (char*)MAP_FAILED;

	if ( (fd = open( devn, O_RDWR ) ) < 0 ) {
		perror("axiHbiOpen(): Unable to open device");
		goto bail;
	}

	rv->map = (char*)mmap( 0, MAP_LEN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base );

	if ( MAP_FAILED == (void*)rv->map ) {
		perror("axiHbiOpen(): mmap() failed");
	}

	close( fd );

	rv->a32 = (volatile uint32_t*) rv->map;
	rv->a16 = (volatile uint16_t*) (rv->map + 0x4000);
	rv->a8  = (volatile uint8_t *) (rv->map + 0x8000);

	return rv;

bail:
	if ( fd >= 0 ) {
		close( fd );
	}
	axiHbiClose( rv );
	if ( fatal ) {
		abort();
	}
	return 0;
}

static AxiHbi dev = axiHbiOpen( "/dev/mem", 0x40c00000, true );

extern "C" {

void readWrite_C(uint32_t addr, uint8_t rdnwr, uint32_t *d_p, uint32_t len)
{
uint32_t d;
int      i;

	if ( 0 == len ) {
		return;
	}

	if ( addr >= 0x4000 ) {
		printf("readWrite_C(): BAD ADDRESS 0x%08" PRIx32 "\n", addr);
		abort();
	}

	if ( len > 4 ) {
		printf("readWrite_C(): BAD LENGTH (must be < 4) %" PRId32 "\n", len);
		abort();
	}

	if ( ( 2 == len && (addr & 1) ) || (4 == len && (addr & 3)) ) {
		printf("readWrite_C(): misaligned length (%" PRId32 ") / addr (0x%08" PRIx32 ")\n", len, addr);
		abort();
	}

	if ( STD_LOGIC_1 == rdnwr ) {
		switch ( len ) {
			case 4: d =            *(dev->a32 + (addr>>2)); break;
			case 2: d =  (uint32_t)*(dev->a16 + (addr>>1)); break;
			case 1: d =  (uint32_t)*(dev->a8  + (addr>>0));  break;

			default: /* must be '3' */

				for ( i=len-1, d=0; i >= 0; i-- ) {
					d <<= 8;
					d |= (uint32_t) dev->a8[i];
				}
			break;
		}
#ifdef DEBUG
		printf("Reading (l=%" PRId32 ") from 0x%04" PRIx32 ": 0x%08" PRIx32 "\n", len, addr, d);
#endif
		*d_p = d;
	} else if ( STD_LOGIC_0 == rdnwr ) {

		d = *d_p;

#ifdef DEBUG
		printf("Writing (l=%" PRId32 ") to   0x%04" PRIx32 ": 0x%08" PRIx32 "\n", len, addr, d);
#endif

		switch ( len ) {
			case 4: *(dev->a32 + (addr>>2)) =           d; break;
			case 2: *(dev->a16 + (addr>>1)) = (uint16_t)d; break;
			case 1: *(dev->a8  + (addr>>0)) = (uint8_t )d; break;

			default: /* must be '3' */

				for ( i=0; i < (int)len; i++ ) {
					dev->a8[i] = (uint8_t)(d & 0xff);
					d >>= 8;
				}
			break;
		}
	} else {
		printf("readWrite_C: unexpected RDNWR %d\n", rdnwr);
		abort();
	}
}

}
