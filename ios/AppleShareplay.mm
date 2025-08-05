#import "AppleShareplay.h"
#import "AppleShareplay-Swift.h"


@interface AppleShareplay()
@property (strong, nonatomic) AppleSharePlayImpl *impl;
@property (strong, nonatomic) NSMutableArray *observers;
@end

@implementation AppleShareplay
RCT_EXPORT_MODULE()

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeAppleShareplaySpecJSI>(params);
}

-(id)init {
    if (self = [super init]) {
      self.impl = [[AppleSharePlayImpl alloc] init];
      self.observers = [[NSMutableArray alloc] init];

      // Calling `emitOnGroupSharingEligbilityChange` during init causes a bad_function_call error.
      // Avoid by delaying subscription a bit.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id observer;
        observer = [self.impl observeGroupSharingEligbility:^(BOOL success) {
          [self emitOnGroupSharingEligbilityChange:@{@"eligible": @(success)}];
        }];
        [self.observers addObject: observer];

        observer = [self.impl observeGroupActivitySession:^(NSInteger activityRef, NSInteger sessionRef) {
          [self emitOnGroupActivitySession:@{
            @"source": @(activityRef),
            @"session": @(sessionRef)
          }];
        }];
        [self.observers addObject: observer];

        observer = [self.impl observeGroupMessengerMessageReceived:^(NSInteger messengerRef, NSData * _Nonnull message) {
          [self emitOnGroupMessengerMessageReceived:@{
            @"source": @(messengerRef),
            @"message": @{
              @"type": @"incoming",
              @"data": [NSString stringWithUTF8String:(char *)[message bytes]],
            }
          }];
        }];
        [self.observers addObject: observer];

        observer = [self.impl observeGroupSessionStatus:^(NSInteger sessionRef) {
          [self emitOnGroupSessionStatusChanged:@{
            @"source": @(sessionRef)
          }];
        }];
        [self.observers addObject: observer];
      });
    }
    return self;
}

- (nonnull NSNumber *)getGroupSharingEligbility {
  return [NSNumber numberWithBool: [self.impl getGroupSharingEligibility]];
}

- (void)groupActivityActivate:(double)activity resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl activate:(NSInteger)activity completionHandler: ^(BOOL success) {
    resolve(@(success));
  }];
}

- (nonnull NSNumber *)groupActivityRegister:(JS::NativeAppleShareplay::GroupActivity &)groupActivity {
  DynamicGroupActivity *activity = [[DynamicGroupActivity alloc] initWithTitle: groupActivity.metadata().title()];
  return [NSNumber numberWithLong:[self.impl register:activity]];
}

- (nonnull NSNumber *)groupMessengerCreate:(double)session {
  return [NSNumber numberWithLong:[self.impl createMessengerOn:(NSInteger)session]];
}

- (void)groupMessengerSend:(double)messenger
                   message:(JS::NativeAppleShareplay::GroupMessengerMessageOutgoing &)message
                    target:(JS::NativeAppleShareplay::GroupMessengerParticipants &)target
                   resolve:(nonnull RCTPromiseResolveBlock)resolve
                    reject:(nonnull RCTPromiseRejectBlock)reject
{
  NSData *messageData = [message.data() dataUsingEncoding: NSUTF8StringEncoding];

  // TODO: there's only one kind of Participants currently
  assert([target.type() isEqual:@"all"]);
  GroupMessengerParticipants *participants = [[GroupMessengerParticipants alloc] init];

  [self.impl send:messageData using:(NSInteger)messenger to:participants completionHandler:^{
    resolve(nil);
  }];
}

- (NSString *)groupSessionStatus:(double)sessionRef {
  return [self.impl statusOf:(NSInteger)sessionRef];
}

- (void)groupSessionJoin:(double)sessionRef {
  [self.impl join:(NSInteger)sessionRef];
}

- (void)groupSessionLeave:(double)sessionRef {
  [self.impl leave:(NSInteger)sessionRef];
}


@end
