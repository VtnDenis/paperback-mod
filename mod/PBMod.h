#import <Foundation/Foundation.h>

// C linkage on purpose: KeepAlive.m is plain C, the .xm files are compiled as
// ObjC++. Without this header the calls mangle to __Z13PBRequestAuthv while the
// definitions stay _PBKeepAliveStop, so the lazy binder resolves them to 0 and
// the app jumps to address 0 when the block runs.
#ifdef __cplusplus
extern "C" {
#endif

void PBRequestAuth(void);
void PBPostLocalNotification(NSString *title, NSString *body, NSString *thread);
void PBKeepAliveStart(void);
void PBKeepAliveStop(void);
BOOL PBKeepAliveActive(void);

// One full report instead of another round of guesses: every hook counts itself,
// a 1 s timeline records what the window looks like, and each feature leaves a
// verdict line.
void PBLogHook(NSString *name);
void PBSetVerdict(NSString *key, NSString *value);
void PBStartDiagTimeline(void);
void PBShowDiag(id host, id tabList);

extern int PBDiagGlassApplied;
extern int PBDiagEligible;
extern int PBDiagButtonsSeen;
extern int PBDiagViewsSeen;
extern int PBDiagControlsSeen;
extern int PBDiagRefreshTicks;
extern int PBDiagRefreshes;
extern int PBDiagNotifications;
extern int PBDiagKeepAliveStarts;
extern int PBDiagKeepAliveStops;
extern BOOL PBDiagShown;
extern BOOL PBGlassEnabled;

void PBScanWindows(void);
void PBScanView(id root);

#ifdef __cplusplus
}
#endif
