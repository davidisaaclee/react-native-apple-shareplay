/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import AppleSharePlay, {
  GroupMessengerParticipantsAll,
  GroupSessionStatus,
  type Participant,
} from 'react-native-apple-shareplay';
import React, { useEffect, useState } from 'react';
import { Appearance, Button, SafeAreaView, Text } from 'react-native';
import type { EventSubscription } from 'react-native';

const nextCounter = (() => {
  let counter = 0;
  return () => counter++;
})();

function App(): React.JSX.Element {
  const [eligible, setEligible] = useState<boolean | null>(() =>
    AppleSharePlay.getGroupSharingEligbility()
  );
  const [sessionRef, setSessionRef] = useState<number | null>(null);
  const [sessionState, setSessionState] = useState<
    Record<number, GroupSessionStatus>
  >({});
  const [messengerRef, setMessengerRef] = useState<number | null>(null);
  const [localParticipant, setLocalParticipant] = useState<Participant | null>(
    null
  );
  const [activeParticipants, setActiveParticipants] = useState<Participant[]>(
    []
  );

  useEffect(() => {
    const subscriptions: EventSubscription[] = [];
    subscriptions.push(
      AppleSharePlay.onGroupSharingEligbilityChange((opts) => {
        console.log('Eligibility changed:', opts);
        setEligible(opts.eligible);
      }),

      AppleSharePlay.onGroupActivitySession(async (opts) => {
        console.log('Group activity session started:', opts);
        setSessionRef(opts.session);
        setSessionState((prev) => ({
          ...prev,
          [opts.session]: AppleSharePlay.groupSessionStatus(opts.session),
        }));
      }),

      AppleSharePlay.onGroupMessengerMessageReceived((opts) => {
        console.log('Message received', opts);
      }),

      AppleSharePlay.onGroupSessionStatusChanged((opts) => {
        console.log('Group session status changed:', opts);
        console.log(
          'Group session status changed to:',
          AppleSharePlay.groupSessionStatus(opts.source)
        );
        setSessionState((prev) => ({
          ...prev,
          [opts.source]: AppleSharePlay.groupSessionStatus(opts.source),
        }));
      }),

      AppleSharePlay.onGroupSessionJournalAttachments(async (opts) => {
        console.log('Journal attachments received:', opts);
        for (const attachment of opts.attachments) {
          console.log(`Attachment: ${attachment}:`);
          console.log(
            'Attachment item:',
            await AppleSharePlay.groupSessionJournalAttachmentLoad(attachment)
          );
          console.log(
            'Attachment metadata:',
            await AppleSharePlay.groupSessionJournalAttachmentLoadMetadata(
              attachment
            )
          );
        }
      }),

      AppleSharePlay.onActiveParticipantsChange((opts) => {
        console.log('Active participants changed:', opts);
        setActiveParticipants(opts.participants);
        // Also update local participant when participants change
        if (opts.source && sessionRef === opts.source) {
          try {
            const local = AppleSharePlay.groupSessionLocalParticipant(
              opts.source
            );
            setLocalParticipant(local);
          } catch (err) {
            console.error('Failed to get local participant:', err);
          }
        }
      })
    );
    return () => subscriptions.forEach((x) => x.remove());
  }, [sessionRef]);

  const [journalRef, setJournalRef] = useState<number | null>(null);

  useEffect(() => {
    if (sessionRef == null) {
      return;
    }

    // Do setup and join.
    setMessengerRef(AppleSharePlay.groupMessengerCreate(sessionRef));
    // This isn't documented anywhere, but it's apparently important to create
    // the journal *before* joining the session.
    setJournalRef(AppleSharePlay.groupSessionJournalCreate(sessionRef));
    AppleSharePlay.groupSessionJoin(sessionRef);

    // Get initial participant information
    try {
      const local = AppleSharePlay.groupSessionLocalParticipant(sessionRef);
      const active = AppleSharePlay.groupSessionActiveParticipants(sessionRef);
      setLocalParticipant(local);
      setActiveParticipants(active);
    } catch (err) {
      console.error('Failed to get participant information:', err);
    }
  }, [sessionRef]);

  const textColor = Appearance.getColorScheme() === 'dark' ? 'white' : 'black';

  return (
    <SafeAreaView>
      <Text style={{ color: textColor }}>
        Eligibility status:{' '}
        {eligible === null ? 'No response' : eligible ? 'Eligible' : 'Not'}
      </Text>
      <Text style={{ color: textColor }}>
        Session reference: {sessionRef == null ? 'None' : sessionRef.toString()}
      </Text>
      <Text style={{ color: textColor }}>
        Messenger reference:{' '}
        {messengerRef == null ? 'None' : messengerRef.toString()}
      </Text>
      <Text style={{ color: textColor }}>
        Local participant: {localParticipant?.id ?? 'None'}
      </Text>
      <Text style={{ color: textColor }}>
        Active participants: {activeParticipants.length} (
        {activeParticipants.map((p) => p.id).join(', ')})
      </Text>
      {Object.entries(sessionState).map(([ref, status]) => (
        <Text key={ref} style={{ color: textColor }}>
          Session {ref} status: {status}
        </Text>
      ))}

      <Button
        title="Check eligibility"
        onPress={() => {
          console.log('Eligible:', AppleSharePlay.getGroupSharingEligbility());
        }}
      />

      <Button
        title="Activate Group Activity"
        onPress={() => {
          const activityRef = AppleSharePlay.groupActivityRegister({
            metadata: {
              title: 'My example RN group activity',
            },
          });
          AppleSharePlay.groupActivityActivate(activityRef)
            .then((result) => {
              console.log('Group activity activated:', result);
            })
            .catch((err) => {
              console.error('Failed to activate group activity:', err);
            });
        }}
      />

      <Button
        title="Join session"
        disabled={sessionRef == null}
        onPress={() => {
          AppleSharePlay.groupSessionJoin(sessionRef!);
        }}
      />

      <Button
        title="Leave session"
        disabled={sessionRef == null}
        onPress={() => {
          AppleSharePlay.groupSessionLeave(sessionRef!);
        }}
      />

      <Button
        title="Send message"
        disabled={messengerRef == null}
        onPress={async () => {
          try {
            await AppleSharePlay.groupMessengerSend(
              messengerRef!,
              'Hello from the group activity!',
              GroupMessengerParticipantsAll
            );
            console.log('Sent message');
          } catch (err) {
            console.error('Failed to send message:', err);
          }
        }}
      />

      <Button
        title="Send journal attachment"
        disabled={journalRef == null}
        onPress={async () => {
          try {
            console.log('Sending journal attachment...');
            const attachmentRef = await AppleSharePlay.groupSessionJournalAdd(
              journalRef!,
              `journal item ${nextCounter()}`
              // `journal metadata ${nextCounter()}`
            );
            console.log('Journal attachment created:', attachmentRef);
            console.log(
              'Fetching attachment data locally:',
              await AppleSharePlay.groupSessionJournalAttachmentLoad(
                attachmentRef
              ),
              await AppleSharePlay.groupSessionJournalAttachmentLoadMetadata(
                attachmentRef
              )
            );
          } catch (err) {
            console.error('Failed to send journal attachment:', err);
          }
        }}
      />
    </SafeAreaView>
  );
}

export default App;
