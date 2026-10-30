#import "MachOTool.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>

// Returns offset of the arm64 slice inside the file (0 for thin binaries), or -1.
static long arm64SliceOffset(NSData *d) {
    const uint8_t *b = d.bytes;
    uint32_t magic = *(uint32_t *)b;
    if (magic == MH_MAGIC_64) return 0;
    if (magic == FAT_CIGAM) {
        struct fat_header *fh = (void *)b; struct fat_arch *fa = (void *)(b + sizeof *fh);
        for (uint32_t i = 0; i < OSSwapBigToHostInt32(fh->nfat_arch); i++)
            if (OSSwapBigToHostInt32(fa[i].cputype) == CPU_TYPE_ARM64) return OSSwapBigToHostInt32(fa[i].offset);
    }
    return -1;
}

@implementation MachOTool
+ (BOOL)walk:(NSString *)path write:(BOOL)write block:(BOOL(^)(struct load_command *, struct mach_header_64 *))cb {
    NSMutableData *d = [NSMutableData dataWithContentsOfFile:path];
    long off = d ? arm64SliceOffset(d) : -1; if (off < 0) return NO;
    struct mach_header_64 *mh = (void *)((uint8_t *)d.mutableBytes + off);
    struct load_command *lc = (void *)(mh + 1);
    BOOL hit = NO;
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (void *)((uint8_t *)lc + lc->cmdsize))
        if (cb(lc, mh)) { hit = YES; break; }
    if (write) [d writeToFile:path atomically:YES];
    return hit;
}
+ (BOOL)isEncrypted:(NSString *)path {
    return [self walk:path write:NO block:^BOOL(struct load_command *lc, struct mach_header_64 *mh) {
        return lc->cmd == LC_ENCRYPTION_INFO_64 && ((struct encryption_info_command_64 *)lc)->cryptid != 0;
    }];
}
+ (BOOL)patchToDylib:(NSString *)path {
    return [self walk:path write:YES block:^BOOL(struct load_command *lc, struct mach_header_64 *mh) {
        if (mh->filetype == MH_EXECUTE) mh->filetype = MH_DYLIB;
        return YES; // header only; stop after first command
    }];
}
+ (uint64_t)entryOffset:(NSString *)path {
    __block uint64_t e = 0;
    [self walk:path write:NO block:^BOOL(struct load_command *lc, struct mach_header_64 *mh) {
        if (lc->cmd == LC_MAIN) { e = ((struct entry_point_command *)lc)->entryoff; return YES; } return NO;
    }];
    return e;
}
@end
