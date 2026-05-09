#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    SECTOR_SIZE = 512,
    TOTAL_SECTORS = 131072,
    PART_LBA = 2048,
    PART_SECTORS = TOTAL_SECTORS - PART_LBA,
    RESERVED_SECTORS = 1,
    FAT_COUNT = 2,
    FAT_SECTORS = 64,
    ROOT_ENTRIES = 512,
    ROOT_SECTORS = ROOT_ENTRIES * 32 / SECTOR_SIZE,
    SECTORS_PER_CLUSTER = 8,
    BIOS_CLUSTER = 2,
    FILE_CLUSTER = 3,
    BOOTLOADER_COMPAT_FILE_LBA = 0x202020,
};

static void put16(uint8_t *p, uint16_t v)
{
    p[0] = v & 0xff;
    p[1] = v >> 8;
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = v & 0xff;
    p[1] = (v >> 8) & 0xff;
    p[2] = (v >> 16) & 0xff;
    p[3] = v >> 24;
}

static void write_at(FILE *out, uint32_t sector, const void *buf, size_t len)
{
    if (fseek(out, (long)sector * SECTOR_SIZE, SEEK_SET) != 0 ||
        fwrite(buf, 1, len, out) != len) {
        fprintf(stderr, "write sector %u failed: %s\n", sector, strerror(errno));
        exit(1);
    }
}

static uint32_t data_lba(void)
{
    return PART_LBA + RESERVED_SECTORS + FAT_COUNT * FAT_SECTORS + ROOT_SECTORS;
}

static uint32_t cluster_lba(uint32_t cluster)
{
    return data_lba() + (cluster - 2) * SECTORS_PER_CLUSTER;
}

static void dirent(uint8_t *p, const char name[11], uint8_t attr,
                   uint32_t cluster, uint32_t size)
{
    memcpy(p, name, 11);
    p[11] = attr;
    put16(p + 20, cluster >> 16);
    put16(p + 26, cluster & 0xffff);
    put32(p + 28, size);
}

static void write_boot(FILE *out)
{
    uint8_t sector[SECTOR_SIZE];

    memset(sector, 0, sizeof(sector));
    memcpy(sector + 0x1be, "\x80\x01\x01\x00\x06\xfe\xff\xff", 8);
    put32(sector + 0x1c6, PART_LBA);
    put32(sector + 0x1ca, PART_SECTORS);
    sector[510] = 0x55;
    sector[511] = 0xaa;
    write_at(out, 0, sector, sizeof(sector));

    memset(sector, 0, sizeof(sector));
    memcpy(sector, "\xeb\x58\x90MSDOS5.0", 11);
    put16(sector + 11, SECTOR_SIZE);
    sector[13] = SECTORS_PER_CLUSTER;
    put16(sector + 14, RESERVED_SECTORS);
    sector[16] = FAT_COUNT;
    put16(sector + 17, ROOT_ENTRIES);
    put32(sector + 32, PART_SECTORS);
    sector[21] = 0xf8;
    put16(sector + 22, FAT_SECTORS);
    put16(sector + 24, 63);
    put16(sector + 26, 255);
    put32(sector + 28, PART_LBA);
    memcpy(sector + 54, "FAT16   ", 8);
    sector[510] = 0x55;
    sector[511] = 0xaa;
    write_at(out, PART_LBA, sector, sizeof(sector));
}

static void fat16(uint8_t *fat, uint32_t cluster, uint16_t value)
{
    put16(fat + cluster * 2, value);
}

static void write_fat(FILE *out, uint32_t file_clusters)
{
    uint8_t fat[FAT_SECTORS * SECTOR_SIZE];
    uint32_t i;

    memset(fat, 0, sizeof(fat));
    fat16(fat, 0, 0xfff8);
    fat16(fat, 1, 0xffff);
    fat16(fat, BIOS_CLUSTER, 0xffff);
    for (i = 0; i < file_clusters; i++) {
        uint32_t cluster = FILE_CLUSTER + i;
        uint16_t next = i + 1 == file_clusters ? 0xffff : cluster + 1;
        fat16(fat, cluster, next);
    }
    write_at(out, PART_LBA + RESERVED_SECTORS, fat, sizeof(fat));
    write_at(out, PART_LBA + RESERVED_SECTORS + FAT_SECTORS, fat, sizeof(fat));
}

static void write_dirs(FILE *out, uint32_t asd_size)
{
    uint8_t root[ROOT_SECTORS * SECTOR_SIZE];
    uint8_t cluster[SECTORS_PER_CLUSTER * SECTOR_SIZE];

    memset(root, 0, sizeof(root));
    dirent(root, "BIOS       ", 0x10, BIOS_CLUSTER, 0);
    write_at(out, PART_LBA + RESERVED_SECTORS + FAT_COUNT * FAT_SECTORS,
             root, sizeof(root));

    memset(cluster, 0, sizeof(cluster));
    dirent(cluster, ".          ", 0x10, BIOS_CLUSTER, 0);
    dirent(cluster + 32, "..         ", 0x10, 0, 0);
    dirent(cluster + 64, "BISRV   ASD", 0x20, FILE_CLUSTER, asd_size);
    write_at(out, cluster_lba(BIOS_CLUSTER), cluster, sizeof(cluster));
}

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *in = fopen(path, "rb");
    uint8_t *buf;
    long len;

    if (!in) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        exit(1);
    }
    if (fseek(in, 0, SEEK_END) != 0 || (len = ftell(in)) < 0 ||
        fseek(in, 0, SEEK_SET) != 0) {
        fprintf(stderr, "stat %s failed\n", path);
        exit(1);
    }
    buf = malloc((size_t)len);
    if (!buf || fread(buf, 1, (size_t)len, in) != (size_t)len) {
        fprintf(stderr, "read %s failed\n", path);
        exit(1);
    }
    fclose(in);
    *size = (size_t)len;
    return buf;
}

int main(int argc, char **argv)
{
    FILE *out;
    uint8_t *asd;
    size_t asd_size;
    uint32_t file_clusters;

    if (argc != 3) {
        fprintf(stderr, "usage: %s bisrv.asd sd.img\n", argv[0]);
        return 2;
    }

    asd = read_file(argv[1], &asd_size);
    file_clusters = (asd_size + SECTORS_PER_CLUSTER * SECTOR_SIZE - 1) /
                    (SECTORS_PER_CLUSTER * SECTOR_SIZE);
    if (FILE_CLUSTER + file_clusters >= (FAT_SECTORS * SECTOR_SIZE) / 2) {
        fprintf(stderr, "ASD is too large for the tiny FAT image\n");
        return 1;
    }

    out = fopen(argv[2], "wb+");
    if (!out) {
        fprintf(stderr, "open %s failed: %s\n", argv[2], strerror(errno));
        return 1;
    }
    if (fseek(out, (long)TOTAL_SECTORS * SECTOR_SIZE - 1, SEEK_SET) != 0 ||
        fputc(0, out) == EOF) {
        fprintf(stderr, "size %s failed: %s\n", argv[2], strerror(errno));
        return 1;
    }

    write_boot(out);
    write_fat(out, file_clusters);
    write_dirs(out, (uint32_t)asd_size);
    write_at(out, cluster_lba(FILE_CLUSTER), asd, asd_size);
    /*
     * Current stock bootloader emulation finds BISRV.ASD in the FAT16
     * directory but computes the first file LBA as 0x202020. Mirror the ASD
     * there so the full-chain diagnostic can continue past this known geometry
     * bug and expose the next hardware contract.
     */
    write_at(out, BOOTLOADER_COMPAT_FILE_LBA, asd, asd_size);
    fclose(out);
    free(asd);
    return 0;
}
