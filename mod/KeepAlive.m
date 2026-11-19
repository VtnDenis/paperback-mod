#import <AVFoundation/AVFoundation.h>
#import "PBMod.h"

// Paperback downloads with in-memory URLSession tasks only: when iOS suspends
// the app the queue dies. The plist declares the audio background mode, so a
// silent looping player keeps the process running until downloads finish.
static AVAudioPlayer *PBPlayer;

static NSData *PBSilentWAV(void) {
    const uint32_t rate = 8000;
    const uint32_t dataSize = rate * 2;  // 1 s, mono, 16-bit
    NSMutableData *wav = [NSMutableData dataWithCapacity:44 + dataSize];
    uint32_t u32;
    uint16_t u16;
    [wav appendBytes:"RIFF" length:4];
    u32 = 36 + dataSize; [wav appendBytes:&u32 length:4];
    [wav appendBytes:"WAVEfmt " length:8];
    u32 = 16; [wav appendBytes:&u32 length:4];
    u16 = 1; [wav appendBytes:&u16 length:2];
    u16 = 1; [wav appendBytes:&u16 length:2];
    [wav appendBytes:&rate length:4];
    u32 = rate * 2; [wav appendBytes:&u32 length:4];
    u16 = 2; [wav appendBytes:&u16 length:2];
    u16 = 16; [wav appendBytes:&u16 length:2];
    [wav appendBytes:"data" length:4];
    [wav appendBytes:&dataSize length:4];
    [wav increaseLengthBy:dataSize];
    return wav;
}

void PBKeepAliveStart(void) {
    PBDiagKeepAliveStarts++;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (PBPlayer) return;
        AVAudioSession *session = AVAudioSession.sharedInstance;
        NSError *error = nil;
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:&error];
        [session setActive:YES error:&error];
        PBPlayer = [[AVAudioPlayer alloc] initWithData:PBSilentWAV() error:&error];
        if (!PBPlayer) {
            NSLog(@"[PaperbackMod] keep-alive player failed: %@", error);
            return;
        }
        PBPlayer.numberOfLoops = -1;
        PBPlayer.volume = 0;
        [PBPlayer play];
    });
}

void PBKeepAliveStop(void) {
    PBDiagKeepAliveStops++;
    dispatch_async(dispatch_get_main_queue(), ^{
        [PBPlayer stop];
        PBPlayer = nil;
        [AVAudioSession.sharedInstance setActive:NO
                                    withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                          error:nil];
    });
}

BOOL PBKeepAliveActive(void) {
    return PBPlayer.isPlaying;
}
