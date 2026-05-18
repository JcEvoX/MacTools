#import "PluginInvocationCatcher.h"

@implementation MTPluginInvocationCatcher

+ (nullable NSException *)catchExceptionInBlock:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}

@end
