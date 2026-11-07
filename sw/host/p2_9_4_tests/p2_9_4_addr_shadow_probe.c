#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(void) {
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR_ROOT_REQUIRED\n");
        return 1;
    }

    if (!overlay_is_applied() || !devicetree_matches()) {
        fprintf(stderr, "ERROR_PREFLIGHT\n");
        return 2;
    }

    struct mmio io = {
        .fd = -1,
        .addr = NULL,
        .regs = NULL
    };

    if (mmio_open(&io) != 0)
        return 3;

    uint32_t control =
        read_reg(&io, REG_CONTROL);

    uint32_t status =
        read_reg(&io, REG_BOOT_STATUS);

    uint32_t original_lo =
        read_reg(&io, REG_BOOT_ADDR_LO);

    uint32_t original_hi =
        read_reg(&io, REG_BOOT_ADDR_HI);

    printf("PRE_CONTROL=0x%08" PRIx32 "\n", control);
    printf("PRE_BOOT_STATUS=0x%08" PRIx32 "\n", status);
    printf("PRE_ADDR_LO=0x%08" PRIx32 "\n", original_lo);
    printf("PRE_ADDR_HI=0x%08" PRIx32 "\n", original_hi);
    fflush(stdout);

    if (control != 0 || status != 0 ||
        original_lo != 0 || original_hi != 0) {
        fprintf(stderr,
                "ABORT_UNEXPECTED_INITIAL_STATE\n");
        mmio_close(&io);
        return 4;
    }

    puts("WRITE_START: BOOT_ADDR_LO=0x80000000");
    fflush(stdout);

    write_reg(&io, REG_BOOT_ADDR_LO,
              UINT32_C(0x80000000));

    uint32_t after =
        read_reg(&io, REG_BOOT_ADDR_LO);

    printf("ADDR_LO_READBACK=0x%08" PRIx32 "\n", after);
    fflush(stdout);

    puts("RESTORE_START: BOOT_ADDR_LO=0x00000000");
    fflush(stdout);

    write_reg(&io, REG_BOOT_ADDR_LO, original_lo);

    uint32_t final_lo =
        read_reg(&io, REG_BOOT_ADDR_LO);

    uint32_t final_control =
        read_reg(&io, REG_CONTROL);

    uint32_t final_status =
        read_reg(&io, REG_BOOT_STATUS);

    printf("RESTORED_ADDR_LO=0x%08" PRIx32 "\n",
           final_lo);
    printf("POST_CONTROL=0x%08" PRIx32 "\n",
           final_control);
    printf("POST_BOOT_STATUS=0x%08" PRIx32 "\n",
           final_status);

    int rc = 0;

    if (after == UINT32_C(0x80000000) &&
        final_lo == original_lo &&
        final_control == 0 &&
        final_status == 0) {

        puts("AXI_BOOT_ADDR_WRITE_READBACK_PASS");
        puts("BOOT_CMD_WRITES=0");
        puts("CONTROL_WRITES=0");
    } else {
        fprintf(stderr,
                "ERROR_WRITE_OR_RESTORE_MISMATCH\n");
        rc = 5;
    }

    mmio_close(&io);
    return rc;
}
