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
import { Button, EventSubscription, SafeAreaView, Text } from 'react-native';

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
      })
    );
    return () => subscriptions.forEach((x) => x.remove());
  }, []);

  return (
    <SafeAreaView>
      <Text>
        Eligibility status:{' '}
        {eligible === null ? 'No response' : eligible ? 'Eligible' : 'Not'}
      </Text>
      <Text>
        Session reference: {sessionRef == null ? 'None' : sessionRef.toString()}
      </Text>
      <Text>
        Messenger reference:{' '}
        {messengerRef == null ? 'None' : messengerRef.toString()}
      </Text>
      {Object.entries(sessionState).map(([ref, status]) => (
        <Text key={ref}>
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
        title="Create messenger"
        disabled={sessionRef == null}
        onPress={() => {
          setMessengerRef(AppleSharePlay.groupMessengerCreate(sessionRef!));
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
    </SafeAreaView>
  );
}

export default App;
