import Foundation
import GroupActivities
import Combine
import CoreTransferable


@objc public class AppleSharePlayImpl: NSObject {
  private actor JournalAttachmentStorage {
    private var attachments: [String: GroupSessionJournal.Attachment] = [:]
    private var itemOverrides: [String: String] = [:]
    private var metadataOverrides: [String: String?] = [:]
    
    func setAttachment(_ attachment: GroupSessionJournal.Attachment, for id: String) {
      attachments[id] = attachment
    }
    
    func setItemOverride(_ item: String, for id: String) {
      itemOverrides[id] = item
    }
    
    func setMetadataOverride(_ metadata: String?, for id: String) {
      metadataOverrides[id] = metadata
    }
    
    func getAttachment(for id: String) -> GroupSessionJournal.Attachment? {
      attachments[id]
    }
    
    func getItemOverride(for id: String) -> String? {
      itemOverrides[id]
    }
    
    func getMetadataOverride(for id: String) -> String?? {
      metadataOverrides[id]
    }
    
    func removeAll(for id: String) {
      attachments.removeValue(forKey: id)
      itemOverrides.removeValue(forKey: id)
      metadataOverrides.removeValue(forKey: id)
    }
    
    func setAll(attachment: GroupSessionJournal.Attachment, item: String, metadata: String?, for id: String) {
      attachments[id] = attachment
      itemOverrides[id] = item
      metadataOverrides[id] = .some(metadata)
    }
    
    func getBoth(for id: String) -> (item: String?, attachment: GroupSessionJournal.Attachment?) {
      (itemOverrides[id], attachments[id])
    }
    
    func getBothMeta(for id: String) -> (metadata: String??, attachment: GroupSessionJournal.Attachment?) {
      (metadataOverrides[id], attachments[id])
    }
    
    func loadAttachmentItem(for id: T.GroupSessionJournalAttachmentRef) async throws -> String {
      if let override = itemOverrides[id] {
        return override
      }
      guard let attachment = attachments[id] else {
        throw Error.invalidAttachmentRef(id)
      }
      let item = try await attachment.load(String.self)
      setItemOverride(item, for: id)
      return item
    }
    
    func loadAttachmentMetadata(for id: T.GroupSessionJournalAttachmentRef) async throws -> String? {
      if let override = metadataOverrides[id] {
        return override
      }
      guard let attachment = attachments[id] else {
        throw Error.invalidAttachmentRef(id)
      }
      let item = try await attachment.loadMetadata(of: String.self)
      setMetadataOverride(item, for: id)
      return item
    }
  }
  /// Types used to transfer data to/from Obj-C
  @objc public class T: NSObject {
    public typealias GroupActivityRef = Int
    public typealias GroupMessengerRef = Int
    public typealias GroupSessionRef = Int
    public typealias GroupSessionJournalRef = Int
    public typealias GroupSessionJournalAttachmentRef = String
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
    @objc public class GroupMessengerParticipantsAll: GroupMessengerParticipants {}
    @objc public class GroupMessengerParticipantsOnly: GroupMessengerParticipants {
      @objc public init(participantIds: Set<UUID>) {
        self.participantIds = participantIds
      }
      
      var participantIds: Set<UUID>
    }
   }

  private var indexGenerator = stride(from: 0, through: Int.max, by: 1).makeIterator()
  private let groupStateObserver = GroupStateObserver()

  // MARK: Stores
  private var groupActivities: [T.GroupActivityRef: T.DynamicGroupActivity] = [:]
  private var groupMessengers: [T.GroupMessengerRef: GroupSessionMessenger] = [:]
  private var groupSessions: [T.GroupSessionRef: GroupSession<T.DynamicGroupActivity>] = [:]
  private var groupMessengerRefToSessionm: [T.GroupMessengerRef: T.GroupSessionRef] = [:]
  private var groupSessionJournals: [T.GroupSessionJournalRef: GroupSessionJournal] = [:]
  private let journalStorage = JournalAttachmentStorage()

  private var tasks: Set<Task<Void, any Swift.Error>> = []
  private var subscriptions: Set<AnyCancellable> = []

  var groupSharingEligibilityPublisher: AnyPublisher<Bool, Never> {
    groupStateObserver.$isEligibleForGroupSession.eraseToAnyPublisher()
  }

  let messageReceivedPublisher = PassthroughSubject<(source: T.GroupMessengerRef, message: T.GroupMessengerMessage, senderId: String), Never>()

  /** When a session's state changes, publishes the ref for the affected session */
  let sessionStatePublisher = PassthroughSubject<T.GroupSessionRef, Never>()

  /** When a session's active participants changes, publishes the ref for the affected session */
  let sessionActiveParticipantsPublisher = PassthroughSubject<T.GroupSessionRef, Never>()

  /** When journal attachments change, publishes the journal ref and attachment IDs */
  let journalAttachmentsPublisher = PassthroughSubject<(source: T.GroupSessionJournalRef, attachments: [String]), Never>()

  private func getSession(_ ref: T.GroupSessionRef) throws -> GroupSession<T.DynamicGroupActivity> {
    guard let session = groupSessions[ref] else { throw Error.invalidSessionRef(ref) }
    return session
  }

  private func getJournal(_ ref: T.GroupSessionJournalRef) throws -> GroupSessionJournal {
    guard let session = groupSessionJournals[ref] else { throw Error.invalidJournalRef(ref) }
    return session
  }

  private func getMessenger(_ ref: T.GroupMessengerRef) throws -> GroupSessionMessenger {
    guard let m = groupMessengers[ref] else { throw Error.invalidMessengerRef(ref) }
    return m
  }

  @objc public func observeGroupSharingEligbility(_ listener: @escaping (Bool) -> Void) -> () -> Void {
    let cancellable = groupSharingEligibilityPublisher
      .sink(receiveValue: listener)
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
  
  @objc public func listActiveGroupSessions() -> [T.GroupSessionRef] {
    Array(
      self.groupSessions
        .filter {
          if case .invalidated = $0.value.state {
            return false
          }
          return true
        }
        .map { $0.key }
    )
  }

  private func register(_ session: GroupSession<T.DynamicGroupActivity>) -> T.GroupSessionRef {
    let sessionRef = groupSessions.insert(session, takingIndexFrom: &indexGenerator)
    subscriptions.insert(
      session.$state
        .sink { [weak self] _ in
          self?.sessionStatePublisher.send(sessionRef)
        }
    )
    
    subscriptions.insert(
      session.$activeParticipants
        .sink { [weak self] _ in
          self?.sessionActiveParticipantsPublisher.send(sessionRef)
        }
    )
    return sessionRef
  }

  @objc public func join(_ sessionRef: T.GroupSessionRef) {
    let session = try! getSession(sessionRef)
    session.join()
  }

  @objc public func leave(_ sessionRef: T.GroupSessionRef) {
    let session = groupSessions[sessionRef]!
    session.leave()
  }

  @objc public func observeGroupActivitySession(_ listener: @escaping (T.GroupActivityRef, T.GroupSessionRef) -> Void) -> () -> Void {
    let task = Task<Void, any Swift.Error> {
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
    groupMessengerRefToSessionm[messengerRef] = sessionRef

    tasks.insert(
      Task {
        let messages = messenger.messages(of: T.GroupMessengerMessage.self)
        for await (message, info) in messages {
          messageReceivedPublisher.send((source: messengerRef, message: message, senderId: info.source.id.uuidString))
        }
      }
    )

    return messengerRef
  }

  @objc public func send(
    _ message: T.GroupMessengerMessage,
    using messengerRef: T.GroupMessengerRef,
    to target: T.GroupMessengerParticipants
  ) async throws {
    let messenger = try getMessenger(messengerRef)
    let session = try getSession(groupMessengerRefToSessionm[messengerRef]!)
    try await messenger.send(message, to: Participants(target, session: session))
  }

  @objc public func observeGroupMessengerMessageReceived(
    _ listener: @escaping (T.GroupMessengerRef, T.GroupMessengerMessage, /* Sender ID */ String) -> Void
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

  @objc public func observeGroupSessionStatus(
    _ listener: @escaping (T.GroupSessionRef) -> Void
  ) -> () -> Void {
    let cancellable = self.sessionStatePublisher.sink(receiveValue: listener)
    return { cancellable.cancel() }
  }

  @objc public func localParticipant(in sessionRef: T.GroupSessionRef) throws -> String {
    return (try getSession(sessionRef)).localParticipant.id.uuidString
  }

  @objc public func activeParticipants(in sessionRef: T.GroupSessionRef) throws -> [String] {
    return (try getSession(sessionRef)).activeParticipants.map { $0.id.uuidString }
  }

  @objc public func observeActiveParticipants(
    _ listener: @escaping (T.GroupSessionRef, /* Participant.id */ [String]) -> Void
  ) -> () -> Void {
    let cancellable = self.sessionActiveParticipantsPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] sessionRef in
        guard let self else { return }
        let session = try! self.getSession(sessionRef)
        listener(sessionRef, session.activeParticipants.map { $0.id.uuidString })
      }
    return { cancellable.cancel() }
  }

  // MARK: GroupSessionJournal APIs

  @objc public func createJournal(for sessionRef: T.GroupSessionRef) -> T.GroupSessionJournalRef {
    let session = groupSessions[sessionRef]!
    let journal = GroupSessionJournal(session: session)
    let journalRef = groupSessionJournals.insert(journal, takingIndexFrom: &indexGenerator)

    // Automatically subscribe to attachments stream
    let task = Task<Void, any Swift.Error> {
      for await attachments in journal.attachments {
        var attachmentIds: [String] = []
        for attachment in attachments {
          let attachmentId = attachment.id.uuidString
          await self.journalStorage.setAttachment(attachment, for: attachmentId)
          attachmentIds.append(attachmentId)
        }
        self.journalAttachmentsPublisher.send((source: journalRef, attachments: attachmentIds))
      }
    }
    tasks.insert(task)

    return journalRef
  }

  @objc public func addToJournal(
    _ journalRef: T.GroupSessionJournalRef,
    item: String,
    metadata: String?
  ) async throws -> String? {
    let journal = try getJournal(journalRef)
    let journalItem = item
    let journalMetadata = metadata

    let attachment = try await journal.add(journalItem, metadata: journalMetadata)
    let attachmentId = attachment.id.uuidString
    await journalStorage.setAll(attachment: attachment, item: journalItem, metadata: journalMetadata, for: attachmentId)

    return attachmentId
  }

  enum Error: Swift.Error {
    case invalidSessionRef(T.GroupSessionRef)
    case invalidJournalRef(T.GroupSessionJournalRef)
    case invalidAttachmentRef(T.GroupSessionJournalAttachmentRef)
    case invalidMessengerRef(T.GroupMessengerRef)
  }

  @objc public func removeFromJournal(
    _ journalRef: T.GroupSessionJournalRef,
    attachmentId: String
  ) async throws -> Void {
    let journal = try getJournal(journalRef)
    guard let attachment = await journalStorage.getAttachment(for: attachmentId) else {
      throw Error.invalidAttachmentRef(attachmentId)
    }

    try await journal.remove(attachment: attachment)
    await journalStorage.removeAll(for: attachmentId)
  }

  @objc public func loadJournalAttachment(_ attachmentId: String) async throws -> String {
    return try await journalStorage.loadAttachmentItem(for: attachmentId)
  }

  @objc public func loadJournalAttachmentMetadata(_ attachmentId: String) async throws -> String? {
    return try await journalStorage.loadAttachmentMetadata(for: attachmentId)
  }

  @objc public func observeJournalAttachments(
    _ listener: @escaping (T.GroupSessionJournalRef, [String]) -> Void
  ) -> () -> Void {
    let cancellable = journalAttachmentsPublisher
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: listener)
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
  init<ActivityType>(_ x: AppleSharePlayImpl.T.GroupMessengerParticipants, session: GroupSession<ActivityType>) {
    if x is AppleSharePlayImpl.T.GroupMessengerParticipantsAll {
      self = .all
    } else if let y = x as? AppleSharePlayImpl.T.GroupMessengerParticipantsOnly  {
      let participants = session.activeParticipants.filter { y.participantIds.contains($0.id) }
      self = .only(participants)
    } else {
      fatalError("Unrecognized Participants shape")
    }
  }
}
