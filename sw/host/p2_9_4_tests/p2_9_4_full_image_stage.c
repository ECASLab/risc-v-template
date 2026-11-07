#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(int argc, char **argv) {
    bool stage = false;

    if (argc == 1) {
        stage = false;
    } else if (argc == 3 &&
               strcmp(argv[1], "--stage") == 0 &&
               strcmp(argv[2], "--confirm-hardware") == 0) {
        stage = true;
    } else {
        fputs("USO: programa [--stage --confirm-hardware]\n",
              stderr);
        return 2;
    }

    size_t n = 0;
    uint8_t *image = load_image("accelerator.bin", &n);
    if (!image)
        return 3;

    const size_t words = (n + 7u) / 8u;

    printf("IMAGE_OK_BYTES=%zu WORDS=%zu\n", n, words);
    printf("IMAGE_FIRST=0x%016" PRIx64 "\n",
           image_word(image, n, 0));
    printf("IMAGE_LAST=0x%016" PRIx64 "\n",
           image_word(image, n, n - 8));

    fflush(stdout);

    if (!stage) {
        puts("OFFLINE_ONLY_NO_MMIO");
        free(image);
        return 0;
    }

    if (geteuid() != 0 ||
        !overlay_is_applied() ||
        !devicetree_matches()) {
        fputs("ERROR: ROOT_OR_OVERLAY_PREFLIGHT\n",
              stderr);
        free(image);
        return 4;
    }

    struct mmio io = {
        .fd = -1,
        .addr = NULL,
        .regs = NULL
    };

    if (mmio_open(&io) != 0) {
        free(image);
        return 5;
    }

    int rc = 0;

    const uint32_t control =
        read_reg(&io, REG_CONTROL);

    const uint32_t status =
        read_reg(&io, REG_STATUS);

    const uint32_t boot_status =
        read_reg(&io, REG_BOOT_STATUS);

    const uint32_t wstrb =
        read_reg(&io, REG_BOOT_WSTRB);

    printf("PRE_CONTROL=0x%08" PRIx32
           " PRE_STATUS=0x%08" PRIx32 "\n",
           control, status);

    printf("PRE_BOOT_STATUS=0x%08" PRIx32
           " PRE_WSTRB=0x%08" PRIx32 "\n",
           boot_status, wstrb);

    fflush(stdout);

    if (control != 0 ||
        status != 0 ||
        (boot_status & 2u) != 0 ||
        wstrb != 0xffu) {

        fputs("ABORT_PRECONDITION: NO_WRITES_PERFORMED\n",
              stderr);
        rc = 6;
        goto done;
    }

    puts("STAGE_BEGIN: RUN_REMAINS_ZERO");
    fflush(stdout);

    for (size_t i = 0; i < words; i++) {
        const uint64_t addr = RAM_BASE + 8u * i;
        const uint64_t expected =
            image_word(image, n, 8u * i);

        uint64_t observed = 0;

        if (boot_op(&io, addr, expected, 1, NULL) != 0) {
            fprintf(stderr,
                    "WRITE_FAILED_INDEX=%zu NO_RETRY\n", i);
            rc = 7;
            goto done;
        }

        if (boot_op(&io, addr, 0, 0, &observed) != 0) {
            fprintf(stderr,
                    "READ_FAILED_INDEX=%zu NO_RETRY\n", i);
            rc = 8;
            goto done;
        }

        if (observed != expected) {
            fprintf(stderr,
                "VERIFY_MISMATCH_INDEX=%zu"
                " EXPECTED=0x%016" PRIx64
                " OBSERVED=0x%016" PRIx64
                " NO_RETRY\n",
                i, expected, observed);

            rc = 9;
            goto done;
        }

        if (((i + 1u) % 16u) == 0u ||
             i + 1u == words) {
            printf("VERIFIED_WORDS=%zu/%zu\n",
                   i + 1u, words);
            fflush(stdout);
        }
    }

    {
        const uint32_t final_control =
            read_reg(&io, REG_CONTROL);

        const uint32_t final_status =
            read_reg(&io, REG_STATUS);

        const uint32_t final_boot =
            read_reg(&io, REG_BOOT_STATUS);

        printf("POST_CONTROL=0x%08" PRIx32 "\n",
               final_control);
        printf("POST_STATUS=0x%08" PRIx32 "\n",
               final_status);
        printf("POST_BOOT_STATUS=0x%08" PRIx32 "\n",
               final_boot);

        if (final_control != 0 ||
            final_status != 0 ||
            final_boot != 1u) {

            fputs("POSTCONDITION_FAILED_NO_RUN\n",
                  stderr);
            rc = 10;
            goto done;
        }
    }

    puts("FULL_IMAGE_STAGE_PASS");
    puts("RUN_WRITES=0");
    puts("DO_NOT_RUN_CORE_YET");

done:
    mmio_close(&io);
    free(image);
    return rc;
}
