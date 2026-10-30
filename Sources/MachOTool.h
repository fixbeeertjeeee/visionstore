#import <Foundation/Foundation.h>
@interface MachOTool : NSObject
+ (BOOL)isEncrypted:(NSString *)path;                       // LC_ENCRYPTION_INFO(_64) cryptid != 0
+ (BOOL)patchToDylib:(NSString *)path;                      // MH_EXECUTE -> MH_DYLIB so dlopen accepts it
+ (uint64_t)entryOffset:(NSString *)path;                   // LC_MAIN entryoff
@end
