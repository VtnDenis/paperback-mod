#import <objc/runtime.h>

// Substrate is not present on a sideloaded (non-jailbroken) app, so provide the
// single call Logos emits. Subclass overrides are installed on the subclass
// (class_addMethod) instead of patching the inherited implementation, which
// would affect every other class sharing it (e.g. UIView's -didMoveToWindow).
void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result) {
    Method inherited = class_getInstanceMethod(cls, sel);
    if (!inherited) return;
    IMP previous = method_getImplementation(inherited);
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(inherited))) {
        previous = method_setImplementation(class_getInstanceMethod(cls, sel), imp);
    }
    if (result) *result = previous;
}
