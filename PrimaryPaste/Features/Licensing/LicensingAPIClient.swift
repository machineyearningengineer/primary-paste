import Foundation

enum LicensingAPIError: Error {
    case operationInProgress
    case invalidResponse
    case rejected(statusCode: Int)
}

struct LicensingAPIClient {
    let baseURL: URL
    var session: URLSession = .shared

    func createCheckoutSession(installationID: String) async throws -> URL {
        let response: CheckoutSessionResponse = try await post(
            path: "v1/checkout-sessions",
            body: ["installation_id": installationID]
        )
        guard response.checkoutURL.scheme == "https", response.checkoutURL.host == "checkout.stripe.com" else {
            throw LicensingAPIError.invalidResponse
        }
        return response.checkoutURL
    }

    func claimCheckout(sessionID: String, installationID: String) async throws -> String {
        let response: CheckoutClaimResponse = try await post(
            path: "v1/checkout/claim",
            body: ["session_id": sessionID, "installation_id": installationID]
        )
        return response.licenseKey
    }

    func activate(licenseKey: String, deviceHash: String) async throws -> ActivationResponse {
        try await post(path: "v1/licenses/activate", body: ["license_key": licenseKey, "device_hash": deviceHash])
    }

    func refresh(activationToken: String) async throws -> ActivationResponse {
        try await post(path: "v1/licenses/refresh", body: ["activation_token": activationToken])
    }

    func deactivate(activationToken: String) async throws {
        let _: EmptyResponse = try await post(
            path: "v1/licenses/deactivate",
            body: ["activation_token": activationToken]
        )
    }

    private func post<Response: Decodable>(path: String, body: [String: String]) async throws -> Response {
        guard baseURL.scheme == "https", baseURL.host != nil else { throw LicensingAPIError.invalidResponse }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LicensingAPIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw LicensingAPIError.rejected(statusCode: http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Decodable {}
