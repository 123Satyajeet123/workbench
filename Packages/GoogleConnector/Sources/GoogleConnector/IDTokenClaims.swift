import Foundation

enum IDTokenClaims {
    private struct Payload: Decodable {
        let email: String?
    }

    static func email(fromIDToken token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let payload = Data(base64URLEncoded: String(parts[1])) else {
            throw GoogleError.decoding("the id_token is not a JWT")
        }
        do {
            guard let email = try JSONDecoder().decode(Payload.self, from: payload).email, !email.isEmpty else {
                throw GoogleError.missingEmail
            }
            return email.lowercased()
        } catch let error as GoogleError {
            throw error
        } catch {
            throw GoogleError.decoding("the id_token claims: \(error.localizedDescription)")
        }
    }
}

extension Data {
    fileprivate init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
