#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(void) {
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: requiere root\n");
        return 1;
    }

    if (!overlay_is_applied() || !devicetree_matches()) {
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

    fprintf(stderr, "AXI_READ_START: CONTROL +0x00\n");
    fflush(stderr);

    const volatile uint32_t *regs =
        (const volatile uint32_t *)p;

    uint32_t value = regs[0];

    fprintf(stderr, "AXI_READ_RETURNED\n");
    fflush(stderr);

    munmap(p, SUPERVISOR_SPAN);
    close(fd);

    printf("CONTROL=0x%08" PRIx32 "\n", value);

    if (value != 0) {
        fprintf(stderr,
                "ERROR: CONTROL inesperado; no continuar\n");
        return 5;
    }

    puts("AXI_CONTROL_READ_PASS");
    puts("MMIO_WRITES=0");
    return 0;
}
