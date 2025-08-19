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
      dispatch_queue_t backgroundQueue = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0);
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), backgroundQueue, ^{
        id observer;
        observer = [self.impl observeGroupSharingEligbility:^(BOOL success) {
          [self emitOnGroupSharingEligbilityChange:@{@"eligible": @(success)}];
        }];
        [self.observers addObject: observer];

        observer = [self.impl observeGroupActivitySession:^(NSInteger activityRef, NSInteger sessionRef) {
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), backgroundQueue, ^{
            [self emitOnGroupActivitySession:@{
              @"source": @(activityRef),
              @"session": @(sessionRef)
            }];
          });
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
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), backgroundQueue, ^{
                                [self emitOnGroupSessionStatusChanged:@{
                                  @"source": @(sessionRef)
                                }];
          });
        }];
        [self.observers addObject: observer];
        
        observer = [self.impl observeJournalAttachments:^(NSInteger journalRef, NSArray<NSString *> * _Nonnull attachments) {
          [self emitOnGroupSessionJournalAttachments:@{
            @"source": @(journalRef),
            @"attachments": attachments
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

- (nonnull NSNumber *)groupSessionJournalCreate:(double)sessionRef {
  return [NSNumber numberWithLong:[self.impl createJournalFor:(NSInteger)sessionRef]];
}

- (void)groupSessionJournalAdd:(double)journalRef
                          item:(nonnull NSString *)item
                      metadata:(nonnull NSString *)metadata
                       resolve:(nonnull RCTPromiseResolveBlock)resolve
                        reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl addToJournal:journalRef item:item metadata:metadata completionHandler:^(NSString * _Nullable attachmentId, NSError * _Nullable error) {
    if (error) {
      reject(@"journal_add_failed", @"Failed to add item to journal", error);
    } else {
      if (attachmentId == nil) {
        reject(@"journal_add_failed", @"Unexpected missing attachment ID", nil);
      } else {
        resolve(attachmentId);
      }
    }
  }];
}

- (void)groupSessionJournalRemove:(double)journalRef
                    attachmentRef:(nonnull NSString *)attachmentRef
                          resolve:(nonnull RCTPromiseResolveBlock)resolve
                           reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl removeFromJournal:journalRef attachmentId:attachmentRef completionHandler:^(NSError * _Nullable error) {
    if (error) {
      reject(@"journal_remove_failed", @"Failed to remove journal attachment", error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)groupSessionJournalAttachmentLoad:(nonnull NSString *)attachmentRef
                                  resolve:(nonnull RCTPromiseResolveBlock)resolve
                                   reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl loadJournalAttachment:attachmentRef completionHandler:^(NSString * _Nullable item, NSError * _Nullable error) {
    if (error) {
      reject(@"journal_attachment_item_load_failed", @"Failed to load journal item", error);
    } else {
      resolve(item);
    }
  }];
}

- (void)groupSessionJournalAttachmentLoadMetadata:(nonnull NSString *)attachmentRef
                                          resolve:(nonnull RCTPromiseResolveBlock)resolve
                                           reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl loadJournalAttachmentMetadata:attachmentRef completionHandler:^(NSString * _Nullable metadata, NSError * _Nullable error) {
    if (error) {
      reject(@"journal_attachment_metadata_load_failed", @"Failed to load journal metadata", error);
    } else {
      resolve(metadata);
    }
  }];
}


@end
