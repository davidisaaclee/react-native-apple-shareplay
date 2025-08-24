import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { EventEmitter } from 'react-native/Libraries/Types/CodegenTypes';

export type GroupMessengerRef = number;
export type GroupSessionRef = number;
export type GroupActivityRef = number;
export type GroupSessionJournalRef = number;
export type GroupSessionJournalAttachmentRef = string; // GroupSessionJournal.Attachment.id in Swift

export type GroupSessionJournalItem = string;
export type GroupSessionJournalItemMetadata = string;

export const GroupMessengerParticipantsAll = null;
export type GroupMessengerParticipants =
  | typeof GroupMessengerParticipantsAll
  | Participant[];

export type GroupMessengerMessage = string;

export enum GroupSessionStatus {
  invalidated = 'invalidated',
  joined = 'joined',
  waiting = 'waiting',
}

export interface GroupActivity {
  metadata: { title: string };
}

export interface Participant {
  id: string;
}

export interface Spec extends TurboModule {
  groupSessionJoin(sessionRef: GroupSessionRef): void;
  groupSessionLeave(sessionRef: GroupSessionRef): void;
  groupSessionStatus(sessionRef: GroupSessionRef): GroupSessionStatus;
  readonly onGroupSessionStatusChanged: EventEmitter<{
    source: GroupSessionRef;
  }>;

  getGroupSharingEligbility(): boolean;
  readonly onGroupSharingEligbilityChange: EventEmitter<{ eligible: boolean }>;

  groupActivityRegister(groupActivity: GroupActivity): GroupActivityRef;
  groupActivityActivate(
    activity: GroupActivityRef
  ): Promise<{ succeeded: boolean }>;

  readonly onGroupActivitySession: EventEmitter<{
    source: GroupActivityRef;
    session: GroupSessionRef;
  }>;

  groupMessengerCreate(session: GroupSessionRef): GroupMessengerRef;
  groupMessengerSend(
    messenger: GroupMessengerRef,
    message: GroupMessengerMessage,
    target: GroupMessengerParticipants
  ): Promise<void>;
  readonly onGroupMessengerMessageReceived: EventEmitter<{
    source: GroupMessengerRef;
    message: GroupMessengerMessage;
    sender: Participant;
  }>;

  // Automatically subscribes to attachments stream. There is currently no way
  // to unsubscribe.
  groupSessionJournalCreate(
    sessionRef: GroupSessionRef
  ): GroupSessionJournalRef;
  groupSessionJournalAdd(
    journalRef: GroupSessionJournalRef,
    item: GroupSessionJournalItem,
    metadata: GroupSessionJournalItemMetadata | null
  ): Promise<GroupSessionJournalAttachmentRef>;
  groupSessionJournalRemove(
    journalRef: GroupSessionJournalRef,
    attachmentRef: GroupSessionJournalAttachmentRef
  ): Promise<void>;
  readonly onGroupSessionJournalAttachments: EventEmitter<{
    source: GroupSessionJournalRef;
    attachments: GroupSessionJournalAttachmentRef[];
  }>;

  groupSessionJournalAttachmentLoad(
    attachmentRef: GroupSessionJournalAttachmentRef
  ): Promise<GroupSessionJournalItem>;
  groupSessionJournalAttachmentLoadMetadata(
    attachmentRef: GroupSessionJournalAttachmentRef
  ): Promise<GroupSessionJournalItemMetadata | null>;

  groupSessionLocalParticipant(sessionRef: GroupSessionRef): Participant;
  groupSessionActiveParticipants(sessionRef: GroupSessionRef): Participant[];
  readonly onActiveParticipantsChange: EventEmitter<{
    source: GroupSessionRef;
    participants: Participant[];
  }>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('AppleShareplay');
