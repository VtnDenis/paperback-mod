#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "PBMod.h"

static const NSTimeInterval PBRefreshInterval = 30 * 60;

#pragma mark - Scene lifecycle

// Notifications instead of %hook: the app's SceneDelegate implements
// -sceneDidBecomeActive: but not -sceneWillResignActive:, and a %orig that
// points nowhere takes the whole process down at launch. The observers now live
// in Bootstrap.m: a %ctor here would replace the Logos constructor and skip
// _logosLocalInit(), i.e. install no hook at all.

#pragma mark - Open on Library instead of Discover

static NSInteger PBIndexOfController(NSArray<UIViewController *> *vcs, NSString *needle) {
    for (NSUInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        if ([NSStringFromClass(vc.class) containsString:needle]) return (NSInteger)i;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *root = [(UINavigationController *)vc viewControllers].firstObject;
            if ([NSStringFromClass(root.class) containsString:needle]) return (NSInteger)i;
        }
    }
    return NSNotFound;
}

%hook _TtC9Paperback21MainTabViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PBDiagShown) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (UIViewController *child in ((UITabBarController *)self).viewControllers) {
            [names addObject:NSStringFromClass(child.class)];
        }
        PBShowDiag(self, [NSString stringWithFormat:@"%lu -> %@",
                          (unsigned long)((UITabBarController *)self).viewControllers.count,
                          [names componentsJoinedByString:@", "]]);
    }
    // Once only: viewDidAppear fires again after modal sheets, and resetting the
    // tab every time would fight the user.
    static BOOL jumped;
    if (jumped) return;
    UITabBarController *tabs = (UITabBarController *)self;
    NSInteger library = PBIndexOfController(tabs.viewControllers, @"LibraryViewController");
    if (library != NSNotFound) {
        jumped = YES;
        if (tabs.selectedIndex != library) tabs.selectedIndex = library;
    }
}
%end

#pragma mark - Periodic library refresh

static __weak UIViewController *PBLibraryViewController;
static NSTimeInterval PBLastRefresh;
static NSTimeInterval PBRefreshStarted;

// True while an updater is on screen, expiring anyway: some updaters never
// report viewDidDisappear and would otherwise block refresh forever.
static BOOL PBRefreshInFlight(void) {
    return PBRefreshStarted > 0 && [NSDate date].timeIntervalSince1970 - PBRefreshStarted < 600;
}

static void PBRefreshIfDue(void) {
    if (PBRefreshInFlight() || !PBLibraryViewController) return;
    if ([NSDate date].timeIntervalSince1970 - PBLastRefresh < PBRefreshInterval) return;
    PBLastRefresh = [NSDate date].timeIntervalSince1970;
    SEL refresh = NSSelectorFromString(@"didRefreshCollectionView:");
    void (*call)(id, SEL, id) = (void (*)(id, SEL, id))[(id)PBLibraryViewController methodForSelector:refresh];
    call(PBLibraryViewController, refresh, nil);
}

%hook _TtC9Paperback21LibraryViewController

- (void)viewDidLoad {
    %orig;
    PBLibraryViewController = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!PBDiagShown) PBShowDiag(PBLibraryViewController, @"JAMAIS (repli Library)");
    });
    // A timer only ticks while the process is alive; combined with KeepAlive it
    // keeps checking while the app sits in the background.
    [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground && !PBRefreshInFlight()) return;
        PBRefreshIfDue();
    }];
}
%end

#pragma mark - Local notifications on new chapters

// The updater table is fed source by source: the section header carries the
// source name and numberOfRowsInSection: its chapter count. Both are @objc and
// called for every section on each reload, unlike cellForRow which is
// virtualised. Reloads fire repeatedly while a source is still being fetched, so
// counts are batched and a single merged notification goes out once the burst
// goes quiet.
static NSMutableDictionary<NSNumber *, NSString *> *PBTitles;
static NSMutableDictionary<NSNumber *, NSNumber *> *PBCounts;
static NSTimer *PBFlushTimer;
static NSString *PBLastBody;
static NSTimeInterval PBLastPost;

static void PBFlushUpdates(void) {
    NSUInteger total = 0;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSNumber *section in PBCounts) {
        NSUInteger count = PBCounts[section].unsignedIntegerValue;
        if (!count) continue;
        total += count;
        NSString *title = PBTitles[section];
        [parts addObject:title.length
            ? [NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)count]
            : [NSString stringWithFormat:@"%lu chapters", (unsigned long)count]];
    }
    [PBCounts removeAllObjects];
    if (!total) return;

    NSString *sources = parts.count > 3
        ? [NSString stringWithFormat:@"%@ and %lu more",
             [[parts subarrayWithRange:NSMakeRange(0, 3)] componentsJoinedByString:@", "],
             (unsigned long)(parts.count - 3)]
        : [parts componentsJoinedByString:@", "];
    NSString *body = [NSString stringWithFormat:@"%lu new chapter%@ from %@",
                      (unsigned long)total, total == 1 ? @"" : @"s", sources];

    // Same burst reloaded twice (e.g. re-presenting the updater) must not re-notify.
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([body isEqualToString:PBLastBody] && now - PBLastPost < 30 * 60) return;
    PBLastBody = body;
    PBLastPost = now;
    PBPostLocalNotification(@"New chapters", body, @"paperback.library");
}

static void PBScheduleFlush(void) {
    [PBFlushTimer invalidate];
    PBFlushTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO
                                                     block:^(NSTimer *timer) { PBFlushUpdates(); }];
}

%hook _TtC9Paperback28LibraryUpdaterViewController

- (void)viewDidLoad {
    %orig;
    PBTitles = [NSMutableDictionary new];
    PBCounts = [NSMutableDictionary new];
    PBRefreshStarted = [NSDate date].timeIntervalSince1970;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    PBRefreshStarted = 0;
    PBFlushUpdates();
}

- (NSInteger)tableView:(id)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger rows = %orig;
    if (rows > 0) {
        PBCounts[@(section)] = @(rows);
        PBScheduleFlush();
    }
    return rows;
}

- (NSString *)tableView:(id)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *title = %orig;
    if (title.length) PBTitles[@(section)] = title;
    return title;
}
%end

#pragma mark - Liquid Glass buttons (iOS 26+)

// The app is built against the iOS 18 SDK, so it keeps the pre-glass look.
// UIGlassEffect exists at runtime from iOS 26 and can be applied to any view.
// Buttons are found by walking the hierarchy rather than by hooking
// -didMoveToWindow: UIKit's own button subclasses override it, so the hook
// never fired (diag: 0 calls while other hooks worked).
static void PBApplyGlass(UIButton *button) {
    if (@available(iOS 26.0, *)) {
        Class glassClass = NSClassFromString(@"UIGlassEffect");
        if (!glassClass) return;
        if (objc_getAssociatedObject(button, "pb.glass")) return;
        // Only restyle buttons that carry a surface already; plain text and
        // bar buttons have no background of their own.
        UIColor *surface = button.backgroundColor;
        if (!surface && button.layer.borderWidth == 0) return;
        PBDiagEligible++;
        // Dry run for now: restoring the button's own background is the whole
        // point of the next test.
        if (!PBGlassEnabled) return;

        // Style 0 is `regular`; `clear` is the other case.
        SEL make = NSSelectorFromString(@"effectWithStyle:");
        id (*makeEffect)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))[(id)glassClass methodForSelector:make];
        id effect = makeEffect(glassClass, make, 0);
        if (!effect) return;
        if (surface && [effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) {
            [(id)effect setTintColor:surface];
        }

        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.userInteractionEnabled = NO;
        glass.clipsToBounds = YES;
        glass.layer.cornerRadius = button.bounds.size.height > 0 ? button.bounds.size.height / 2 : 22;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [button insertSubview:glass atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:button.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
        ]];
        button.backgroundColor = [UIColor clearColor];
        objc_setAssociatedObject(button, "pb.glass", glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PBDiagGlassApplied++;
    }
}

#pragma mark - Tab bar

%hook _TtC18ESTabBarController18ESTabBarController

- (void)viewDidLoad {
    %orig;
    UITabBarController *tabs = (UITabBarController *)self;
    tabs.tabBar.tintColor = [UIColor colorWithRed:0.98 green:0.42 blue:0.35 alpha:1.0];
    tabs.tabBar.unselectedItemTintColor = [UIColor secondaryLabelColor];
}
%end

static void PBWalk(UIView *view, void (^visit)(UIButton *)) {
    if ([view isKindOfClass:UIButton.class]) visit((UIButton *)view);
    for (UIView *child in view.subviews) PBWalk(child, visit);
}

void PBScanWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            PBWalk(window, ^(UIButton *button) {
                PBDiagButtonsSeen++;
                PBApplyGlass(button);
            });
        }
    }
}
