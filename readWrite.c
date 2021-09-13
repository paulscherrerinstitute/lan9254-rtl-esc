#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static int cnt   = 0;
static int state = 0;

static uint32_t states[] = {1, 2, 4, 8, 4, 2, 1};

void readWrite_C(uint32_t addr, uint8_t rdnwr, uint32_t *d_p, uint32_t len)
{
    if ( 4 == cnt ) {
       cnt = 0;
       if ( state < sizeof(states)/sizeof(states[0]) - 1 ) {
	       state++;
       }
    } else {
		cnt++;
	}
	if ( 3 == rdnwr ) {
		printf("Reading from 0x%04" PRIx32 "(data was 0x%08" PRIx32 ")\n", addr, *d_p);
        if ( 0x120 == addr ) {
            *d_p = states[state];
        } else {
            printf("BAD ADDRESS 0x%04" PRIx32 "\n", addr);
            abort();
        }
	} else if ( 2 == rdnwr ) {
		printf("Writing to   0x%04" PRIx32 ": 0x%08" PRIx32 "\n", addr, *d_p);
        if ( 0x130 == addr ) {
            if ( *d_p != states[state] ) {
				printf("New state mismatch: %" PRId32 " (expected %" PRId32 ")\n", *d_p, states[state]);
			} else {
				if ( state == sizeof(states)/sizeof(states[0]) - 1 ) {
					printf("*******TEST PASSED***********\n");
                    exit(0);
				}
			}
        } else {
            printf("BAD ADDRESS 0x%04" PRIx32 "\n", addr);
            abort();
        }
	} else {
		printf("readWrite_C: unexpected RDNWR %d\n", rdnwr);
		abort();
	}
}
