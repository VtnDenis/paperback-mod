#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Substrate is not present on a sideloaded (non-jailbroken) app, so provide the
// single call Logos emits. Subclass overrides are installed on the subclass
// (class_addMethod) instead of patching the inherited implementation, which
// would affect every other class sharing it (e.g. UIView's -didMoveToWindow).
//
// %orig is a raw pointer Logos loads and calls: it must never stay NULL. When
// the class has nothing to chain to (an optional delegate method the app never
// implemented), we still install our method and point %orig at a no-op instead
// of leaving a null pointer to be called.
static void PBNoopHook(id self, SEL _cmd) {}

// Every `if (@available(...))` compiles to a call here. The helper lives in
// compiler-rt, which no framework exports on iOS 27, so `-undefined
// dynamic_lookup` let dyld bind it to 0 and the call jumped to address 0.
int __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor) {
    NSOperatingSystemVersion version = {major, minor, subminor};
    return (int)[[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version];
}

void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result) {
    Method inherited = class_getInstanceMethod(cls, sel);
    if (!inherited) {
        class_addMethod(cls, sel, imp, "v@:@");
        if (result) *result = (IMP)PBNoopHook;
        return;
    }
    IMP previous = method_getImplementation(inherited);
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(inherited))) {
        previous = method_setImplementation(class_getInstanceMethod(cls, sel), imp);
    }
    if (result) *result = previous;
}
