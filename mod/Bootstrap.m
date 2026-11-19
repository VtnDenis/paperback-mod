#import <UIKit/UIKit.h>
#import "PBMod.h"

// Every %hook lives in a constructor that Logos generates -- and that
// constructor is the only place _logosLocalInit() is called. Writing a %ctor in
// Tweak.xm replaced it, so no hook was ever installed (diag: 0 didMoveToWindow
// calls). Keeping this code in its own constructor leaves the Logos one alone.
__attribute__((constructor)) static void PBBootstrap(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
        PBRequestAuth();
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
        // Downloads die in the background otherwise: no background URLSession, no
        // BGTask, so the queue only lives while the process runs. See MAP.md.
        PBKeepAliveStart();
    }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
        PBKeepAliveStop();
    }];
}
