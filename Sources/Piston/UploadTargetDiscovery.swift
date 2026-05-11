import Foundation

// #R001: Model discovery request payload fields for install identity.
public struct UploadTargetDiscoveryRequest: Encodable, Sendable {
    public var installID: String
    public var credential: String

    public init(installID: String, credential: String) {
        self.installID = installID
        self.credential = credential
    }

    enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case credential
    }
}

// #R005: Model discovery response payload from Valve control plane.
public struct UploadTargetDiscoveryResponse: Decodable, Sendable {
    public var uploadURL: String
    public var ttlSeconds: Int?
    public var expiresAt: String?
    public var routingVersion: String?

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case ttlSeconds = "ttl_seconds"
        case expiresAt = "expires_at"
        case routingVersion = "routing_version"
    }
}

// #R010: Mirror URLSession-style async data contract for discovery transport.
protocol UploadTargetDiscoverySession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: UploadTargetDiscoverySession {}

// #R015: Expose a typed discovery client seam for resolver testing.
protocol UploadTargetDiscovering: Sendable {
    func discoverUploadTarget(
        discoveryURL: URL,
        requestPayload: UploadTargetDiscoveryRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> UploadTargetDiscoveryResponse
}

enum UploadTargetDiscoveryClientError: Error {
    case nonHTTPResponse
    case nonSuccessStatus(Int)
}

struct HTTPUploadTargetDiscoveryClient: UploadTargetDiscovering {
    private let session: UploadTargetDiscoverySession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        session: UploadTargetDiscoverySession = URLSession.shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    // #R020: POST discovery JSON body and decode upload-target response.
    func discoverUploadTarget(
        discoveryURL: URL,
        requestPayload: UploadTargetDiscoveryRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> UploadTargetDiscoveryResponse {
        var request = URLRequest(url: discoveryURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try encoder.encode(requestPayload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadTargetDiscoveryClientError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UploadTargetDiscoveryClientError.nonSuccessStatus(httpResponse.statusCode)
        }

        return try decoder.decode(UploadTargetDiscoveryResponse.self, from: responseData)
    }
}
