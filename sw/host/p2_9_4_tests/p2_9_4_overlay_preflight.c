#define main rv64i_loader_original_main
#include "../rv64i_arm_loader.c"
#undef main

int main(void) {
    if (!overlay_is_applied()) {
        return 10;
    }

    if (!devicetree_matches()) {
        return 11;
    }

    puts("OVERLAY_PREFLIGHT_OK");
    puts("NO_DEVMEM_ACCESS");
    return 0;
}
