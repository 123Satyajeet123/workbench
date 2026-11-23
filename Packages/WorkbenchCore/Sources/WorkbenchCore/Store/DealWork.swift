import Foundation
import Kernel
import Lines

/// Why lines of a deal are not read now. Each case is said to the person in plain words.
public enum ReadBlock: Error, Equatable, LocalizedError {
    /// A line has no known consent, so nobody can say it may be read.
    case consentUnknown
    case switchedOff(Consent)

    public var errorDescription: String? {
        switch self {
        case .consentUnknown: "A line of this deal has no known consent, so its text is not read."
        case .switchedOff(let consent):
            "\(consent.kind.words) is switched off or not allowed for \(consent.label), so its text is not read."
        }
    }
}

extension Store {
    static let readerVersion = "by-hand 1"

    /// A grant for each consent the lines hold, before any model reads them. What the person gave by hand needs no
    /// switch; any other kind needs the capture policy to allow it now.
    public func grants(for lines: [Evidence]) throws -> [Consent: CaptureGrant] {
        let policy = try currentPolicy()
        var grants: [Consent: CaptureGrant] = [:]
        for line in lines {
            guard let consent = line.consent else { throw ReadBlock.consentUnknown }
            guard grants[consent] == nil else { continue }
            let request = CaptureRequest(kind: consent.kind, label: consent.label)
            guard
                let grant = CaptureGrant.byHand(consent.kind, label: consent.label, at: clock())
                    ?? policy.authorize(request, at: clock()).grant
            else { throw ReadBlock.switchedOff(consent) }
            grants[consent] = grant
        }
        return grants
    }

    /// Adds a file to a deal: the text of its pages becomes lines of the deal's evidence, written by the person. The
    /// act is the consent. Returns the pages kept; none when the file holds no text.
    @discardableResult
    public func addFile(_ file: Data, named name: String, to deal: String, owner: PersonID) throws -> Int {
        let digest = Kernel.Digest.sha256([UInt8](file)).description.prefix(12)
        let lines = try FileText.pages(in: file).map { page in
            ObservedLine(
                line: Line(
                    entity: try ownEntity(deal: deal, item: "\(name)/\(digest)/\(page.page)"), text: page.text,
                    readerVersion: Self.readerVersion),
                eventTime: UTCInstant(clock()), actor: WhatsAppAudience.owner,
                coordinate: try Coding.json(FilePlace(file: name, page: page.page)))
        }
        return try recordOwn(lines, of: .droppedFile, label: name, deal: deal, owner: owner).inserted
    }

    /// Types a claim on a deal. It is a line of the deal's evidence, in the person's own words, and a claim that cites
    /// that line, so it is checked like a claim read from a deck. Nil when the words are empty.
    @discardableResult
    public func addTypedClaim(_ words: String, to deal: String, owner: PersonID) throws -> Int64? {
        guard let words = words.cleaned else { return nil }
        let line = Line(
            entity: try ownEntity(deal: deal, item: "typed/\(UUID().uuidString)"), text: words,
            readerVersion: Self.readerVersion)
        try recordOwn(
            [ObservedLine(line: line, eventTime: UTCInstant(clock()), actor: WhatsAppAudience.owner)],
            of: .typedNote, label: "claim", deal: deal, owner: owner)
        guard let stored = try queries.line(withID: line.id) else { return nil }
        let standing = Standing(citing: [stored.evidence], facts: [], window: [stored.evidence])
        let claim = Claim(
            deal: deal, text: words, type: "", value: "", quote: words, line: 0, label: standing.label,
            authority: standing.authority, source: .typed)
        guard let consent = stored.consent, let grant = try grants(for: [stored.evidence])[consent] else { return nil }
        return try saveClaims([claim], run: nil, grant: grant).first
    }

    private func ownEntity(deal: String, item: String) throws -> EntityKey {
        try EntityKey.web(site: "workbench", container: deal, itemID: item)
    }

    @discardableResult
    private func recordOwn(
        _ lines: [ObservedLine], of descriptor: SourceDescriptor, label: String, deal: String, owner: PersonID
    ) throws -> IngestReport {
        guard let grant = CaptureGrant.byHand(descriptor.consent, label: label, at: clock()) else {
            return IngestReport()
        }
        return try record(
            SourceReading(
                grant: grant, label: label, container: deal,
                audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [String]()), lines: lines,
                cursorAfter: nil, readerVersion: Self.readerVersion),
            of: descriptor, owner: owner)
    }
}
