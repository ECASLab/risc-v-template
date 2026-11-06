#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/mman.h>
#include <sys/stat.h>

/* TFG P2.9.3: aplicación ARM para el supervisor AXI4-Lite P2.7.1.
 * Por defecto NO toca /dev/mem ni la FPGA. Ver README antes de --execute.
 * Diseño destinado a un único proceso; no usar simultáneamente con otros
 * clientes que accedan a la misma ventana AXI.
 */
enum {
    REG_CONTROL=0x00, REG_STATUS=0x04,
    REG_BOOT_ADDR_LO=0x08, REG_BOOT_ADDR_HI=0x0c,
    REG_BOOT_WDATA_LO=0x10, REG_BOOT_WDATA_HI=0x14,
    REG_BOOT_WSTRB=0x18, REG_BOOT_CMD=0x1c,
    REG_BOOT_RDATA_LO=0x20, REG_BOOT_RDATA_HI=0x24,
    REG_BOOT_STATUS=0x28
};
#define SUPERVISOR_PHYS UINT64_C(0xA0000000)
#define SUPERVISOR_SPAN  4096u
#define RAM_BASE UINT64_C(0x80000000)
#define RAM_SIZE 1048576u
#define RESULT_OFFSET 0x300u
#define EXPECTED_DEMO_IMAGE_SIZE 776u
#define EXPECTED_RESULT UINT64_C(1)

static void usage(const char *program) {
    fprintf(stderr,
        "Uso: %s --image archivo.bin [--check-image | --execute --confirm-hardware]\n"
        "  --check-image  Solo valida el binario (predeterminado, SIN /dev/mem).\n"
        "  --execute      Acceso AXI REAL; usar solo despues de autorizar el despliegue.\n"
        "  --confirm-hardware Confirma que se revisaron overlay, reloj y recuperacion.\n",program);
}

static uint8_t *load_image(const char *path, size_t *len) {
    struct stat st;
    if (stat(path,&st)!=0 || !S_ISREG(st.st_mode)) {
        fprintf(stderr,"ERROR: archivo no válido: %s (%s)\n",path,strerror(errno));
        return NULL;
    }
    if (st.st_size != EXPECTED_DEMO_IMAGE_SIZE) {
        fprintf(stderr,"ERROR: demo espera %u bytes; se encontraron %jd.\n",
            EXPECTED_DEMO_IMAGE_SIZE,(intmax_t)st.st_size);
        return NULL;
    }
    FILE *fp=fopen(path,"rb");
    if (!fp) { perror("fopen imagen"); return NULL; }
    uint8_t *data=calloc(1,(size_t)st.st_size);
    if (!data) { perror("calloc"); fclose(fp); return NULL; }
    size_t nr=fread(data,1,(size_t)st.st_size,fp);
    int bad=ferror(fp);
    fclose(fp);
    if (bad || nr!=(size_t)st.st_size) {
        fprintf(stderr,"ERROR: lectura incompleta de imagen\n");
        free(data); return NULL;
    }
    for (unsigned i=0;i<8;i++) {
        if (data[RESULT_OFFSET+i]!=0) {
            fprintf(stderr,"ERROR: result_flag inicial no es cero en +0x%03x\n",RESULT_OFFSET);
            free(data); return NULL;
        }
    }
    *len=nr;
    return data;
}

static uint64_t image_word(const uint8_t *p,size_t n,size_t offset) {
    uint64_t result=0;
    for (unsigned i=0;i<8 && offset+i<n;i++) result |= (uint64_t)p[offset+i] << (8*i);
    return result;
}

static int file_has_string(const char *filename,const char *needle) {
    char buf[512];
    FILE *fp=fopen(filename,"rb");
    if (!fp) return 0;
    size_t n=fread(buf,1,sizeof(buf)-1,fp);
    fclose(fp);
    buf[n]=0;
    return strstr(buf,needle)!=NULL;
}

static int overlay_is_applied(void) {
    const char *root="/sys/kernel/config/device-tree/overlays";
    DIR *dir=opendir(root);
    if (!dir) return 0;
    int match=0,reference=0;
    struct dirent *ent;
    while ((ent=readdir(dir))) {
        if (ent->d_name[0]=='.') continue;
        char path[512];
        int n=snprintf(path,sizeof(path),"%s/%s/status",root,ent->d_name);
        if (n<0 || (size_t)n>=sizeof(path)) continue;
        if (strstr(ent->d_name,"k26-starter-kits") && file_has_string(path,"applied")) reference=1;
        if (strstr(ent->d_name,"rv64i_tfg") && file_has_string(path,"applied")) match=1;
    }
    closedir(dir);
    if (reference) { fprintf(stderr,"ERROR: overlay original sigue aplicado\n"); return 0; }
    if (!match) fprintf(stderr,"ERROR: overlay RV64I no figura como applied\n");
    return match;
}

static int devicetree_matches(void) {
    const char *base="/proc/device-tree/axi/rv64i_supervisor@a0000000";
    char path[512];
    snprintf(path,sizeof(path),"%s/compatible",base);
    if (!file_has_string(path,"tfg,rv64i-axi-supervisor-1.0")) {
        fprintf(stderr,"ERROR: compatible del supervisor no detectado\n"); return 0;
    }
    snprintf(path,sizeof(path),"%s/reg",base);
    FILE *fp=fopen(path,"rb");
    if (!fp) { perror("Device Tree /reg"); return 0; }
    uint8_t reg[16];
    size_t bytes=fread(reg,1,sizeof(reg),fp);
    int extra=fgetc(fp);
    fclose(fp);
    const uint8_t expected[16]={0,0,0,0,0xa0,0,0,0,0,0,0,0,0,0,0x10,0};
    if (bytes!=16 || extra!=EOF || memcmp(reg,expected,16)!=0) {
        fprintf(stderr,"ERROR: reg del Device Tree no corresponde a 0xA0000000/4KiB\n");
        return 0;
    }
    if (!file_has_string("/sys/class/fpga_manager/fpga0/state","operating")) {
        fprintf(stderr,"ERROR: FPGA Manager no informa operating\n"); return 0;
    }
    return 1;
}

struct mmio {
    int fd;
    void *addr;
    volatile uint32_t *regs;
};

static int mmio_open(struct mmio *io) {
    io->fd=open("/dev/mem",O_RDWR|O_SYNC);
    if (io->fd<0) { perror("open /dev/mem"); return -1; }
    io->addr=mmap(NULL,SUPERVISOR_SPAN,PROT_READ|PROT_WRITE,MAP_SHARED,io->fd,(off_t)SUPERVISOR_PHYS);
    if (io->addr==MAP_FAILED) {
        perror("mmap supervisor");
        close(io->fd); io->fd=-1; io->addr=NULL;
        return -1;
    }
    io->regs=(volatile uint32_t *)io->addr;
    return 0;
}
static void mmio_close(struct mmio *io) {
    if (io->addr) munmap(io->addr,SUPERVISOR_SPAN);
    if (io->fd>=0) close(io->fd);
}
static inline void write_reg(struct mmio *io,unsigned offset,uint32_t value) {
    atomic_thread_fence(memory_order_seq_cst);
    io->regs[offset/4]=value;
    atomic_thread_fence(memory_order_seq_cst);
}
static inline uint32_t read_reg(struct mmio *io,unsigned offset) {
    atomic_thread_fence(memory_order_seq_cst);
    uint32_t value=io->regs[offset/4];
    atomic_thread_fence(memory_order_seq_cst);
    return value;
}
static void set_addr(struct mmio *io,uint64_t addr) {
    write_reg(io,REG_BOOT_ADDR_LO,(uint32_t)addr);
    write_reg(io,REG_BOOT_ADDR_HI,(uint32_t)(addr>>32));
}
static int boot_op(struct mmio *io,uint64_t addr,uint64_t input,int write,uint64_t *output) {
    if (addr<RAM_BASE || addr-RAM_BASE>RAM_SIZE-8 || (addr&7)!=0) {
        fprintf(stderr,"ERROR: acceso RAM fuera de rango/desalineado: 0x%016" PRIx64 "\n",addr);
        return -1;
    }
    set_addr(io,addr);
    if (write) {
        write_reg(io,REG_BOOT_WDATA_LO,(uint32_t)input);
        write_reg(io,REG_BOOT_WDATA_HI,(uint32_t)(input>>32));
        write_reg(io,REG_BOOT_WSTRB,0xff);
    }
    /* BOOT_CMD genera respuesta AXI solo tras completar el acceso nativo. */
    write_reg(io,REG_BOOT_CMD,write?1u:2u);
    uint32_t st=read_reg(io,REG_BOOT_STATUS);
    if ((st&3u)!=1u) {
        fprintf(stderr,"ERROR: BOOT_STATUS=0x%08" PRIx32 " en 0x%016" PRIx64 "\n",st,addr);
        return -1;
    }
    if (!write && output) {
        uint32_t lo=read_reg(io,REG_BOOT_RDATA_LO);
        uint32_t hi=read_reg(io,REG_BOOT_RDATA_HI);
        *output=((uint64_t)hi<<32)|lo;
    }
    return 0;
}
static double monotonic_s(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC,&now)!=0) return 0.0;
    return (double)now.tv_sec+(double)now.tv_nsec*1e-9;
}
static int run_demo(struct mmio *io,const uint8_t *img,size_t n) {
    if (read_reg(io,REG_CONTROL)!=0u) {
        fprintf(stderr,"ERROR: CONTROL.RUN != 0 antes de la carga; abortado\n"); return -1;
    }
    write_reg(io,REG_CONTROL,0);
    size_t words=(n+7)/8;
    printf("Cargando %zu palabras de 64 bits a RAM RV64I...\n",words);
    for (size_t i=0;i<words;i++) {
        uint64_t word=image_word(img,n,8*i);
        if (boot_op(io,RAM_BASE+8*i,word,1,NULL)!=0) return -1;
    }
    uint64_t val=0;
    if (boot_op(io,RAM_BASE,0,0,&val)!=0 || val!=image_word(img,n,0)) {
        fprintf(stderr,"ERROR: verificación de la primera palabra\n"); return -1;
    }
    if (boot_op(io,RAM_BASE+8*(words-1),0,0,&val)!=0 ||
        val!=image_word(img,n,8*(words-1))) {
        fprintf(stderr,"ERROR: verificación de la última palabra\n"); return -1;
    }
    if (boot_op(io,RAM_BASE+RESULT_OFFSET,0,0,&val)!=0 || val!=0) {
        fprintf(stderr,"ERROR: marcador inicial distinto de cero\n"); return -1;
    }
    puts("Carga validada. Iniciando RV64I...");
    write_reg(io,REG_CONTROL,1);
    double start=monotonic_s();
    unsigned polls=0;
    int result=-1;
    while (monotonic_s()-start<5.0) {
        uint32_t status=read_reg(io,REG_STATUS);
        unsigned code=(status>>8)&3u;
        polls++;
        if (code==1u) { result=0; break; }
        if (code==2u) { fprintf(stderr,"ERROR: RV64I reportó FAIL\n"); break; }
        struct timespec t={.tv_sec=0,.tv_nsec=1000000L};
        nanosleep(&t,NULL);
    }
    /* Detener el núcleo: no cambia el contenido de UltraRAM. */
    write_reg(io,REG_CONTROL,0);
    if (result!=0) {
        fprintf(stderr,"ERROR: no se obtuvo PASS en %u consultas\n",polls);
        return -1;
    }
    if (boot_op(io,RAM_BASE+RESULT_OFFSET,0,0,&val)!=0 || val!=EXPECTED_RESULT) {
        fprintf(stderr,"ERROR: result_flag = 0x%016" PRIx64 " (esperado 1)\n",val);
        return -1;
    }
    printf("PASS: ARM -> AXI4-Lite -> UltraRAM -> RV64I -> MMIO\n");
    printf("RESULT_FLAG=%" PRIu64 " POLLS=%u\n",val,polls);
    return 0;
}
int main(int argc,char **argv) {
    const char *filename=NULL;
    bool execute=false,confirm=false;
    for (int i=1;i<argc;i++) {
        if (strcmp(argv[i],"--image")==0 && i+1<argc) filename=argv[++i];
        else if (strcmp(argv[i],"--check-image")==0) execute=false;
        else if (strcmp(argv[i],"--execute")==0) execute=true;
        else if (strcmp(argv[i],"--confirm-hardware")==0) confirm=true;
        else { usage(argv[0]); return 2; }
    }
    if (!filename) { usage(argv[0]); return 2; }
    size_t n=0;
    uint8_t *img=load_image(filename,&n);
    if (!img) return 3;
    printf("IMAGE_VALID: %zu bytes, %zu palabras, RAM_BASE=0x%08" PRIx64 "\n",
           n,(n+7)/8,RAM_BASE);
    if (!execute) {
        printf("DRY_RUN_OK: no se accedió a /dev/mem ni a la FPGA\n");
        free(img);return 0;
    }
    if (!confirm || geteuid()!=0) {
        fprintf(stderr,"ERROR: --execute requiere --confirm-hardware y privilegios de root\n");
        free(img);return 4;
    }
    if (!overlay_is_applied() || !devicetree_matches()) {
        fprintf(stderr,"ERROR: comprobación previa del overlay falló; no se accedió al hardware\n");
        free(img);return 5;
    }
    fprintf(stderr,"AVISO: el acceso MMIO puede bloquearse si el reloj AXI o el hardware falla.\n");
    struct mmio io={.fd=-1,.addr=NULL,.regs=NULL};
    if (mmio_open(&io)!=0) { free(img); return 6; }
    int rc=run_demo(&io,img,n);
    mmio_close(&io);
    free(img);
    return rc==0?0:7;
}
