#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import "PBMod.h"

// Everything the tweak decides is recorded here, so a single report answers
// "what happened" without another build. Nothing in this file changes behaviour
// except the Verre button (which turns the dry run off).

int PBDiagGlassApplied;
int PBDiagEligible;
int PBDiagButtonsSeen;
int PBDiagViewsSeen;
int PBDiagControlsSeen;
int PBDiagRefreshTicks;
int PBDiagRefreshes;
int PBDiagNotifications;
int PBDiagKeepAliveStarts;
int PBDiagKeepAliveStops;
BOOL PBGlassEnabled = NO;
BOOL PBDiagShown;

static NSMutableDictionary<NSString *, NSNumber *> *PBHooks;
static NSMutableDictionary<NSString *, NSString *> *PBVerdicts;
static NSMutableArray<NSString *> *PBTimeline;

void PBLogHook(NSString *name) {
    if (!PBHooks) PBHooks = [NSMutableDictionary dictionary];
    PBHooks[name] = @(PBHooks[name].intValue + 1);
}

void PBSetVerdict(NSString *key, NSString *value) {
    if (!PBVerdicts) PBVerdicts = [NSMutableDictionary dictionary];
    PBVerdicts[key] = value ?: @"-";
}

#pragma mark - Window and view inspection

static UIWindow *PBKeyWindow(void) {
    UIWindow *fallback;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
            if (!fallback) fallback = window;
        }
    }
    return fallback ?: UIApplication.sharedApplication.windows.firstObject;
}

static int PBCountViews(UIView *view, int *controls, int *buttons) {
    int total = 1;
    if ([view isKindOfClass:UIControl.class]) (*controls)++;
    if ([view isKindOfClass:UIButton.class]) (*buttons)++;
    for (UIView *child in view.subviews) total += PBCountViews(child, controls, buttons);
    return total;
}

static NSString *PBSnapshotLine(int tick) {
    UIWindow *window = PBKeyWindow();
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    UITabBarController *tabs = [root isKindOfClass:UITabBarController.class] ? (UITabBarController *)root : nil;
    NSInteger library = -1;
    if (tabs) {
        for (NSUInteger i = 0; i < tabs.viewControllers.count; i++) {
            if ([NSStringFromClass([tabs.viewControllers[i] class]) containsString:@"LibraryViewController"]) {
                library = (NSInteger)i;
            }
        }
    }
    int controls = 0, buttons = 0;
    int views = window ? PBCountViews(window, &controls, &buttons) : 0;
    return [NSString stringWithFormat:@"t=%-2d racine=%@ enfants=%lu tabs=%lu lib=%ld sel=%ld vues=%d ctrl=%d btn=%d",
            tick,
            root ? NSStringFromClass(root.class) : @"-",
            (unsigned long)root.childViewControllers.count,
            (unsigned long)(tabs ? tabs.viewControllers.count : 0),
            (long)library,
            (long)(tabs ? tabs.selectedIndex : -1),
            views, controls, buttons];
}

void PBStartDiagTimeline(void) {
    if (PBTimeline) return;
    PBTimeline = [NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(), ^{
        __block int tick = 0;
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            [PBTimeline addObject:PBSnapshotLine(tick)];
            if (++tick >= 40) [timer invalidate];
        }];
    });
}

// Only the nodes that carry meaning for this tweak: buttons, controls, bars,
// cells, and the first two levels of structure.
static BOOL PBInteresting(NSString *name, int depth) {
    if (depth < 2) return YES;
    for (NSString *needle in @[@"Button", @"Control", @"Bar", @"Cell", @"Switch", @"Segment", @"TextView", @"Field"]) {
        if ([name containsString:needle]) return YES;
    }
    return NO;
}

static void PBDumpView(UIView *view, int depth, NSMutableString *out) {
    if (out.length > 12000 || depth > 14) return;
    NSString *name = NSStringFromClass(view.class);
    if (PBInteresting(name, depth)) {
        CGRect f = view.frame;
        NSString *flags = @"";
        if (view.hidden) flags = @" hidden";
        else if (view.alpha < 0.05) flags = @" alpha0";
        [out appendFormat:@"%*s%@ %.0fx%.0f@%.0f,%.0f%@\n", depth * 2, "", name,
                        f.size.width, f.size.height, f.origin.x, f.origin.y, flags];
    }
    for (UIView *child in view.subviews) PBDumpView(child, depth + 1, out);
}

static void PBCollectButtons(UIView *view, NSMutableArray<NSString *> *lines) {
    if (lines.count > 40) return;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        BOOL hasFill = NO;
        CGFloat alpha = 0;
        [button.backgroundColor getRed:nil green:nil blue:nil alpha:&alpha];
        hasFill = alpha > 0.01;
        [lines addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f fond=%@ bordure=%.0f%s",
                          NSStringFromClass(button.class), button.bounds.size.width, button.bounds.size.height,
                          hasFill ? @"oui" : @"non", button.layer.borderWidth,
                          button.isHidden ? " hidden" : ""]];
    }
    for (UIView *child in view.subviews) PBCollectButtons(child, lines);
}

static NSString *PBClassState(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) return @"ABSENTE";
    unsigned int count = 0;
    free(class_copyMethodList(cls, &count));
    return [NSString stringWithFormat:@"présente (%u méthodes)", count];
}

#pragma mark - Report screen

@interface PBDiagViewController : UIViewController
@property (nonatomic, copy) NSString *report;
@end

@implementation PBDiagViewController {
    UITextView *_text;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"PaperbackMod";

    _text = [[UITextView alloc] initWithFrame:CGRectZero];
    _text.editable = NO;
    _text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _text.text = self.report;
    _text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_text];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_text.topAnchor constraintEqualToAnchor:area.topAnchor constant:8],
        [_text.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:8],
        [_text.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-8],
        [_text.bottomAnchor constraintEqualToAnchor:area.bottomAnchor constant:-8],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                     target:self
                                                     action:@selector(pbShare)];
    UIBarButtonItem *glass = [[UIBarButtonItem alloc] initWithTitle:@"Verre"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(pbGlass)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                         target:self
                                                                         action:@selector(pbDone)];
    self.navigationItem.leftBarButtonItems = @[done, glass];
}

- (void)appendText:(NSString *)text {
    _text.text = [_text.text stringByAppendingString:text];
}

- (void)pbGlass {
    PBGlassEnabled = YES;
    PBScanView(self.view.window);
    [self appendText:[NSString stringWithFormat:@"\n[verre ON] vues=%d ctrl=%d btn=%d éligibles=%d appliqués=%d\n",
                      PBDiagViewsSeen, PBDiagControlsSeen, PBDiagButtonsSeen, PBDiagEligible, PBDiagGlassApplied]];
}

- (void)pbDone {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pbShare {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[_text.text ?: @""]
                                                                      applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

@end

#pragma mark - Report assembly

static void PBAppendSection(NSMutableString *report, NSString *title) {
    [report appendFormat:@"\n=== %@ ===\n", title];
}

void PBShowDiag(id host, id tabList) {
    if (PBDiagShown) return;
    PBDiagShown = YES;

    UIViewController *presenter = host;
    if ([presenter isKindOfClass:UIViewController.class] && !presenter.view.window) presenter = nil;
    if (!presenter) presenter = PBKeyWindow().rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter) {
        static int attempts;
        if (++attempts < 30) {
            PBDiagShown = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                PBShowDiag(nil, tabList);
            });
        }
        return;
    }

    UIWindow *window = PBKeyWindow();
    UIViewController *root = window.rootViewController;
    UITabBarController *tabs = [root isKindOfClass:UITabBarController.class] ? (UITabBarController *)root : nil;
    PBScanView(window);

    NSMutableString *report = [NSMutableString string];

    PBAppendSection(report, @"RUNTIME");
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    [report appendFormat:@"iOS %@\napp %@ (%@)\nmodèle %@\n",
     UIDevice.currentDevice.systemVersion,
     info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"],
     UIDevice.currentDevice.model];
    [report appendFormat:@"UIBackgroundModes %@\n", info[@"UIBackgroundModes"]];
    [report appendFormat:@"UIDesignRequiresCompatibility %@\n", info[@"UIDesignRequiresCompatibility"]];
    [report appendFormat:@"racine %@\nenfants racine %lu\ntabs %lu sel %ld\n",
     root ? NSStringFromClass(root.class) : @"-",
     (unsigned long)root.childViewControllers.count,
     (unsigned long)(tabs ? tabs.viewControllers.count : 0),
     (long)(tabs ? tabs.selectedIndex : -1)];

    PBAppendSection(report, @"TIMELINE 1s");
    for (NSString *line in PBTimeline) [report appendFormat:@"%@\n", line];
    if (!PBTimeline.count) [report appendString:@"(aucune mesure)\n"];

    PBAppendSection(report, @"HOOKS");
    if (!PBHooks.count) [report appendString:@"aucun hook appelé\n"];
    for (NSString *name in [PBHooks.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [report appendFormat:@"%@ %@\n", name, PBHooks[name]];
    }

    PBAppendSection(report, @"VERDICTS");
    [report appendFormat:@"onglets: %@\n", tabList ?: @"-"];
    for (NSString *key in [PBVerdicts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [report appendFormat:@"%@: %@\n", key, PBVerdicts[key]];
    }

    PBAppendSection(report, @"LIBRARY TAB");
    [report appendFormat:@"MainTab %@\nLibrary %@\n", PBClassState("_TtC9Paperback21MainTabViewController"),
     PBClassState("_TtC9Paperback21LibraryViewController")];
    Class libraryClass = objc_getClass("_TtC9Paperback21LibraryViewController");
    [report appendFormat:@"didRefreshCollectionView: %@\n",
     (libraryClass && class_getInstanceMethod(libraryClass, NSSelectorFromString(@"didRefreshCollectionView:"))) ? @"trouvée" : @"ABSENTE"];

    PBAppendSection(report, @"REFRESH");
    [report appendFormat:@"ticks %d\nrefreshs %d\nupdater relancé %d\n",
     PBDiagRefreshTicks, PBDiagRefreshes, PBDiagNotifications];

    PBAppendSection(report, @"KEEP-ALIVE");
    [report appendFormat:@"starts %d\nstops %d\nsession audio %@\n",
     PBDiagKeepAliveStarts, PBDiagKeepAliveStops, PBKeepAliveActive() ? @"active" : @"inactive"];

    PBAppendSection(report, @"NOTIFS");
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [report appendFormat:@"delegate %@\npostées %d\n",
     center.delegate ? NSStringFromClass([center.delegate class]) : @"aucun", PBDiagNotifications];

    PBAppendSection(report, @"LIQUID GLASS");
    [report appendFormat:@"UIGlassEffect %@\n", PBClassState("UIGlassEffect")];
    Class glass = objc_getClass("UIGlassEffect");
    SEL make = NSSelectorFromString(@"effectWithStyle:");
    [report appendFormat:@"effectWithStyle: %@\n", (glass && [glass respondsToSelector:make]) ? @"présente" : @"ABSENTE"];
    if (glass && [glass respondsToSelector:make]) {
        id (*build)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))[glass methodForSelector:make];
        id sample = build(glass, make, 0);
        [report appendFormat:@"style 0 -> %@\n", sample ? NSStringFromClass([sample class]) : @"nil"];
    }
    [report appendFormat:@"boutons vus %d / éligibles %d / appliqués %d (dry run: %@)\n",
     PBDiagButtonsSeen, PBDiagEligible, PBDiagGlassApplied, PBGlassEnabled ? @"non" : @"oui"];

    PBAppendSection(report, @"BOUTONS");
    NSMutableArray<NSString *> *buttons = [NSMutableArray array];
    PBCollectButtons(window, buttons);
    if (!buttons.count) [report appendString:@"aucun UIButton dans la fenêtre\n"];
    for (NSString *line in buttons) [report appendFormat:@"%@\n", line];

    PBAppendSection(report, @"HIÉRARCHIE");
    PBDumpView(window, 0, report);

    PBDiagViewController *diag = [PBDiagViewController new];
    diag.report = report;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:diag];
    [presenter presentViewController:nav animated:YES completion:nil];

    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [diag appendText:[NSString stringWithFormat:@"\n[notifs] autorisation=%ld alerte=%ld son=%ld badge=%ld\n",
                              (long)settings.authorizationStatus, (long)settings.alertSetting,
                              (long)settings.soundSetting, (long)settings.badgeSetting]];
        });
    }];
}
