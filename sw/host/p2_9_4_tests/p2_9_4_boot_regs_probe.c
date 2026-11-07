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

    void *map = mmap(NULL, SUPERVISOR_SPAN,
                     PROT_READ, MAP_SHARED, fd,
                     (off_t)SUPERVISOR_PHYS);

    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 4;
    }

    const volatile uint32_t *regs =
        (const volatile uint32_t *)map;

    fprintf(stderr, "BOOT_STATUS_READ_START\n");
    fflush(stderr);

    uint32_t status = regs[REG_BOOT_STATUS / 4];

    fprintf(stderr, "BOOT_STATUS_READ_RETURNED\n");
    fflush(stderr);

    if (status != 0) {
        printf("BOOT_STATUS=0x%08" PRIx32 "\n", status);
        munmap(map, SUPERVISOR_SPAN);
        close(fd);
        return 5;
    }

    fprintf(stderr, "BOOT_WSTRB_READ_START\n");
    fflush(stderr);

    uint32_t strb = regs[REG_BOOT_WSTRB / 4];

    fprintf(stderr, "BOOT_WSTRB_READ_RETURNED\n");
    fflush(stderr);

    munmap(map, SUPERVISOR_SPAN);
    close(fd);

    printf("BOOT_STATUS=0x%08" PRIx32 "\n", status);
    printf("BOOT_DONE=%u\n", (unsigned)(status & 1u));
    printf("BOOT_ERROR=%u\n", (unsigned)((status >> 1) & 1u));
    printf("BOOT_WSTRB=0x%08" PRIx32 "\n", strb);

    if (strb != 0xffu) {
        fprintf(stderr, "ERROR: BOOT_WSTRB inesperado\n");
        return 6;
    }

    puts("BOOT_REGS_READ_PASS");
    puts("MMIO_WRITES=0");
    return 0;
}
