import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { EventEmitter } from 'react-native/Libraries/Types/CodegenTypes';

type GroupMessengerRef = number;
type GroupSessionRef = number;
type GroupActivityRef = number;

type GroupMessengerParticipants = { type: 'all' };

type GroupMessengerMessage = {
  data: string;
};

interface GroupMessengerMessageOutgoing extends GroupMessengerMessage {
  type: 'outgoing';
}
interface GroupMessengerMessageIncoming extends GroupMessengerMessage {
  type: 'incoming';
}

export enum GroupSessionStatus {
  invalidated = 'invalidated',
  joined = 'joined',
  waiting = 'waiting',
}

interface GroupActivity {
  metadata: { title: string };
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
    message: GroupMessengerMessageOutgoing,
    target: GroupMessengerParticipants
  ): Promise<void>;
  readonly onGroupMessengerMessageReceived: EventEmitter<{
    source: GroupMessengerRef;
    message: GroupMessengerMessageIncoming;
  }>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('AppleShareplay');
