import Testing

@testable import Kernel

/// Research 47 I1, review 1 F6: a known device cannot sign in another known device's stream.
@Suite struct ImpersonationTests {
    @Test func anEventInOneDevicesStreamSignedByAnotherKnownDeviceIsRefused() throws {
        let header = try EventFixture.header(
            EventFixture.founderMac, EventFixture.groupLabel, sequence: 1, millis: 1, backlink: .zero)
        let byAditya = Event(header: header, signature: try EventFixture.adityaMac.sign(header.signedBytes))
        var ledger = Ledger(keys: EventFixture.keys)
        #expect(throws: EventError.badSignature) { try ledger.insert(byAditya) }
        let byFounder = Event(header: header, signature: try EventFixture.founderMac.sign(header.signedBytes))
        #expect(throws: Never.self) { try ledger.insert(byFounder) }
    }
}
