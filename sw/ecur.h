#ifndef ECUR_LIB_H
#define ECUR_LIB_H

#include <stdint.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Ethercat EoE / UDP register access */

typedef void (*EcurReadCallback)(void *data, int nelems, void *closure);

typedef struct EcurRec *Ecur;

/* Open connection */
Ecur
ecurOpen(const char *destIP, unsigned destPort, int verbosity);

/* Close connection */
void
ecurClose(Ecur e);

/* Queue operations */
int
ecurQRead8(Ecur e, uint32_t addr, uint8_t *data, unsigned n, EcurReadCallback cb, void *closure);

int
ecurQRead16(Ecur e, uint32_t addr, uint16_t *data, unsigned n, EcurReadCallback cb, void *closure);

int
ecurQRead32(Ecur e, uint32_t addr, uint32_t *data, unsigned n, EcurReadCallback cb, void *closure);

int
ecurQWrite8 (Ecur e, uint32_t addr, uint8_t *writeData, unsigned n);

int
ecurQWrite16(Ecur e, uint32_t addr, uint16_t *writeData, unsigned n);

int
ecurQWrite32(Ecur e, uint32_t addr, uint32_t *writeData, unsigned n);

/* Execute queued operations (writes always posted) */
int
ecurExecute( Ecur e );

/* Wrappers for synchronous operation */
int
ecurRead8(Ecur e, uint32_t addr, uint8_t *data, unsigned n);

int
ecurRead16(Ecur e, uint32_t addr, uint16_t *data, unsigned n);

int
ecurRead32(Ecur e, uint32_t addr, uint32_t *data, unsigned n);

void
ecurPrintNetStats(Ecur e, uint32_t locbas);

int
ecurPrint(Ecur e, int level, const char *fmt, ... );

#ifdef __cplusplus
}
#endif

#endif
