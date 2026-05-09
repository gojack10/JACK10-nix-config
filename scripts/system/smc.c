// smc.c — Apple Silicon AppleSMC userspace poke tool
// Build: clang -O2 -Wall -framework IOKit -framework CoreFoundation smc.c -o smc
//
// Subcommands:
//   smc list [PREFIX]      enumerate keys (optionally filter by prefix, e.g. F)
//   smc read KEY           read one key (KEY is 4 chars)
//   smc write KEY HEX      write hex bytes (e.g. write F0Md 01)
//   smc info KEY           show key type/size/attributes only

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>

typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

enum {
    kSMCUserClientOpen  = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent  = 2,
    kSMCReadKey         = 5,
    kSMCWriteKey        = 6,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo      = 9,
};

#define KERNEL_INDEX_SMC 2

static io_connect_t conn;

static uint32_t fourcc_from(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) |
           ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] <<  8) |
           ((uint32_t)(uint8_t)s[3]);
}

static void fourcc_to(char out[5], uint32_t k) {
    out[0] = (k >> 24) & 0xff;
    out[1] = (k >> 16) & 0xff;
    out[2] = (k >>  8) & 0xff;
    out[3] = k & 0xff;
    out[4] = 0;
}

static kern_return_t smc_call(SMCParamStruct *in, SMCParamStruct *out) {
    size_t outsz = sizeof(*out);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC,
                                     in, sizeof(*in), out, &outsz);
}

static kern_return_t smc_get_key_info(uint32_t key, SMCKeyInfoData *info) {
    SMCParamStruct in = {0}, out = {0};
    in.key   = key;
    in.data8 = kSMCGetKeyInfo;
    kern_return_t r = smc_call(&in, &out);
    if (r != KERN_SUCCESS) return r;
    if (out.result != 0) return (kern_return_t)(0xE0000000u | out.result);
    *info = out.keyInfo;
    return KERN_SUCCESS;
}

static kern_return_t smc_read(uint32_t key, SMCKeyInfoData *info_out, uint8_t *bytes_out) {
    SMCKeyInfoData info;
    kern_return_t r = smc_get_key_info(key, &info);
    if (r != KERN_SUCCESS) return r;

    SMCParamStruct in = {0}, out = {0};
    in.key     = key;
    in.keyInfo = info;
    in.data8   = kSMCReadKey;
    r = smc_call(&in, &out);
    if (r != KERN_SUCCESS) return r;
    if (out.result != 0) return (kern_return_t)(0xE0000000u | out.result);

    if (info_out) *info_out = info;
    uint32_t n = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(bytes_out, out.bytes, n);
    return KERN_SUCCESS;
}

static kern_return_t smc_write(uint32_t key, const uint8_t *bytes, uint32_t len) {
    SMCKeyInfoData info;
    kern_return_t r = smc_get_key_info(key, &info);
    if (r != KERN_SUCCESS) return r;
    if (info.dataSize != len) {
        fprintf(stderr, "size mismatch: key wants %u bytes, you gave %u\n",
                info.dataSize, len);
        return -1;
    }
    SMCParamStruct in = {0}, out = {0};
    in.key     = key;
    in.keyInfo = info;
    in.data8   = kSMCWriteKey;
    memcpy(in.bytes, bytes, len);
    r = smc_call(&in, &out);
    if (r != KERN_SUCCESS) return r;
    if (out.result != 0) return (kern_return_t)(0xE0000000u | out.result);
    return KERN_SUCCESS;
}

static kern_return_t smc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) {
        fprintf(stderr, "AppleSMC service not found\n");
        return KERN_FAILURE;
    }
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return r;
}

static void format_value(uint32_t type_fcc, const uint8_t *b, uint32_t len,
                         char *buf, size_t bufsz) {
    char t[5]; fourcc_to(t, type_fcc);
    if (!strcmp(t, "ui8 ") && len >= 1) {
        snprintf(buf, bufsz, "%u", b[0]);
    } else if (!strcmp(t, "si8 ") && len >= 1) {
        snprintf(buf, bufsz, "%d", (int8_t)b[0]);
    } else if (!strcmp(t, "ui16") && len >= 2) {
        snprintf(buf, bufsz, "%u", (b[0] << 8) | b[1]);
    } else if (!strcmp(t, "si16") && len >= 2) {
        int16_t v = (int16_t)((b[0] << 8) | b[1]);
        snprintf(buf, bufsz, "%d", v);
    } else if (!strcmp(t, "ui32") && len >= 4) {
        snprintf(buf, bufsz, "%u",
                 (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]);
    } else if (!strcmp(t, "flt ") && len >= 4) {
        // little-endian float in SMC bytes
        float f;
        uint8_t le[4] = { b[0], b[1], b[2], b[3] };
        memcpy(&f, le, 4);
        snprintf(buf, bufsz, "%.3f", f);
    } else if (!strcmp(t, "fpe2") && len >= 2) {
        // 14.2 fixed-point, big-endian
        uint16_t v = (b[0] << 8) | b[1];
        snprintf(buf, bufsz, "%.2f", v / 4.0);
    } else if (!strcmp(t, "fp78") && len >= 2) {
        // 7.8 signed fixed, big-endian
        int16_t v = (int16_t)((b[0] << 8) | b[1]);
        snprintf(buf, bufsz, "%.3f", v / 256.0);
    } else if (!strcmp(t, "flag") && len >= 1) {
        snprintf(buf, bufsz, "%u", b[0]);
    } else {
        size_t off = 0;
        for (uint32_t i = 0; i < len && i < 16 && off + 3 < bufsz; i++)
            off += snprintf(buf + off, bufsz - off, "%02x", b[i]);
        if (len > 16 && off + 4 < bufsz) snprintf(buf + off, bufsz - off, "...");
    }
}

static int cmd_list(const char *prefix) {
    uint8_t cnt[4];
    SMCKeyInfoData info;
    kern_return_t r = smc_read(fourcc_from("#KEY"), &info, cnt);
    if (r != KERN_SUCCESS) {
        fprintf(stderr, "read #KEY failed: 0x%x\n", r);
        return 1;
    }
    uint32_t total = (cnt[0]<<24)|(cnt[1]<<16)|(cnt[2]<<8)|cnt[3];
    fprintf(stderr, "# total keys: %u\n", total);

    size_t plen = prefix ? strlen(prefix) : 0;
    uint32_t shown = 0;
    for (uint32_t i = 0; i < total; i++) {
        SMCParamStruct in = {0}, out = {0};
        in.data8  = kSMCGetKeyFromIndex;
        in.data32 = i;
        if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) continue;

        char keystr[5]; fourcc_to(keystr, out.key);
        if (plen && strncmp(keystr, prefix, plen) != 0) continue;

        uint8_t bytes[32] = {0};
        SMCKeyInfoData ki = {0};
        kern_return_t rr = smc_read(out.key, &ki, bytes);
        if (rr != KERN_SUCCESS) {
            char ts[5] = "----";
            printf("%s  type=%s size=?  attr=?    (read err 0x%x)\n",
                   keystr, ts, rr);
            shown++;
            continue;
        }
        char typestr[5]; fourcc_to(typestr, ki.dataType);
        char val[160];
        format_value(ki.dataType, bytes, ki.dataSize, val, sizeof(val));
        printf("%s  type=%s size=%-2u attr=0x%02x  %s\n",
               keystr, typestr, ki.dataSize, ki.dataAttributes, val);
        shown++;
    }
    fprintf(stderr, "# shown: %u\n", shown);
    return 0;
}

static int cmd_read(const char *keystr) {
    if (strlen(keystr) != 4) { fprintf(stderr, "key must be 4 chars\n"); return 1; }
    uint8_t bytes[32] = {0};
    SMCKeyInfoData info;
    kern_return_t r = smc_read(fourcc_from(keystr), &info, bytes);
    if (r != KERN_SUCCESS) { fprintf(stderr, "read failed: 0x%x\n", r); return 1; }
    char ts[5]; fourcc_to(ts, info.dataType);
    char val[160]; format_value(info.dataType, bytes, info.dataSize, val, sizeof(val));
    printf("%s = %s  (type=%s size=%u attr=0x%02x)\n",
           keystr, val, ts, info.dataSize, info.dataAttributes);
    printf("raw:");
    for (uint32_t i = 0; i < info.dataSize && i < 32; i++) printf(" %02x", bytes[i]);
    printf("\n");
    return 0;
}

static int cmd_info(const char *keystr) {
    if (strlen(keystr) != 4) { fprintf(stderr, "key must be 4 chars\n"); return 1; }
    SMCKeyInfoData info;
    kern_return_t r = smc_get_key_info(fourcc_from(keystr), &info);
    if (r != KERN_SUCCESS) { fprintf(stderr, "info failed: 0x%x\n", r); return 1; }
    char ts[5]; fourcc_to(ts, info.dataType);
    printf("%s  type=%s size=%u attr=0x%02x\n",
           keystr, ts, info.dataSize, info.dataAttributes);
    return 0;
}

static int cmd_write(const char *keystr, const char *hex) {
    if (strlen(keystr) != 4) { fprintf(stderr, "key must be 4 chars\n"); return 1; }
    uint8_t bytes[32] = {0};
    uint32_t len = 0;
    const char *p = hex;
    while (*p && len < 32) {
        while (*p == ' ') p++;
        if (!p[0] || !p[1]) break;
        unsigned v;
        if (sscanf(p, "%2x", &v) != 1) { fprintf(stderr, "bad hex\n"); return 1; }
        bytes[len++] = (uint8_t)v;
        p += 2;
    }
    kern_return_t r = smc_write(fourcc_from(keystr), bytes, len);
    if (r != KERN_SUCCESS) { fprintf(stderr, "write failed: 0x%x\n", r); return 1; }
    printf("write ok\n");
    return 0;
}

int main(int argc, char **argv) {
    // Sanity: the SMC param struct must be exactly 80 bytes for AppleSMC.
    _Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must be 80 bytes");

    if (argc < 2) {
        fprintf(stderr,
            "usage: %s list [PREFIX]\n"
            "       %s read  KEY\n"
            "       %s write KEY HEX\n"
            "       %s info  KEY\n",
            argv[0], argv[0], argv[0], argv[0]);
        return 1;
    }
    kern_return_t openr = smc_open();
    if (openr != KERN_SUCCESS) {
        fprintf(stderr, "failed to open AppleSMC: 0x%x\n", openr);
        return 1;
    }
    int rc = 1;
    if      (!strcmp(argv[1], "list")  )                 rc = cmd_list(argc > 2 ? argv[2] : NULL);
    else if (!strcmp(argv[1], "read")  && argc == 3)     rc = cmd_read(argv[2]);
    else if (!strcmp(argv[1], "write") && argc == 4)     rc = cmd_write(argv[2], argv[3]);
    else if (!strcmp(argv[1], "info")  && argc == 3)     rc = cmd_info(argv[2]);
    else fprintf(stderr, "bad args\n");
    IOServiceClose(conn);
    return rc;
}
