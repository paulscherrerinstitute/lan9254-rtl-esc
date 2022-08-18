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

#define ECUR_NO_CALLBACK ((EcurReadCallback)0)

/* Open connection; ECUR_DEFAULT_PORT should be fine in all normal cases */
#define ECUR_DEFAULT_PORT 0
Ecur
ecurOpen(const char *destIP, unsigned destPort, int verbosity);

/* Close connection */
void
ecurClose(Ecur e);

#define ECUR_ERR_INVALID_COUNT (-1) /* Invalid burst count */
#define ECUR_ERR_INVALID_ADDR  (-2) /* Address too big (not supported by protocol) or misaligned */
#define ECUR_ERR_NOSPACE_REQ   (-3) /* no space in xmit buffer for this request */
#define ECUR_ERR_NOSPACE_REP   (-4) /* no space in rcv buffer for the reply */

#define ECUR_ERR_INVALID_REP   (-5) /* unable to process reply */
#define ECUR_ERR_IO            (-6) /* network error */
#define ECUR_ERR_INTERNAL      (-7) /* should not happen */

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

/* RETURNS: number of elements processed or negative value on error */
int
ecurExecute( Ecur e );

/* Wrappers for synchronous operation */
int
ecurRead8(Ecur e, uint32_t addr, uint8_t *data, unsigned n);

int
ecurRead16(Ecur e, uint32_t addr, uint16_t *data, unsigned n);

int
ecurRead32(Ecur e, uint32_t addr, uint32_t *data, unsigned n);

int
ecurWrite8(Ecur e, uint32_t addr, uint8_t *data, unsigned n);

int
ecurWrite16(Ecur e, uint32_t addr, uint16_t *data, unsigned n);

int
ecurWrite32(Ecur e, uint32_t addr, uint32_t *data, unsigned n);

void
ecurPrintNetStats(Ecur e, uint32_t locbas);

int
ecurPrint(Ecur e, int level, const char *fmt, ... );

#ifdef __cplusplus
}
#endif

#endif
