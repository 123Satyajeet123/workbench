import Foundation

/// The person's yes to the conditions of reading with their own plan sign-in, and the version of the words they said
/// yes to.
public struct ModelTermsConfirmation: Codable, Sendable, Equatable {
    public var conditionsVersion: Int
    /// How the calls were billed when the person confirmed.
    public var billing: String
    public var confirmedAt: Date

    public init(conditionsVersion: Int, billing: String, confirmedAt: Date) {
        self.conditionsVersion = conditionsVersion
        self.billing = billing
        self.confirmedAt = confirmedAt
    }
}

public enum ModelTerms {
    /// Changes whenever the words of `conditions` change, so an old yes no longer counts.
    public static let currentVersion = 1
    public static let planBilling = "plan"
    public static let trainingOff = """
        Model training is off for the account you signed in with: on claude.ai, Settings › Privacy › "Help improve \
        Claude" is off; on ChatGPT, Settings › Data controls › "Improve the model for everyone" is off.
        """
    public static let ordinaryUse =
        "Your plan's limits cover one person's ordinary use, and Workbench reads for you alone."
    public static let conditions = [trainingOff, ordinaryUse]

    public static let stateKey = "model.terms"
}

public enum ModelTermsError: Error, Equatable, LocalizedError {
    case notConfirmed

    public var errorDescription: String? {
        """
        Reading with your plan sign-in needs your yes first. Open Settings › General › Model and confirm the two \
        conditions, or bill your own Anthropic API key.
        """
    }
}

extension Store {
    /// The confirmation that holds now. Nil when there is none, when it is for older words, or when it cannot be read.
    public func currentModelTermsConfirmation() -> ModelTermsConfirmation? {
        let kept = (try? queries.state(forKey: ModelTerms.stateKey)).flatMap { $0 }
        guard let kept,
            let confirmation = try? Self.termsDecoder.decode(ModelTermsConfirmation.self, from: Data(kept.utf8))
        else { return nil }
        return confirmation.conditionsVersion == ModelTerms.currentVersion ? confirmation : nil
    }

    public func keepModelTermsConfirmation(_ confirmation: ModelTermsConfirmation) throws {
        let text = String(decoding: try Self.termsEncoder.encode(confirmation), as: UTF8.self)
        try saveState(text, forKey: ModelTerms.stateKey)
    }

    public func confirmModelTerms() throws {
        try keepModelTermsConfirmation(
            ModelTermsConfirmation(
                conditionsVersion: ModelTerms.currentVersion, billing: ModelTerms.planBilling, confirmedAt: clock()))
    }

    public func withdrawModelTerms() throws { try saveState("", forKey: ModelTerms.stateKey) }

    func requireModelTerms(for model: any StructuredModel) throws {
        if model.billedToPlanSignIn, currentModelTermsConfirmation() == nil { throw ModelTermsError.notConfirmed }
    }

    private static let termsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let termsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
