import Foundation

public enum UploadTargetSource: String, Sendable {
    case discovery = "discovery"
    case cacheFresh = "cache-fresh"
    case cacheStale = "cache-stale"
    case environmentOverride = "env"
}

public struct UploadTargetResolution: Sendable {
    public var endpointURL: URL
    public var source: UploadTargetSource

    public init(endpointURL: URL, source: UploadTargetSource) {
        self.endpointURL = endpointURL
        self.source = source
    }
}

public struct UploadTargetResolverConfiguration: Sendable {
    public var discoveryURL: URL
    public var cacheFileURL: URL
    public var allowedUploadHosts: Set<String>
    public var discoveryTimeoutSeconds: TimeInterval
    public var staleCacheGracePeriodSeconds: TimeInterval

    public init(
        discoveryURL: URL,
        cacheFileURL: URL,
        allowedUploadHosts: Set<String> = [],
        discoveryTimeoutSeconds: TimeInterval = 8,
        staleCacheGracePeriodSeconds: TimeInterval = 0
    ) {
        self.discoveryURL = discoveryURL
        self.cacheFileURL = cacheFileURL
        self.allowedUploadHosts = allowedUploadHosts
        self.discoveryTimeoutSeconds = discoveryTimeoutSeconds
        self.staleCacheGracePeriodSeconds = staleCacheGracePeriodSeconds
    }
}

public enum UploadTargetResolverError: Error, Equatable {
    case missingDiscoveryURL
    case invalidDiscoveryResponse(String)
    case invalidUploadURL(String)
    case cacheUnavailable
}

private struct UploadTargetCacheRecord: Codable, Sendable {
    var uploadURL: String
    var expiresAt: Date
    var cachedAt: Date
    var routingVersion: String?
}

public final class UploadTargetResolver: @unchecked Sendable {
    private let configuration: UploadTargetResolverConfiguration
    private let discoveryClient: UploadTargetDiscovering
    private let fileManager: FileManager
    private let nowProvider: @Sendable () -> Date
    private let envProvider: @Sendable () -> [String: String]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public convenience init(
        configuration: UploadTargetResolverConfiguration,
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        envProvider: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.init(
            configuration: configuration,
            discoveryClient: HTTPUploadTargetDiscoveryClient(),
            fileManager: fileManager,
            nowProvider: nowProvider,
            envProvider: envProvider
        )
    }

    init(
        configuration: UploadTargetResolverConfiguration,
        discoveryClient: UploadTargetDiscovering,
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        envProvider: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.configuration = configuration
        self.discoveryClient = discoveryClient
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.envProvider = envProvider
        self.encoder.outputFormatting = [.sortedKeys]
    }

    // #R025: Resolve endpoint from env override, discovery, then cache fallback.
    public func resolve(installID: String, credential: String) async throws -> UploadTargetResolution {
        if let envOverride = envProvider()["MANIFOLD_UPLOAD_URL"], !envOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let endpointURL = try validateUploadURL(rawURL: envOverride)
            return UploadTargetResolution(endpointURL: endpointURL, source: .environmentOverride)
        }

        do {
            let response = try await discoveryClient.discoverUploadTarget(
                discoveryURL: configuration.discoveryURL,
                requestPayload: UploadTargetDiscoveryRequest(installID: installID, credential: credential),
                timeoutSeconds: configuration.discoveryTimeoutSeconds
            )
            let endpointURL = try validateUploadURL(rawURL: response.uploadURL)
            let now = nowProvider()
            let expiresAt = try deriveExpiry(response: response, now: now)
            let cacheRecord = UploadTargetCacheRecord(
                uploadURL: endpointURL.absoluteString,
                expiresAt: expiresAt,
                cachedAt: now,
                routingVersion: response.routingVersion
            )
            try writeCache(record: cacheRecord)
            return UploadTargetResolution(endpointURL: endpointURL, source: .discovery)
        } catch {
            if let fallback = try readFallbackFromCache() {
                return fallback
            }
            throw error
        }
    }

    private func deriveExpiry(response: UploadTargetDiscoveryResponse, now: Date) throws -> Date {
        if let ttl = response.ttlSeconds, ttl > 0 {
            return now.addingTimeInterval(TimeInterval(ttl))
        }
        if let expiresAt = response.expiresAt, !expiresAt.isEmpty {
            let formatter = ISO8601DateFormatter()
            if let parsed = formatter.date(from: expiresAt) {
                return parsed
            }
        }
        throw UploadTargetResolverError.invalidDiscoveryResponse("Missing ttl_seconds/expires_at")
    }

    private func validateUploadURL(rawURL: String) throws -> URL {
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), scheme == "https", let host = url.host else {
            throw UploadTargetResolverError.invalidUploadURL(rawURL)
        }

        if !configuration.allowedUploadHosts.isEmpty && !configuration.allowedUploadHosts.contains(host) {
            throw UploadTargetResolverError.invalidUploadURL(rawURL)
        }
        return url
    }

    private func writeCache(record: UploadTargetCacheRecord) throws {
        let parentDirectory = configuration.cacheFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        let payload = try encoder.encode(record)
        try payload.write(to: configuration.cacheFileURL, options: .atomic)
    }

    private func readFallbackFromCache() throws -> UploadTargetResolution? {
        guard fileManager.fileExists(atPath: configuration.cacheFileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: configuration.cacheFileURL)
        let record = try decoder.decode(UploadTargetCacheRecord.self, from: data)
        let endpointURL = try validateUploadURL(rawURL: record.uploadURL)
        let now = nowProvider()

        if now <= record.expiresAt {
            return UploadTargetResolution(endpointURL: endpointURL, source: .cacheFresh)
        }

        let staleDeadline = record.expiresAt.addingTimeInterval(configuration.staleCacheGracePeriodSeconds)
        if configuration.staleCacheGracePeriodSeconds > 0, now <= staleDeadline {
            return UploadTargetResolution(endpointURL: endpointURL, source: .cacheStale)
        }

        throw UploadTargetResolverError.cacheUnavailable
    }
}
