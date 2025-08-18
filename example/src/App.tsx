/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import AppleSharePlay, {
  GroupSessionStatus,
} from 'react-native-apple-shareplay';
import React, { useEffect, useState } from 'react';
import { Button, SafeAreaView, Text } from 'react-native';
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
            await AppleSharePlay.groupSessionJournalAttachmentLoad(attachment)
          );
          console.log(
            await AppleSharePlay.groupSessionJournalAttachmentLoadMetadata(
              attachment
            )
          );
        }
      })
    );
    return () => subscriptions.forEach((x) => x.remove());
  }, []);

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
  }, [sessionRef]);

  return (
    <SafeAreaView>
      <Text style={{ color: 'white' }}>
        Eligibility status:{' '}
        {eligible === null ? 'No response' : eligible ? 'Eligible' : 'Not'}
      </Text>
      <Text style={{ color: 'white' }}>
        Session reference: {sessionRef == null ? 'None' : sessionRef.toString()}
      </Text>
      <Text style={{ color: 'white' }}>
        Messenger reference:{' '}
        {messengerRef == null ? 'None' : messengerRef.toString()}
      </Text>
      {Object.entries(sessionState).map(([ref, status]) => (
        <Text key={ref} style={{ color: 'white' }}>
          Session {ref} status: {status}
        </Text>
      ))}

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
              { type: 'outgoing', data: 'Hello from the group activity!' },
              { type: 'all' }
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
              `journal item ${nextCounter()}`,
              `journal metadata ${nextCounter()}`
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
