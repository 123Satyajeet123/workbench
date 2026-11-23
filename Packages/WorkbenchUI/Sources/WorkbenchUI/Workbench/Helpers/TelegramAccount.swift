import CaptureService
import Foundation
import Observation
import TelegramReader
import WorkbenchCore

@Observable
final class TelegramAccount {
    static let keysPage = "https://my.telegram.org/apps"

    private(set) var login = TelegramLogin.signedOut
    private(set) var hasKeys = false

    @ObservationIgnored let service: any TelegramService
    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let capture: CaptureService

    init(service: any TelegramService, capture: CaptureService, secrets: SecretStore = KeychainSecrets()) {
        self.service = service
        self.capture = capture
        self.secrets = secrets
        hasKeys = keys != nil
        followCapture()
    }

    var isReady: Bool { if case .ready = login { true } else { false } }

    func connect(apiID: String, apiHash: String) throws {
        let hash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(apiID.trimmingCharacters(in: .whitespacesAndNewlines)), id > 0,
            hash.count == 32, hash.allSatisfy(\.isHexDigit)
        else {
            throw TelegramFailure(
                "The API ID is a number and the API hash is 32 letters and digits. Copy both from my.telegram.org.")
        }
        try secrets.save(String(id), as: Name.apiID)
        try secrets.save(hash, as: Name.apiHash)
        if secrets.read(Name.databaseKey) == nil {
            try secrets.save(
                Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString(), as: Name.databaseKey)
        }
        hasKeys = true
        try start()
    }

    func resume() throws {
        switch login {
        case .signedOut, .failed, .paused: if hasKeys { try start() }
        case .connecting, .scan, .password, .ready: break
        }
    }

    func checkPassword(_ password: String) async throws {
        try await service.checkPassword(password)
    }

    func signOut() async throws {
        try await service.signOut()
    }

    func forgetKeys() throws {
        for name in [Name.apiID, Name.apiHash] { try secrets.remove(name) }
        hasKeys = false
        login = .signedOut
    }

    func waitUntilReady(polls: Int = 300) async throws {
        try resume()
        for _ in 0..<polls {
            switch login {
            case .ready: return
            case .failed(let why): throw TelegramFailure(why)
            case .scan, .password: throw TelegramFailure("Sign in to Telegram first, on the machine's page.")
            case .paused:
                throw TelegramFailure(
                    "Telegram is paused because capture or its switch is off. Connect again on the machine's page.")
            case .signedOut where !hasKeys:
                throw TelegramFailure("Telegram needs its app key; add it on the machine's page.")
            case .signedOut, .connecting: try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw TelegramFailure("Telegram did not answer. Check the connection and try again.")
    }

    private var keys: TelegramKeys? {
        guard let id = secrets.read(Name.apiID).flatMap(Int.init), let hash = secrets.read(Name.apiHash) else {
            return nil
        }
        let databaseKey = secrets.read(Name.databaseKey).flatMap { Data(base64Encoded: $0) } ?? Data()
        return TelegramKeys(apiID: id, apiHash: hash, databaseKey: databaseKey)
    }

    private func followCapture() {
        withObservationTracking {
            _ = capture.policy
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.pauseIfSwitchedOff()
                self?.followCapture()
            }
        }
    }

    private func pauseIfSwitchedOff() {
        guard (try? TelegramGate.check(capture.policy)) == nil else { return }
        switch login {
        case .connecting, .scan, .password, .ready, .failed: service.disconnect()
        case .signedOut, .paused: break
        }
    }

    private func start() throws {
        guard let keys else { return }
        if !capture.policy.isEnabled(.telegram) { try capture.update { $0.switches[.telegram] = true } }
        login = .connecting
        try service.connect(keys, policy: capture.policy) { [weak self] login in
            Task { @MainActor in self?.login = login }
        }
    }

    private enum Name {
        static let apiID = "telegram.apiID"
        static let apiHash = "telegram.apiHash"
        static let databaseKey = "telegram.databaseKey"
    }
}
