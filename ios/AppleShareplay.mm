#import "AppleShareplay.h"
#import "AppleShareplay-Swift.h"


@interface AppleShareplay()
@property (strong, nonatomic) AppleSharePlayImpl *impl;
@property (strong, nonatomic) NSMutableArray *observers;
@property (nonatomic) BOOL needsRegisterObservers;
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
    self.needsRegisterObservers = YES;
  }
    return self;
}

- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)eventEmitterCallbackWrapper
{
  [super setEventEmitterCallback:eventEmitterCallbackWrapper];
  // Now that we're guaranteed event emitter setup, register observers (which may fire on attach).
  [self registerObserversIfNeeded];
}

- (void)registerObserversIfNeeded
{
  if (!self.needsRegisterObservers) {
    return;
  }
  
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
  
  observer = [self.impl observeGroupMessengerMessageReceived:^(NSInteger messengerRef, NSData * _Nonnull message, NSString * _Nonnull senderId) {
    [self emitOnGroupMessengerMessageReceived:@{
      @"source": @(messengerRef),
      @"message": [NSString stringWithUTF8String:(char *)[message bytes]],
      @"sender": @{@"id": senderId},
    }];
  }];
  [self.observers addObject: observer];
  
  observer = [self.impl observeGroupSessionStatus:^(NSInteger sessionRef) {
    [self emitOnGroupSessionStatusChanged:@{
      @"source": @(sessionRef)
    }];
  }];
  [self.observers addObject: observer];
  
  observer = [self.impl observeJournalAttachments:^(NSInteger journalRef, NSArray<NSString *> * _Nonnull attachments) {
    [self emitOnGroupSessionJournalAttachments:@{
      @"source": @(journalRef),
      @"attachments": attachments
    }];
  }];
  [self.observers addObject: observer];
  
  observer = [self.impl observeActiveParticipants:^(NSInteger sessionRef, NSArray<NSString *> * _Nonnull activeParticipants) {
    NSMutableArray *participants = [NSMutableArray arrayWithCapacity:activeParticipants.count];
    for (NSString *participantId in activeParticipants) {
      [participants addObject:@{@"id": participantId}];
    }
    
    [self emitOnActiveParticipantsChange:@{
      @"source": @(sessionRef),
      @"participants": participants
    }];
  }];
  [self.observers addObject: observer];
  
  self.needsRegisterObservers = NO;
}

- (nonnull NSNumber *)getGroupSharingEligbility {
  return [NSNumber numberWithBool: [self.impl getGroupSharingEligibility]];
}

- (void)groupActivityActivate:(double)activity resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject {
  [self.impl activate:(NSInteger)activity completionHandler: ^(BOOL success) {
    resolve(@{@"succeeded": @(success)});
  }];
}

- (nonnull NSNumber *)groupActivityRegister:(JS::NativeAppleShareplay::GroupActivity &)groupActivity {
  DynamicGroupActivity *activity = [[DynamicGroupActivity alloc] initWithTitle: groupActivity.metadata().title()];
  return [NSNumber numberWithLong:[self.impl register:activity]];
}

- (nonnull NSNumber *)groupMessengerCreate:(double)session {
  return [NSNumber numberWithLong:[self.impl createMessengerOn:(NSInteger)session]];
}

- (GroupMessengerParticipants *)participantsFrom:(NSArray *)target
{
  if (target == nil) {
    return [[GroupMessengerParticipantsAll alloc] init];
  }
  
  NSMutableSet *participantIds = [[NSMutableSet alloc] init];
  for (NSString *participantId in participantIds) {
    [participantIds addObject:@{@"id": participantId}];
  }
  return [[GroupMessengerParticipantsOnly alloc] initWithParticipantIds:participantIds];
}

- (void)groupMessengerSend:(double)messenger
                   message:(NSString *)message
                    target:(NSArray *)target
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject
{
  NSData *messageData = [message dataUsingEncoding: NSUTF8StringEncoding];
  GroupMessengerParticipants *participants = [self participantsFrom:target];
  
  [self.impl send:messageData using:(NSInteger)messenger to:participants completionHandler:^(NSError * _Nullable error) {
    if (error) {
      reject(@"messenger_send_failed", @"Failed to send message", error);
    } else {
      resolve(nil);
    }
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
                          item:(NSString *)item
                      metadata:(NSString *)metadata
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject
{
  [self.impl addToJournal:(NSInteger)journalRef item:item metadata:metadata completionHandler:^(NSString * _Nullable attachmentId, NSError * _Nullable error) {
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

- (nonnull NSArray<NSDictionary *> *)groupSessionActiveParticipants:(double)sessionRef {
  NSError *error;
  NSArray *participantIds = [self.impl activeParticipantsIn:(NSInteger)sessionRef error:&error];
  if (error) {
    throw error;
  }
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:participantIds.count];
  for (NSString *participantId in participantIds) {
    [result addObject:@{@"id": participantId}];
  }
  return result;
}


- (nonnull NSDictionary *)groupSessionLocalParticipant:(double)sessionRef {
  NSError *error;
  NSString *localParticipantId = [self.impl localParticipantIn:(NSInteger)sessionRef error:&error];
  if (error) {
    throw error;
  }
  return @{@"id": localParticipantId};
}

@end
