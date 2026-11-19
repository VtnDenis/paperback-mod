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

// Probe build only.
extern int PBDiagHookFired;
extern int PBDiagGlassApplied;
extern BOOL PBDiagShown;
void PBShowDiag(id host, id tabList);

#ifdef __cplusplus
}
#endif
