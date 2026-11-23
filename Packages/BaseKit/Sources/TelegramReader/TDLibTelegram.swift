import Foundation
@preconcurrency import TDLibKit
import WorkbenchCore

public final class TDLibTelegram: TelegramService, @unchecked Sendable {
    private static let manager = TDLibClientManager()

    private let folder: URL
    private let lock = NSLock()
    private var client: TDLibClient?
    private var keys: TelegramKeys?
    private var onChange: (@Sendable (TelegramLogin) -> Void)?
    private var isSignedIn = false
    private var isWaitingForKeys = false
    private var restartsWhenClosed = false
    private var names: [Int64: String] = [:]
    private var me: Int64?
    private var myName: String?

    public init(folder: URL) { self.folder = folder }

    public func connect(
        _ keys: TelegramKeys, policy: CapturePolicy, onChange: @escaping @Sendable (TelegramLogin) -> Void
    ) throws {
        try TelegramGate.check(policy)
        let next: Next = locked {
            self.keys = keys
            self.onChange = onChange
            guard let client else { return .start }
            if isSignedIn, let myName { return .ready(myName) }
            if isWaitingForKeys { return .sendKeys(client) }
            restartsWhenClosed = true
            return .restart(client)
        }
        switch next {
        case .start: start()
        case .ready(let name): report(.ready(name: name))
        case .sendKeys(let client): sendKeys(client)
        case .restart(let client):
            report(.connecting)
            try? client.close { _ in }
        }
    }

    private enum Next {
        case start
        case ready(String)
        case sendKeys(TDLibClient)
        case restart(TDLibClient)
    }

    public func checkPassword(_ password: String) async throws {
        try await call(signedIn: false) { try await $0.checkAuthenticationPassword(password: password) }
    }

    public func groups() async throws -> [TelegramChat] {
        let client = try signedIn()
        _ = try? await client.loadChats(chatList: .chatListMain, limit: 200)
        let ids = try await call { try await $0.getChats(chatList: .chatListMain, limit: 200).chatIds }
        var chats: [TelegramChat] = []
        for id in ids {
            let chat = try await call { try await $0.getChat(chatId: id) }
            switch chat.type {
            case .chatTypeBasicGroup(let group):
                let info = try await call { try await $0.getBasicGroup(basicGroupId: group.basicGroupId) }
                if info.isActive {
                    chats.append(TelegramChat(id: id, title: chat.title, memberCount: info.memberCount))
                }
            case .chatTypeSupergroup(let group) where !group.isChannel:
                let info = try await call { try await $0.getSupergroup(supergroupId: group.supergroupId) }
                chats.append(TelegramChat(id: id, title: chat.title, memberCount: info.memberCount))
            default: continue
            }
        }
        return chats
    }

    public func members(of chatID: Int64) async throws -> [TelegramMember] {
        let chat = try await call { try await $0.getChat(chatId: chatID) }
        var members: [ChatMember] = []
        switch chat.type {
        case .chatTypeBasicGroup(let group):
            members = try await call { try await $0.getBasicGroupFullInfo(basicGroupId: group.basicGroupId).members }
        case .chatTypeSupergroup(let group):
            while members.count < 1000 {
                let offset = members.count
                let page = try await call {
                    try await $0.getSupergroupMembers(
                        filter: .supergroupMembersFilterRecent, limit: 200, offset: offset,
                        supergroupId: group.supergroupId)
                }
                members += page.members
                if page.members.isEmpty || members.count >= page.totalCount { break }
            }
        default: return []
        }
        let me = locked { self.me }
        var people: [TelegramMember] = []
        for member in members where member.status.isPresent {
            guard case .messageSenderUser(let sender) = member.memberId, sender.userId != me else { continue }
            let user = try await call { try await $0.getUser(userId: sender.userId) }
            guard case .userTypeRegular = user.type else { continue }
            people.append(TelegramMember(id: user.id, name: remember(user)))
        }
        return people.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func messages(in chat: Int64, from start: Foundation.Date, to end: Foundation.Date) async throws
        -> [TelegramMessage]
    {
        var found: [TelegramMessage] = []
        var from: Int64 = 0
        for _ in 0..<200 {
            let page = try await call {
                try await $0.getChatHistory(chatId: chat, fromMessageId: from, limit: 100, offset: 0, onlyLocal: false)
                    .messages ?? []
            }
            guard let oldest = page.last, oldest.id != from else { break }
            for message in page {
                let date = Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))
                guard date >= start, date < end, let content = Self.plain(message.content) else { continue }
                found.append(
                    TelegramMessage(
                        id: message.id, chat: chat, date: date, kind: content.kind,
                        sender: try await name(of: message.senderId), isOutgoing: message.isOutgoing,
                        text: content.text, title: content.title))
            }
            if TimeInterval(oldest.date) < start.timeIntervalSince1970 { break }
            from = oldest.id
        }
        return found
    }

    public func signOut() async throws {
        _ = try await call { try await $0.logOut() }
    }

    static func plain(_ content: MessageContent) -> (kind: TelegramMessage.Kind, text: String, title: String?)? {
        switch content {
        case .messageText(let message): (.text, message.text.text, nil)
        case .messagePhoto(let message): (.photo, message.caption.text, nil)
        case .messageVideo(let message): (.video, message.caption.text, nil)
        case .messageDocument(let message): (.document, message.caption.text, message.document.fileName)
        case .messageVoiceNote(let message): (.voiceNote, message.caption.text, nil)
        default: nil
        }
    }

    static func text(of error: Swift.Error) -> String {
        guard let error = error as? TDLibKit.Error else { return error.localizedDescription }
        switch error.message {
        case "API_ID_INVALID", "API_ID_PUBLISHED_FLOOD":
            return "Telegram did not accept this API ID and hash. Copy them again from my.telegram.org."
        case "PASSWORD_HASH_INVALID": return "That is not your Telegram password."
        case "Unauthorized": return "Telegram is not signed in."
        default: return "Telegram said: \(error.message)."
        }
    }

    private func start() {
        report(.connecting)
        let client = Self.manager.createClient { [weak self] data, client in self?.handle(data, client) }
        _ = try? client.execute(query: DTO(SetLogVerbosityLevel(newVerbosityLevel: 1)))
        locked { self.client = client }
    }

    private func handle(_ data: Data, _ client: TDLibClient) {
        guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
        switch update {
        case .updateAuthorizationState(let change): authorization(change.authorizationState, client)
        case .updateUser(let change): _ = remember(change.user)
        default: break
        }
    }

    private func authorization(_ state: AuthorizationState, _ client: TDLibClient) {
        locked { isWaitingForKeys = false }
        switch state {
        case .authorizationStateWaitTdlibParameters:
            locked { isWaitingForKeys = true }
            sendKeys(client)
        case .authorizationStateWaitPhoneNumber:
            report(.connecting)
            try? client.requestQrCodeAuthentication(otherUserIds: nil) { [weak self] result in
                if case .failure(let error) = result { self?.report(.failed(Self.text(of: error))) }
            }
        case .authorizationStateWaitOtherDeviceConfirmation(let wait): report(.scan(link: wait.link))
        case .authorizationStateWaitPassword(let wait): report(.password(hint: wait.passwordHint))
        case .authorizationStateReady:
            try? client.getMe { [weak self] result in
                switch result {
                case .success(let user):
                    guard let self else { return }
                    let name = remember(user)
                    locked {
                        self.me = user.id
                        self.myName = name
                        self.isSignedIn = true
                    }
                    report(.ready(name: name))
                case .failure(let error): self?.report(.failed(Self.text(of: error)))
                }
            }
        case .authorizationStateLoggingOut, .authorizationStateClosing:
            locked { isSignedIn = false }
        case .authorizationStateClosed:
            let restarts = locked {
                self.client = nil
                self.isSignedIn = false
                self.me = nil
                self.myName = nil
                defer { restartsWhenClosed = false }
                return restartsWhenClosed
            }
            if restarts { start() } else { report(.signedOut) }
        default:
            report(.failed("Telegram asked for a sign-in step Workbench does not do. Sign in with the QR code again."))
        }
    }

    private func sendKeys(_ client: TDLibClient) {
        guard let keys = locked({ self.keys }) else { return }
        try? client.setTdlibParameters(
            apiHash: keys.apiHash, apiId: keys.apiID, applicationVersion: "1.0",
            databaseDirectory: folder.appending(path: "data").path, databaseEncryptionKey: keys.databaseKey,
            deviceModel: "Mac", filesDirectory: folder.appending(path: "files").path, systemLanguageCode: "en",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString, useChatInfoDatabase: true,
            useFileDatabase: false, useMessageDatabase: true, useSecretChats: false, useTestDc: false
        ) { [weak self] result in
            if case .failure(let error) = result { self?.report(.failed(Self.text(of: error))) }
        }
    }

    private func name(of sender: MessageSender) async throws -> String {
        switch sender {
        case .messageSenderUser(let user):
            if let known = locked({ names[user.userId] }) { return known }
            return remember(try await call { try await $0.getUser(userId: user.userId) })
        case .messageSenderChat(let chat):
            return try await call { try await $0.getChat(chatId: chat.chatId).title }
        }
    }

    private func remember(_ user: User) -> String {
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let shown = name.isEmpty ? "Telegram user" : name
        locked { names[user.id] = shown }
        return shown
    }

    private func signedIn() throws -> TDLibClient {
        guard let client = locked({ isSignedIn ? client : nil }) else {
            throw TelegramFailure("Telegram is not signed in.")
        }
        return client
    }

    private func call<T>(signedIn: Bool = true, _ work: (TDLibClient) async throws -> T) async throws -> T {
        guard let client = signedIn ? try self.signedIn() : locked({ self.client }) else {
            throw TelegramFailure("Telegram is not connected.")
        }
        do {
            return try await work(client)
        } catch {
            throw TelegramFailure(Self.text(of: error))
        }
    }

    private func report(_ login: TelegramLogin?) {
        guard let login, let onChange = locked({ self.onChange }) else { return }
        onChange(login)
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }
}

extension ChatMemberStatus {
    fileprivate var isPresent: Bool {
        switch self {
        case .chatMemberStatusLeft, .chatMemberStatusBanned: false
        case .chatMemberStatusRestricted(let restricted): restricted.isMember
        default: true
        }
    }
}
