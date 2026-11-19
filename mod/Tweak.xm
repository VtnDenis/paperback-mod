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

static NSString *PBTabNames(UITabBarController *tabs) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger i = 0; i < tabs.viewControllers.count; i++) {
        UIViewController *vc = tabs.viewControllers[i];
        [names addObject:[NSString stringWithFormat:@"%lu:%@(%@)",
                          (unsigned long)i, NSStringFromClass(vc.class), vc.tabBarItem.title ?: @"?"]];
    }
    return [names componentsJoinedByString:@", "];
}

// Class name first, then the tab title: the app may wrap or rename its tab
// controllers, and the label the user sees is the reliable signal.
static NSInteger PBFindLibraryTab(UITabBarController *tabs) {
    NSInteger byClass = PBIndexOfController(tabs.viewControllers, @"LibraryViewController");
    if (byClass != NSNotFound) return byClass;
    for (NSUInteger i = 0; i < tabs.tabBar.items.count; i++) {
        NSString *title = tabs.tabBar.items[i].title.lowercaseString ?: @"";
        if ([title containsString:@"library"] || [title containsString:@"biblioth"]) return (NSInteger)i;
    }
    for (NSUInteger i = 0; i < tabs.viewControllers.count; i++) {
        NSString *title = tabs.viewControllers[i].tabBarItem.title.lowercaseString ?: @"";
        if ([title containsString:@"library"] || [title containsString:@"biblioth"]) return (NSInteger)i;
    }
    return NSNotFound;
}

static void PBJumpToLibrary(UITabBarController *tabs, int attempt) {
    NSInteger library = PBFindLibraryTab(tabs);
    PBSetVerdict(@"saut", [NSString stringWithFormat:@"essai %d, tabs %lu, index %ld | %@",
                           attempt, (unsigned long)tabs.viewControllers.count, (long)library, PBTabNames(tabs)]);
    if (library == NSNotFound) {
        // The tabs are attached after viewDidAppear: returns (the probe saw 0
        // children there), so a single shot always misses.
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                PBJumpToLibrary(tabs, attempt + 1);
            });
        }
        return;
    }
    if (tabs.selectedIndex != library) tabs.selectedIndex = library;
    // No tabBar.selectedItem here: setting an item the bar hasn't registered yet
    // raises NSException from UIKit and killed the app at launch (ips: setSelectedItem:).
    PBSetVerdict(@"saut", [NSString stringWithFormat:@"OK index %ld -> sel %ld", (long)library, (long)tabs.selectedIndex]);
    if (!PBDiagShown) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (UIViewController *child in tabs.viewControllers) [names addObject:NSStringFromClass(child.class)];
        PBSetVerdict(@"onglets", [NSString stringWithFormat:@"%lu -> %@ (saut: %ld)",
                                  (unsigned long)names.count, [names componentsJoinedByString:@", "], (long)library]);
        PBReportSummaryRemote();
        PBShowDiag();
    }
}

%hook _TtC9Paperback21MainTabViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PBLogHook(@"tab.viewDidAppear");
    // Once only: viewDidAppear fires again after modal sheets, and resetting the
    // tab every time would fight the user.
    static BOOL jumped;
    if (jumped) return;
    jumped = YES;
    PBJumpToLibrary((UITabBarController *)self, 0);
}

// The tab list is assigned through this setter: hooking it means the jump no
// longer depends on when viewDidAppear happens to run.
- (void)setViewControllers:(NSArray *)controllers {
    %orig;
    PBLogHook(@"tab.setViewControllers");
    static BOOL jumped;
    if (jumped || !controllers.count) return;
    jumped = YES;
    PBJumpToLibrary((UITabBarController *)self, 0);
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
    PBDiagRefreshTicks++;
    if (PBRefreshInFlight() || !PBLibraryViewController) return;
    if ([NSDate date].timeIntervalSince1970 - PBLastRefresh < PBRefreshInterval) return;
    PBLastRefresh = [NSDate date].timeIntervalSince1970;
    SEL refresh = NSSelectorFromString(@"didRefreshCollectionView:");
    void (*call)(id, SEL, id) = (void (*)(id, SEL, id))[(id)PBLibraryViewController methodForSelector:refresh];
    if (!call) return;
    PBDiagRefreshes++;
    PBLogHook(@"library.didRefreshCollectionView:");
    call(PBLibraryViewController, refresh, nil);
}

%hook _TtC9Paperback21LibraryViewController

- (void)viewDidLoad {
    %orig;
    PBLogHook(@"library.viewDidLoad");
    PBLibraryViewController = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!PBDiagShown) {
            PBSetVerdict(@"onglets", @"JAMAIS (repli Library)");
            PBShowDiag();
        }
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
    PBDiagNotifications++;
    PBLogHook(@"notif.posted");
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
    PBLogHook(@"updater.viewDidLoad");
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
    PBLogHook(@"updater.numberOfRowsInSection:");
    if (rows > 0) {
        PBCounts[@(section)] = @(rows);
        PBScheduleFlush();
    }
    return rows;
}

- (NSString *)tableView:(id)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *title = %orig;
    if (title.length) {
        PBTitles[@(section)] = title;
        PBLogHook(@"updater.titleForHeaderInSection:");
    }
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
    PBDiagViewsSeen++;
    if ([view isKindOfClass:UIControl.class]) PBDiagControlsSeen++;
    if ([view isKindOfClass:UIButton.class]) visit((UIButton *)view);
    for (UIView *child in view.subviews) PBWalk(child, visit);
}

void PBScanView(id root) {
    if (![root isKindOfClass:UIView.class]) return;
    // Counters are per scan: cumulative totals made every later report look
    // like the UI had grown when it was the same walk plus the previous one.
    PBDiagViewsSeen = PBDiagControlsSeen = PBDiagButtonsSeen = 0;
    PBWalk(root, ^(UIButton *button) {
        PBDiagButtonsSeen++;
        PBApplyGlass(button);
    });
}

void PBScanWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            PBScanView(window);
        }
    }
}
