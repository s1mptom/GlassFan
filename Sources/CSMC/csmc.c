#include "include/csmc.h"
#include <string.h>
#include <IOKit/IOKitLib.h>

typedef struct { char major, minor, build, reserved[1]; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVers vers; SMCPLimit pLimitData; SMCKeyInfo keyInfo;
    char result, status, data8; uint32_t data32; char bytes[32];
} SMCKeyData;

enum { KERNEL_INDEX_SMC = 2, SMC_CMD_READ = 5, SMC_CMD_WRITE = 6,
       SMC_CMD_KEY_FROM_INDEX = 8, SMC_CMD_KEY_INFO = 9 };

static io_connect_t g_conn = 0;
static int g_last_status = 0;

int smc_last_status(void) { return g_last_status; }

int smc_open(void) {
    if (g_conn) return SMC_OK;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return SMC_ERR_OPEN;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? SMC_OK : SMC_ERR_OPEN;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

static int call_smc(SMCKeyData *in, SMCKeyData *out) {
    if (!g_conn) return SMC_ERR_OPEN;
    g_last_status = 0;
    size_t sz = sizeof(SMCKeyData);
    kern_return_t r = IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sizeof(SMCKeyData), out, &sz);
    if (r == kIOReturnNotPrivileged) return SMC_ERR_NOT_PRIVILEGED;
    if (r != KERN_SUCCESS) return SMC_ERR_CALL;
    // The call succeeding says the message was delivered, not that the SMC agreed
    // with it. The controller answers in its own status byte, and on Apple silicon
    // it uses that byte to refuse fan writes (0x82) while the kernel reports success
    // - which made every refused write look like it had worked.
    g_last_status = (unsigned char)out->result;
    return g_last_status == 0 ? SMC_OK : SMC_ERR_REJECTED;
}

static int key_info(uint32_t key, SMCKeyInfo *info) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.data8 = SMC_CMD_KEY_INFO;
    int r = call_smc(&in, &out);
    if (r != SMC_OK) return r;
    if (out.keyInfo.dataSize == 0 || out.keyInfo.dataSize > 32) return SMC_ERR_SIZE;
    *info = out.keyInfo;
    return SMC_OK;
}

int smc_key_count(uint32_t *out_count) {
    uint8_t buf[32]; uint32_t size = 0, type = 0;
    int r = smc_read(smc_key_from_string("#KEY"), buf, &size, &type);
    if (r != SMC_OK || size != 4) return r == SMC_OK ? SMC_ERR_SIZE : r;
    *out_count = ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) | ((uint32_t)buf[2] << 8) | buf[3];
    return SMC_OK;
}

int smc_key_at_index(uint32_t index, uint32_t *out_key) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.data8 = SMC_CMD_KEY_FROM_INDEX; in.data32 = index;
    int r = call_smc(&in, &out);
    if (r != SMC_OK) return r;
    *out_key = out.key;
    return SMC_OK;
}

int smc_read(uint32_t key, uint8_t *buf, uint32_t *out_size, uint32_t *out_type) {
    SMCKeyInfo info;
    int r = key_info(key, &info);
    if (r != SMC_OK) return r;
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.keyInfo.dataSize = info.dataSize; in.data8 = SMC_CMD_READ;
    r = call_smc(&in, &out);
    if (r != SMC_OK) return r;
    memcpy(buf, out.bytes, info.dataSize);
    *out_size = info.dataSize;
    *out_type = info.dataType;
    return SMC_OK;
}

int smc_write(uint32_t key, const uint8_t *buf, uint32_t size) {
    if (size > 32) return SMC_ERR_SIZE;
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.data8 = SMC_CMD_WRITE; in.keyInfo.dataSize = size;
    memcpy(in.bytes, buf, size);
    return call_smc(&in, &out);
}

uint32_t smc_key_from_string(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16)
         | ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

void smc_key_to_string(uint32_t key, char *out5) {
    out5[0] = (char)(key >> 24); out5[1] = (char)(key >> 16);
    out5[2] = (char)(key >> 8);  out5[3] = (char)key; out5[4] = 0;
}
