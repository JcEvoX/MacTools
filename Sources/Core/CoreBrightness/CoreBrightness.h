// References:
//   https://github.com/smunkelwitz/NightShiftManager
//   https://github.com/antonfisher/night-shift-cli
// License notes are tracked in Sources/Resources/ThirdPartyNotices.

#include <Foundation/Foundation.h>

typedef struct {
    BOOL active; // whether night shift is currently reducing blue light
    BOOL enabled;
    BOOL sunSchedulePermitted;
    int mode; // 0 = off, 1 = scheduled (sunset to sunrise), 2 = always on
    struct {
        int hour;
        int minute;
    } scheduledStart, scheduledEnd;
    unsigned long long disableFlags;
    BOOL available;
} CBBlueLightStatus;

@interface CBBlueLightClient : NSObject
- (BOOL)getBlueLightStatus:(CBBlueLightStatus *)status;
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)setStrength:(float)strength commit:(BOOL)commit;
@end
