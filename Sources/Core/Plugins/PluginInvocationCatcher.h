#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPluginInvocationCatcher : NSObject

+ (nullable NSException *)catchExceptionInBlock:(NS_NOESCAPE void (^)(void))block
    NS_SWIFT_NAME(catchException(in:));

@end

NS_ASSUME_NONNULL_END
