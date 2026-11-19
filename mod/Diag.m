#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PBMod.h"

// Probe build: the user reports the tweak loads but nothing it should do is
// visible, so dump the facts once on screen instead of guessing.

int PBDiagHookFired;
int PBDiagGlassApplied;
int PBDiagEligible;
int PBDiagButtonsSeen;
int PBDiagViewsSeen;
int PBDiagControlsSeen;
BOOL PBGlassEnabled = NO;
BOOL PBDiagShown;

static NSString *PBClassState(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) return @"ABSENTE";
    unsigned int count = 0;
    free(class_copyMethodList(cls, &count));
    return [NSString stringWithFormat:@"présente, %u méthodes", count];
}

@interface PBDiagViewController : UIViewController
@end

@implementation PBDiagViewController {
    UITextView *_text;
    NSString *_report;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Diagnostic PaperbackMod";

    _text = [[UITextView alloc] initWithFrame:CGRectZero];
    _text.editable = NO;
    _text.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _text.text = _report;
    _text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_text];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_text.topAnchor constraintEqualToAnchor:area.topAnchor constant:12],
        [_text.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:12],
        [_text.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-12],
        [_text.bottomAnchor constraintEqualToAnchor:area.bottomAnchor constant:-12],
    ]];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:self
                                                     action:@selector(pbDone)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                     target:self
                                                     action:@selector(pbShare)];
    UIBarButtonItem *glass = [[UIBarButtonItem alloc] initWithTitle:@"Verre"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(pbGlass)];
    self.navigationItem.leftBarButtonItems = @[self.navigationItem.leftBarButtonItem, glass];
}

- (void)pbGlass {
    PBGlassEnabled = YES;
    PBScanView(self.view.window);
    _text.text = [_text.text stringByAppendingFormat:
                  @"\nverre ON -> vues %d, controls %d, boutons %d, éligibles %d, appliqués %d\n",
                  PBDiagViewsSeen, PBDiagControlsSeen, PBDiagButtonsSeen, PBDiagEligible, PBDiagGlassApplied];
}

- (void)setReport:(NSString *)report {
    _report = [report copy];
}

- (void)pbDone {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pbShare {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[_text.text ?: @""] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

@end

static UIViewController *PBTopViewController(void) {
    UIWindow *window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) window = candidate;
        }
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

void PBShowDiag(id host, id tabList) {
    if (PBDiagShown) return;
    PBDiagShown = YES;

    UIViewController *presenter = host ?: PBTopViewController();
    if (!presenter || presenter.presentedViewController) {
        // Something is already up (notification permission alert, launch sheet):
        // back off and retry rather than giving up for good.
        static int attempts;
        if (++attempts > 30) return;
        PBDiagShown = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            PBShowDiag(nil, tabList);
        });
        return;
    }

    Class glass = objc_getClass("UIGlassEffect");
    SEL make = NSSelectorFromString(@"effectWithStyle:");
    BOOL canMake = glass && [glass respondsToSelector:make];
    id sample;
    if (canMake) {
        id (*build)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))[glass methodForSelector:make];
        sample = build(glass, make, 0);
    }

    // Scan the window the presenting controller actually lives in: on device the
    // scene list came back empty, which is why the walk found nothing.
    NSUInteger scenes = 0, windows = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        scenes++;
        windows += ((UIWindowScene *)scene).windows.count;
    }
    PBScanView(presenter.view.window ?: presenter.view);

    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"iOS %@\n", UIDevice.currentDevice.systemVersion];
    [report appendString:@"tweak chargé: oui\n"];
    [report appendFormat:@"didMoveToWindow: %d appels\n", PBDiagHookFired];
    [report appendFormat:@"verre appliqué: %d boutons\n", PBDiagGlassApplied];
    [report appendFormat:@"boutons éligibles: %d\n", PBDiagEligible];
    [report appendFormat:@"boutons vus: %d\n", PBDiagButtonsSeen];
    [report appendFormat:@"scènes/fenêtres: %lu/%lu\n", (unsigned long)scenes, (unsigned long)windows];
    [report appendFormat:@"vues parcourues: %d\n", PBDiagViewsSeen];
    [report appendFormat:@"controls (UIControl): %d\n", PBDiagControlsSeen];
    UIViewController *root = presenter.view.window.rootViewController;
    [report appendFormat:@"racine: %@\n", root ? NSStringFromClass(root.class) : @"(aucune)"];
    [report appendFormat:@"enfants racine: %lu\n", (unsigned long)root.childViewControllers.count];
    [report appendFormat:@"UIGlassEffect: %@\n", PBClassState("UIGlassEffect")];
    [report appendFormat:@"effectWithStyle:: %@\n", canMake ? @"présente" : @"ABSENTE"];
    [report appendFormat:@"style 0 -> %@\n", sample ? NSStringFromClass([sample class]) : @"nil"];
    [report appendFormat:@"MainTabViewController: %@\n", PBClassState("_TtC9Paperback21MainTabViewController")];
    [report appendFormat:@"LibraryViewController: %@\n", PBClassState("_TtC9Paperback21LibraryViewController")];
    Class library = objc_getClass("_TtC9Paperback21LibraryViewController");
    [report appendFormat:@"didRefreshCollectionView:: %@\n",
        (library && class_getInstanceMethod(library, NSSelectorFromString(@"didRefreshCollectionView:"))) ? @"trouvée" : @"ABSENTE"];
    [report appendFormat:@"onglets: %@\n", tabList ?: @"viewDidAppear jamais appelé"];

    PBDiagViewController *diag = [PBDiagViewController new];
    diag.report = report;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:diag];
    [presenter presentViewController:nav animated:YES completion:nil];
}
