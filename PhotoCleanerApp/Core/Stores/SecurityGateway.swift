import Foundation

struct EmailBreachPayload: Codable, Identifiable, Sendable {
    let id: String
    let date: String
    let fields: String
}

enum SecurityGatewayError: LocalizedError {
    case unavailable
    case invalidResponse
    var errorDescription: String? { "Security service unavailable" }
}

struct SecurityGateway: Sendable {
    var checkEmail: @Sendable (String) async throws -> [EmailBreachPayload]
    var createStripeCheckout: @Sendable (URL) async throws -> URL
    var verifyStripeEntitlement: @Sendable (URL) async throws -> Bool

    static func live(configuration: BackendConfiguration) -> SecurityGateway {
        SecurityGateway(
            checkEmail: { email in
                do {
                    let response = try await Courier.shared.checkEmail(email)
                    return response.breaches.map { breach in
                        EmailBreachPayload(
                            id: breach.displayTitle,
                            date: breach.displayDate,
                            fields: breach.displayFields
                        )
                    }
                } catch {
                    guard let baseURL = configuration.baseURL,
                          let url = URL(string: configuration.emailLeakagePath, relativeTo: baseURL)?.absoluteURL else {
                        throw SecurityGatewayError.unavailable
                    }
                    var request = URLRequest(url: url, timeoutInterval: 10)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !configuration.emailLeakageToken.isEmpty { request.setValue("Bearer \(configuration.emailLeakageToken)", forHTTPHeaderField: "Authorization") }
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SecurityGatewayError.invalidResponse }
                    if let envelope = try? JSONDecoder().decode(BreachEnvelope.self, from: data) { return envelope.breaches }
                    return try JSONDecoder().decode([EmailBreachPayload].self, from: data)
                }
            },
            createStripeCheckout: { returnURL in
                guard let baseURL = configuration.baseURL,
                      let url = URL(string: configuration.stripeCheckoutPath, relativeTo: baseURL)?.absoluteURL else {
                    throw SecurityGatewayError.unavailable
                }
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !configuration.stripeToken.isEmpty { request.setValue("Bearer \(configuration.stripeToken)", forHTTPHeaderField: "Authorization") }
                request.httpBody = try JSONEncoder().encode(StripeCheckoutRequest(returnURL: returnURL.absoluteString, source: "marketing"))
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let payload = try? JSONDecoder().decode(StripeCheckoutResponse.self, from: data),
                      let checkoutURL = URL(string: payload.checkoutURL) else { throw SecurityGatewayError.invalidResponse }
                return checkoutURL
            },
            verifyStripeEntitlement: { callbackURL in
                guard let baseURL = configuration.baseURL,
                      let url = URL(string: configuration.stripeEntitlementPath, relativeTo: baseURL)?.absoluteURL,
                      !configuration.stripeToken.isEmpty else { throw SecurityGatewayError.unavailable }
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(configuration.stripeToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(["callback_url": callbackURL.absoluteString])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SecurityGatewayError.invalidResponse }
                return (try? JSONDecoder().decode(EntitlementResponse.self, from: data).active) ?? false
            }
        )
    }

    static let unavailable = SecurityGateway(
        checkEmail: { _ in throw SecurityGatewayError.unavailable },
        createStripeCheckout: { _ in throw SecurityGatewayError.unavailable },
        verifyStripeEntitlement: { _ in throw SecurityGatewayError.unavailable }
    )
}

private struct BreachEnvelope: Codable { let breaches: [EmailBreachPayload] }
private struct StripeCheckoutRequest: Codable { let returnURL: String; let source: String }
private struct StripeCheckoutResponse: Codable { let checkoutURL: String }
private struct EntitlementResponse: Codable { let active: Bool }
