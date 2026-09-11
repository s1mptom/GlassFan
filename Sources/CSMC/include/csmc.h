// Minimal SMC access. No policy, no decoding beyond raw bytes + type code.
#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

#define SMC_OK 0
#define SMC_ERR_OPEN -1
#define SMC_ERR_CALL -2
#define SMC_ERR_SIZE -3
#define SMC_ERR_NOT_PRIVILEGED -4

// Opens the AppleSMC user client. Reads work unprivileged; writes need root.
int smc_open(void);
void smc_close(void);

int smc_key_count(uint32_t *out_count);
int smc_key_at_index(uint32_t index, uint32_t *out_key);
// Reads up to 32 bytes. out_size and out_type receive the key's declared size/type code.
int smc_read(uint32_t key, uint8_t *buf, uint32_t *out_size, uint32_t *out_type);
int smc_write(uint32_t key, const uint8_t *buf, uint32_t size);

uint32_t smc_key_from_string(const char *s);
void smc_key_to_string(uint32_t key, char *out5);

#endif
