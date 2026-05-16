// References:
//   https://github.com/smunkelwitz/NightShiftManager
//   https://github.com/antonfisher/night-shift-cli
// License notes are tracked in Sources/Resources/ThirdPartyNotices.

#include <Foundation/Foundation.h>

typedef struct {
    int mode;    // 0 = off, 1 = scheduled (sunset to sunrise), 2 = always on
    BOOL active; // whether night shift is currently reducing blue light
    float strength; // 0.0 (less warm) to 1.0 (more warm)
    struct {
        int hour;
        int minute;
    } scheduledStart;
    struct {
        int hour;
        int minute;
    } scheduledEnd;
    int locationType;
} CBBlueLightStatus;

@interface CBBlueLightClient : NSObject
- (BOOL)getBlueLightStatus:(CBBlueLightStatus *)status;
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)setStrength:(float)strength commit:(BOOL)commit;
@end
