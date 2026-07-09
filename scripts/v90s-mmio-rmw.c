// SPDX-License-Identifier: MIT
// Tiny diagnostic helper for V90S bring-up: read/modify/write one 32-bit MMIO register.

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

static uint32_t parse_u32(const char *text, const char *name)
{
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 0);
    if (errno || end == text || *end != '\0' || value > UINT32_MAX) {
        fprintf(stderr, "invalid %s: %s\n", name, text);
        exit(2);
    }
    return (uint32_t)value;
}

int main(int argc, char **argv)
{
    if (argc != 4) {
        fprintf(stderr, "usage: %s <phys-addr> <mask> <value>\n", argv[0]);
        return 2;
    }

    uint32_t addr = parse_u32(argv[1], "phys-addr");
    uint32_t mask = parse_u32(argv[2], "mask");
    uint32_t value = parse_u32(argv[3], "value");

    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        perror("sysconf(_SC_PAGESIZE)");
        return 1;
    }

    uint32_t page_mask = (uint32_t)page_size - 1U;
    off_t page_addr = (off_t)(addr & ~page_mask);
    off_t page_off = (off_t)(addr & page_mask);

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open(/dev/mem)");
        return 1;
    }

    void *map = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page_addr);
    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }

    volatile uint32_t *reg = (volatile uint32_t *)((char *)map + page_off);
    uint32_t before = *reg;
    uint32_t after = (before & ~mask) | (value & mask);
    *reg = after;
    uint32_t verify = *reg;

    printf("addr=0x%08" PRIx32 " mask=0x%08" PRIx32 " value=0x%08" PRIx32
           " before=0x%08" PRIx32 " after=0x%08" PRIx32 " verify=0x%08" PRIx32 "\n",
           addr, mask, value, before, after, verify);

    munmap(map, (size_t)page_size);
    close(fd);
    return verify == after ? 0 : 1;
}
