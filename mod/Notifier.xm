#import <UserNotifications/UserNotifications.h>

// Central place for the local-notification plumbing. Nothing here knows about
// Paperback; the hooks call in.

// The app sets no UNUserNotificationCenter delegate, so banners would be
// suppressed while it is in the foreground. This one shows them and defers to
// any delegate the app would install later.
@interface PBNotificationPresenter : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation PBNotificationPresenter

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    if (@available(iOS 14.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList
                          | UNNotificationPresentationOptionSound);
    } else {
        completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
    }
}

@end

void PBRequestAuth(void) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    static PBNotificationPresenter *presenter;
    if (!presenter) {
        presenter = [PBNotificationPresenter new];
        if (!center.delegate) center.delegate = presenter;
    }
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError *error) {
        if (!granted && error) NSLog(@"[PaperbackMod] notif auth failed: %@", error);
    }];
}

void PBPostLocalNotification(NSString *title, NSString *body, NSString *thread) {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title ?: @"Paperback";
    content.body = body ?: @"";
    content.sound = [UNNotificationSound defaultSound];
    if (thread.length) content.threadIdentifier = thread;

    // nil trigger = deliver now
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:[NSUUID UUID].UUIDString
                                                                     content:content
                                                                     trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req
                                                           withCompletionHandler:^(NSError *error) {
        if (error) NSLog(@"[PaperbackMod] post failed: %@", error);
    }];
}
