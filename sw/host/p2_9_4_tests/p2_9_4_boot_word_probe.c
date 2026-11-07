#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(void) {
    const uint64_t probe_addr = RAM_BASE;
    const uint64_t pattern =
        UINT64_C(0x1122334455667788);

    uint64_t got = 0;
    int ret = 1;

    struct mmio io = {
        .fd = -1,
        .addr = NULL,
        .regs = NULL
    };

    if (geteuid() != 0) {
        fputs("ROOT_REQUIRED\n", stderr);
        return 1;
    }

    if (!overlay_is_applied() ||
        !devicetree_matches()) {
        fputs("PREFLIGHT_FAILED\n", stderr);
        return 2;
    }

    if (mmio_open(&io) != 0)
        return 3;

    uint32_t control =
        read_reg(&io, REG_CONTROL);
    uint32_t status =
        read_reg(&io, REG_STATUS);
    uint32_t boot_status =
        read_reg(&io, REG_BOOT_STATUS);
    uint32_t wstrb =
        read_reg(&io, REG_BOOT_WSTRB);

    printf("PRE_CONTROL=0x%08" PRIx32 "\n", control);
    printf("PRE_STATUS=0x%08" PRIx32 "\n", status);
    printf("PRE_BOOT_STATUS=0x%08" PRIx32 "\n",
           boot_status);
    printf("PRE_BOOT_WSTRB=0x%08" PRIx32 "\n", wstrb);
    fflush(stdout);

    if (control != 0 ||
        status != 0 ||
        boot_status != 0 ||
        wstrb != 0xffu) {

        fputs("PRECONDITION_FAILED_NO_BOOT_COMMAND\n",
              stderr);
        ret = 4;
        goto cleanup;
    }

    printf("BOOT_WRITE_START addr=0x%016" PRIx64
           " data=0x%016" PRIx64 "\n",
           probe_addr, pattern);
    fflush(stdout);

    if (boot_op(&io, probe_addr,
                pattern, 1, NULL) != 0) {

        fputs("BOOT_WRITE_FAILED_NO_RETRY\n", stderr);
        ret = 5;
        goto cleanup;
    }

    puts("BOOT_WRITE_COMPLETED");
    fflush(stdout);

    printf("BOOT_READ_START addr=0x%016" PRIx64 "\n",
           probe_addr);
    fflush(stdout);

    if (boot_op(&io, probe_addr,
                0, 0, &got) != 0) {

        fputs("BOOT_READ_FAILED_NO_RETRY\n", stderr);
        ret = 6;
        goto cleanup;
    }

    printf("BOOT_READ_VALUE=0x%016" PRIx64 "\n", got);

    uint32_t final_control =
        read_reg(&io, REG_CONTROL);
    uint32_t final_status =
        read_reg(&io, REG_STATUS);
    uint32_t final_boot =
        read_reg(&io, REG_BOOT_STATUS);

    printf("POST_CONTROL=0x%08" PRIx32 "\n",
           final_control);
    printf("POST_STATUS=0x%08" PRIx32 "\n",
           final_status);
    printf("POST_BOOT_STATUS=0x%08" PRIx32 "\n",
           final_boot);

    if (got != pattern ||
        final_control != 0 ||
        final_status != 0 ||
        final_boot != 1u) {

        fputs("BOOT_READBACK_MISMATCH_NO_RETRY\n",
              stderr);
        ret = 7;
        goto cleanup;
    }

    puts("BOOT_URAM_WORD_PASS");
    puts("RUN_WRITES=0");
    puts("RELOAD_FULL_IMAGE_BEFORE_RUN");

    ret = 0;

cleanup:
    mmio_close(&io);
    return ret;
}
