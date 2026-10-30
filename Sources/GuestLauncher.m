#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "fishhook.h"          // https://github.com/facebook/fishhook
#import "MachOTool.h"

static NSString *gGuestBundlePath, *gGuestBundleID, *gGuestDataRoot;
static Class gGuestDelegateClass;

// ---- 1. Path virtualization -------------------------------------------------
static NSString *(*orig_NSHomeDirectory)(void);
static NSString *my_NSHomeDirectory(void) { return gGuestDataRoot; }
static NSString *(*orig_NSTemporaryDirectory)(void);
static NSString *my_NSTemporaryDirectory(void) { return [gGuestDataRoot stringByAppendingPathComponent:@"tmp/"]; }

// ---- 2. Bundle identity spoofing -------------------------------------------
@implementation NSBundle (Guest)
+ (NSBundle *)guest_mainBundle { return [NSBundle bundleWithPath:gGuestBundlePath]; }
@end
static void swizzleClass(Class c, SEL a, SEL b) {
    method_exchangeImplementations(class_getClassMethod(c, a), class_getClassMethod(c, b));
}

// ---- 3. Swallow the guest's UIApplicationMain ------------------------------
// The host already owns the UIApplication; capture the guest delegate and return.
static int (*orig_UIApplicationMain)(int, char **, NSString *, NSString *);
static int my_UIApplicationMain(int argc, char **argv, NSString *principal, NSString *delegate) {
    gGuestDelegateClass = NSClassFromString(delegate);
    return 0;
}

// ---- Public entry -----------------------------------------------------------
int LaunchGuest(NSString *appPath, NSString *bundleID, NSString *exeName, NSString *dataRoot) {
    gGuestBundlePath = appPath; gGuestBundleID = bundleID; gGuestDataRoot = dataRoot;
    [[NSFileManager defaultManager] createDirectoryAtPath:[dataRoot stringByAppendingPathComponent:@"Documents"]
                              withIntermediateDirectories:YES attributes:nil error:nil];

    rebind_symbols((struct rebinding[]){
        {"NSHomeDirectory", my_NSHomeDirectory, (void *)&orig_NSHomeDirectory},
        {"NSTemporaryDirectory", my_NSTemporaryDirectory, (void *)&orig_NSTemporaryDirectory},
        {"UIApplicationMain", my_UIApplicationMain, (void *)&orig_UIApplicationMain},
    }, 3);
    swizzleClass(NSBundle.class, @selector(mainBundle), @selector(guest_mainBundle));
    // TODO: also hook open/stat/access (POSIX) and NSUserDefaults suite naming.

    NSString *exe = [appPath stringByAppendingPathComponent:exeName];
    [MachOTool patchToDylib:exe];                 // MH_EXECUTE -> MH_DYLIB
    // Load embedded frameworks first (dependency order matters; simplified here).
    NSString *fw = [appPath stringByAppendingPathComponent:@"Frameworks"];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fw error:nil])
        if ([f hasSuffix:@".framework"] || [f hasSuffix:@".dylib"]) {
            NSString *p = [f hasSuffix:@".dylib"] ? [fw stringByAppendingPathComponent:f]
                : [[fw stringByAppendingPathComponent:f] stringByAppendingPathComponent:[f stringByDeletingPathExtension]];
            dlopen(p.UTF8String, RTLD_GLOBAL | RTLD_NOW);
        }

    void *h = dlopen(exe.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    if (!h) { NSLog(@"dlopen failed: %s", dlerror()); return -1; }

    // Find image header, jump to LC_MAIN entry.
    const struct mach_header *hdr = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
        if (strstr(_dyld_get_image_name(i), exeName.UTF8String)) { hdr = _dyld_get_image_header(i); break; }
    if (!hdr) return -2;
    int (*guest_main)(int, char **) = (void *)((uintptr_t)hdr + [MachOTool entryOffset:exe]);
    char *argv[] = { (char *)exeName.UTF8String, NULL };
    guest_main(1, argv);                          // returns immediately thanks to hook #3

    if (gGuestDelegateClass) {
        id del = [[gGuestDelegateClass alloc] init];
        UIApplication.sharedApplication.delegate = del;   // may need KVC/runtime tricks on newer iOS
        if ([del respondsToSelector:@selector(application:didFinishLaunchingWithOptions:)])
            [del application:UIApplication.sharedApplication didFinishLaunchingWithOptions:@{}];
    }
    return 0;
}
