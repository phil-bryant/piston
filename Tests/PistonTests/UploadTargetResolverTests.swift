import Foundation
import XCTest
@testable import Piston

final class UploadTargetResolverTests: XCTestCase {
    func testDiscoverySuccessWritesCacheAndReturnsDiscoverySource() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = tempRoot.appendingPathComponent("upload-target-cache.json")

        let discovery = MockDiscoveryClient(
            result: .success(
                UploadTargetDiscoveryResponse(
                    uploadURL: "https://manifold.example.com/v1/events/batch",
                    ttlSeconds: 120,
                    expiresAt: nil,
                    routingVersion: "route-v1"
                )
            )
        )
        let resolver = UploadTargetResolver(
            configuration: .init(
                discoveryURL: URL(string: "https://valve.example.com/v1/piston/upload-target")!,
                cacheFileURL: cacheURL
            ),
            discoveryClient: discovery,
            nowProvider: { Date(timeIntervalSince1970: 1_000) }
        )

        let resolution = try await resolver.resolve(installID: "install-1", credential: "cred-1")

        XCTAssertEqual(resolution.source, .discovery)
        XCTAssertEqual(resolution.endpointURL.absoluteString, "https://manifold.example.com/v1/events/batch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testEnvironmentOverrideWinsOverDiscovery() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = tempRoot.appendingPathComponent("upload-target-cache.json")
        let discovery = MockDiscoveryClient(
            result: .success(
                UploadTargetDiscoveryResponse(
                    uploadURL: "https://manifold.example.com/v1/events/batch",
                    ttlSeconds: 120,
                    expiresAt: nil,
                    routingVersion: nil
                )
            )
        )
        let resolver = UploadTargetResolver(
            configuration: .init(
                discoveryURL: URL(string: "https://valve.example.com/v1/piston/upload-target")!,
                cacheFileURL: cacheURL
            ),
            discoveryClient: discovery,
            envProvider: { ["MANIFOLD_UPLOAD_URL": "https://override.example.com/v1/events"] }
        )

        let resolution = try await resolver.resolve(installID: "install-1", credential: "cred-1")

        XCTAssertEqual(resolution.source, .environmentOverride)
        XCTAssertEqual(resolution.endpointURL.absoluteString, "https://override.example.com/v1/events")
        XCTAssertEqual(discovery.callCount, 0)
    }

    func testDiscoveryFailureFallsBackToFreshCache() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = tempRoot.appendingPathComponent("upload-target-cache.json")

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let cachePayload = """
        {
          "cachedAt": -10,
          "expiresAt": 2000,
          "routingVersion": "route-v1",
          "uploadURL": "https://cache.example.com/v1/events"
        }
        """
        try Data(cachePayload.utf8).write(to: cacheURL, options: .atomic)

        let resolver = UploadTargetResolver(
            configuration: .init(
                discoveryURL: URL(string: "https://valve.example.com/v1/piston/upload-target")!,
                cacheFileURL: cacheURL
            ),
            discoveryClient: MockDiscoveryClient(result: .failure(URLError(.timedOut))),
            nowProvider: { Date(timeIntervalSinceReferenceDate: 1_500) }
        )

        let resolution = try await resolver.resolve(installID: "install-1", credential: "cred-1")

        XCTAssertEqual(resolution.source, .cacheFresh)
        XCTAssertEqual(resolution.endpointURL.absoluteString, "https://cache.example.com/v1/events")
    }

    func testDiscoveryFailureWithExpiredCacheThrowsCacheUnavailable() async {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = tempRoot.appendingPathComponent("upload-target-cache.json")

        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            let cachePayload = """
            {
              "cachedAt": 1,
              "expiresAt": 2,
              "routingVersion": "route-v1",
              "uploadURL": "https://cache.example.com/v1/events"
            }
            """
            try Data(cachePayload.utf8).write(to: cacheURL, options: .atomic)

            let resolver = UploadTargetResolver(
                configuration: .init(
                    discoveryURL: URL(string: "https://valve.example.com/v1/piston/upload-target")!,
                    cacheFileURL: cacheURL
                ),
                discoveryClient: MockDiscoveryClient(result: .failure(URLError(.cannotConnectToHost))),
                nowProvider: { Date(timeIntervalSinceReferenceDate: 100) }
            )

            _ = try await resolver.resolve(installID: "install-1", credential: "cred-1")
            XCTFail("Expected resolution to fail when cache is expired and no stale grace configured.")
        } catch let error as UploadTargetResolverError {
            XCTAssertEqual(error, .cacheUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDiscoveryFailureFallsBackToStaleCacheWithinGrace() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = tempRoot.appendingPathComponent("upload-target-cache.json")

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let cachePayload = """
        {
          "cachedAt": 1,
          "expiresAt": 100,
          "routingVersion": "route-v1",
          "uploadURL": "https://cache.example.com/v1/events"
        }
        """
        try Data(cachePayload.utf8).write(to: cacheURL, options: .atomic)

        let resolver = UploadTargetResolver(
            configuration: .init(
                discoveryURL: URL(string: "https://valve.example.com/v1/piston/upload-target")!,
                cacheFileURL: cacheURL,
                staleCacheGracePeriodSeconds: 30
            ),
            discoveryClient: MockDiscoveryClient(result: .failure(URLError(.timedOut))),
            nowProvider: { Date(timeIntervalSinceReferenceDate: 110) }
        )

        let resolution = try await resolver.resolve(installID: "install-1", credential: "cred-1")
        XCTAssertEqual(resolution.source, .cacheStale)
        XCTAssertEqual(resolution.endpointURL.absoluteString, "https://cache.example.com/v1/events")
    }
}

private final class MockDiscoveryClient: UploadTargetDiscovering, @unchecked Sendable {
    enum Result {
        case success(UploadTargetDiscoveryResponse)
        case failure(Error)
    }

    private let result: Result
    private(set) var callCount = 0
    private let lock = NSLock()

    init(result: Result) {
        self.result = result
    }

    func discoverUploadTarget(
        discoveryURL: URL,
        requestPayload: UploadTargetDiscoveryRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> UploadTargetDiscoveryResponse {
        lock.withLock {
            callCount += 1
        }

        switch result {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}
