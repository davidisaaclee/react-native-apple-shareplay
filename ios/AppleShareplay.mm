#import "AppleShareplay.h"
#import "AppleShareplay-Swift.h"

@implementation AppleShareplay
RCT_EXPORT_MODULE()

- (NSNumber *)multiply:(double)a b:(double)b {
    NSNumber *result = [[[SwiftFile alloc] init] multiplyByThree:@(a * b)];
    return result;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeAppleShareplaySpecJSI>(params);
}

@end
