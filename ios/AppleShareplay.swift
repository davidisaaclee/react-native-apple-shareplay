import Foundation
import GroupActivities
import Combine

@objc public class AppleSharePlayImpl: NSObject {
  /// Types used to transfer data to/from Obj-C
  @objc public class T: NSObject {
    public typealias GroupActivityRef = Int
    public typealias GroupMessengerRef = Int
    public typealias GroupSessionRef = Int
    public typealias GroupMessengerMessage = Data

    public typealias GroupSessionStatus = String
    public static let GroupSessionStatusInvalidated = "invalidated"
    public static let GroupSessionStatusJoined = "joined"
    public static let GroupSessionStatusWaiting = "waiting"

    @objc public class DynamicGroupActivity: NSObject, GroupActivity {
      @objc public init(title: String) {
        metadata = GroupActivityMetadata()
        metadata.title = title
      }

      public var metadata: GroupActivityMetadata
    }

    @objc public class GroupMessengerParticipants: NSObject {}
  }

  private var indexGenerator = stride(from: 0, through: Int.max, by: 1).makeIterator()
  private let groupStateObserver = GroupStateObserver()

  // MARK: Stores
  private var groupActivities: [T.GroupActivityRef: T.DynamicGroupActivity] = [:]
  private var groupMessengers: [T.GroupMessengerRef: GroupSessionMessenger] = [:]
  private var groupSessions: [T.GroupSessionRef: GroupSession<T.DynamicGroupActivity>] = [:]

  private var tasks: Set<Task<Void, any Error>> = []
  private var subscriptions: Set<AnyCancellable> = []

  var groupSharingEligibilityPublisher: AnyPublisher<Bool, Never> {
    groupStateObserver.$isEligibleForGroupSession.eraseToAnyPublisher()
  }

  let messageReceivedPublisher = PassthroughSubject<(source: T.GroupMessengerRef, message: T.GroupMessengerMessage), Never>()

  /** When a session's state changes, publishes the ref for the affected session */
  let sessionStatePublisher = PassthroughSubject<T.GroupSessionRef, Never>()

  @discardableResult
  @objc public func observeGroupSharingEligbility(_ listener: @escaping (Bool) -> Void) -> () -> Void {
    let cancellable = groupSharingEligibilityPublisher.sink(receiveValue: listener)
    return { cancellable.cancel() }
  }

  @objc public func getGroupSharingEligibility() -> Bool {
    groupStateObserver.isEligibleForGroupSession
  }

  @objc public func register(_ groupActivity: T.DynamicGroupActivity) -> T.GroupActivityRef {
    groupActivities.insert(groupActivity, takingIndexFrom: &indexGenerator)
  }

  @objc public func activate(_ ref: T.GroupActivityRef) async -> Bool {
    await activate(groupActivities[ref]!)
  }

  func activate(_ groupActivity: T.DynamicGroupActivity) async -> Bool {
    try! await groupActivity.activate()
  }

  private func register(_ session: GroupSession<T.DynamicGroupActivity>) -> T.GroupSessionRef {
    let sessionRef = groupSessions.insert(session, takingIndexFrom: &indexGenerator)
    subscriptions.insert(
      session.$state.sink { [weak self] _ in
        self?.sessionStatePublisher.send(sessionRef)
      }
    )
    return sessionRef
  }

  @objc public func join(_ sessionRef: T.GroupSessionRef) {
    let session = groupSessions[sessionRef]!
    session.join()
  }

  @objc public func leave(_ sessionRef: T.GroupSessionRef) {
    let session = groupSessions[sessionRef]!
    session.leave()
  }

  @discardableResult
  @objc public func observeGroupActivitySession(_ listener: @escaping (T.GroupActivityRef, T.GroupSessionRef) -> Void) -> () -> Void {
    let task = Task<Void, any Error> {
      for await session in T.DynamicGroupActivity.sessions() {
        let activityRef = groupActivities.first(where: { $0.value == session.activity })?.key
          ?? self.register(session.activity)
        let sessionRef = register(session)
        listener(activityRef, sessionRef)
      }
    }
    tasks.insert(task)

    return { [weak self] in
      task.cancel()
      self?.tasks.remove(task)
    }
  }

  @objc public func createMessenger(on sessionRef: T.GroupSessionRef) -> T.GroupMessengerRef {
    let session = groupSessions[sessionRef]!
    let messenger = GroupSessionMessenger(session: session)
    let messengerRef = groupMessengers.insert(messenger, takingIndexFrom: &indexGenerator)

    tasks.insert(
      Task {
        let messages = messenger.messages(of: T.GroupMessengerMessage.self)
        for await (message, _) in messages {
          messageReceivedPublisher.send((source: messengerRef, message: message))
        }
      }
    )

    return messengerRef
  }

  @objc public func send(
    _ message: T.GroupMessengerMessage,
    using messengerRef: T.GroupMessengerRef,
    to target: T.GroupMessengerParticipants
  ) async {
    do {
      let messenger = groupMessengers[messengerRef]!
      try await messenger.send(message, to: Participants(target))
    } catch {
      print("Failed send message", error)
    }
  }

  @discardableResult
  @objc public func observeGroupMessengerMessageReceived(
    _ listener: @escaping (T.GroupMessengerRef, T.GroupMessengerMessage) -> Void
  ) -> () -> Void {
    let cancellable = self.messageReceivedPublisher.sink(receiveValue: listener)
    return { cancellable.cancel() }
  }

  @objc public func status(of sessionRef: T.GroupSessionRef) -> T.GroupSessionStatus {
    let session = groupSessions[sessionRef]!
    switch session.state {
    case .invalidated: return T.GroupSessionStatusInvalidated
    case .waiting: return T.GroupSessionStatusWaiting
    case .joined: return T.GroupSessionStatusJoined
    @unknown default:
      fatalError("Unknown session state \(session.state)")
    }
  }

  @discardableResult
  @objc public func observeGroupSessionStatus(
    _ listener: @escaping (T.GroupSessionRef) -> Void
  ) -> () -> Void {
    let cancellable = self.sessionStatePublisher.sink(receiveValue: listener)
    return { cancellable.cancel() }
  }
}

private extension Dictionary {
  mutating func insert<It>(
    _ x: Value,
    takingIndexFrom iterator: inout It
  ) -> Key where It: IteratorProtocol, It.Element == Key {
    let ref = iterator.next()!
    self[ref] = x
    return ref
  }
}

private extension Participants {
  init(_ x: AppleSharePlayImpl.T.GroupMessengerParticipants) {
    self = .all
  }
}
