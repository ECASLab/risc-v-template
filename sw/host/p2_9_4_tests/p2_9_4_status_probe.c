#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(void) {
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: requiere root\n");
        return 1;
    }

    if (!overlay_is_applied() ||
        !devicetree_matches()) {
        fprintf(stderr, "ERROR: preflight fallido\n");
        return 2;
    }

    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 3;
    }

    void *p = mmap(NULL, SUPERVISOR_SPAN,
                   PROT_READ, MAP_SHARED, fd,
                   (off_t)SUPERVISOR_PHYS);

    if (p == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 4;
    }

    const volatile uint32_t *regs =
        (const volatile uint32_t *)p;

    fprintf(stderr,
            "AXI_STATUS_READ_START: STATUS +0x04\n");
    fflush(stderr);

    uint32_t status = regs[REG_STATUS / 4];

    fprintf(stderr, "AXI_STATUS_READ_RETURNED\n");
    fflush(stderr);

    munmap(p, SUPERVISOR_SPAN);
    close(fd);

    printf("STATUS=0x%08" PRIx32 "\n", status);
    printf("RUN=%u\n", (unsigned)(status & 1u));
    printf("RESULT_CODE=%u\n",
           (unsigned)((status >> 8) & 3u));

    if (status != 0) {
        fprintf(stderr,
                "ERROR: estado inicial inesperado\n");
        return 5;
    }

    puts("AXI_STATUS_READ_PASS");
    puts("MMIO_WRITES=0");
    return 0;
}
