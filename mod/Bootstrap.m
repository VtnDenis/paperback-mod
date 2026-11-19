#import <UIKit/UIKit.h>
#import "PBMod.h"

// Every %hook lives in a constructor that Logos generates -- and that
// constructor is the only place _logosLocalInit() is called. Writing a %ctor in
// Tweak.xm replaced it, so no hook was ever installed (diag: 0 didMoveToWindow
// calls). Keeping this code in its own constructor leaves the Logos one alone.
__attribute__((constructor)) static void PBBootstrap(void) {
    PBStartDiagTimeline();
    PBLogHook(@"tweak.loaded");
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
        PBRequestAuth();
        PBReportRemote(@"boot", [NSString stringWithFormat:@"iOS %@, app lancée", UIDevice.currentDevice.systemVersion]);
        // Unattended: 25 s after launch the summary lands on the ntfy topic, so a
        // failed run is visible without asking anyone to copy a screen.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            PBReportSummaryRemote();
        });
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
