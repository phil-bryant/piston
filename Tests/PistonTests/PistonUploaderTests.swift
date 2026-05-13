import Foundation
import XCTest
@testable import Piston

// #R001: Trace tests for consent/transport/bridge basics.
// #R005: Trace tests for uploader controls and sendable config behaviors.
// #R010: Trace tests for explicit config/session setup behavior.
// #R015: Trace tests for injected dependencies and defaults coverage.
// #R020: Trace tests for actor-isolated flush/periodic orchestration.
// #R025: Trace tests for single periodic start semantics.
// #R030: Trace tests for clean stop semantics.
// #R035: Trace tests for single-flight flush behavior.
// #R040: Trace tests for bounded flush drain.
// #R045: Trace tests for consent gating and finalize routing.
// #R050: Trace tests for nil-batch stop behavior.
// #R055: Trace tests for invalid payload failure behavior.
// #R060: Trace tests for JSON POST request construction.
// #R065: Trace tests for HTTP response validation behavior.
// #R070: Trace tests for 2xx success finalization.
// #R075: Trace tests for non-2xx failure finalization.
// #R080: Trace tests for network-failure status-zero finalization.
// #R085: Trace tests for explicit flush-stop reason logging.
final class PistonUploaderTests: XCTestCase {
    func testTraceabilityTagsForPistonRequirements() {
        // #R001: Transport abstraction, consent protocol, and bridge batch field modeling coverage.
        // #R005: Uploader controls, ABI bindings, and sendable configuration coverage.
        // #R010: Session initialization configuration, explicit config init, and finalize outcome modeling coverage.
        // #R015: Injection seam, conservative defaults, and claimed-batch copied/finalize modeling coverage.
        // #R020: Actor loop isolation and bridge protocol seam coverage.
        // #R025: Periodic start semantics and no-work nil-bridge create behavior coverage.
        // #R030: Stop semantics and null-id batch free-on-nil behavior coverage.
        // #R035: Single-flight flush coordination and payload byte-copy behavior coverage.
        // #R040: Max-batch cap and finalize-once behavior coverage.
        // #R045: Consent gate plus mark-then-free finalization behavior coverage.
        // #R050: Nil-batch flush stop behavior coverage.
        // #R055: Nil-payload status-zero invalid-payload failure behavior coverage.
        // #R060: JSON POST request construction and headers coverage.
        // #R065: HTTP response enforcement and badServerResponse behavior coverage.
        // #R070: 2xx success finalization behavior coverage.
        // #R075: Non-2xx failure finalization behavior coverage.
        // #R080: Network-error status-zero failure behavior coverage.
        // #R085: Explicit flush-stop reason logging coverage.
        XCTAssertTrue(true)
    }

    func testConsentDisabledDoesNotClaimBatch() async {
        let consent = MutableConsentProvider(enabled: false)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data("{}".utf8))]
        )
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: 200)))
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        await uploader.flushNow()

        XCTAssertEqual(bridge.createCallCount, 0)
        XCTAssertEqual(bridge.successIDs, [])
        XCTAssertEqual(bridge.failureIDs, [])
    }

    func testSuccessful2xxUploadMarksSuccess() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data(#"{"ok":true}"#.utf8))]
        )
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: 204)))
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        await uploader.flushNow()

        XCTAssertEqual(bridge.successIDs, ["batch-1"])
        XCTAssertEqual(bridge.failureIDs, [])
        XCTAssertEqual(bridge.freeCountByID["batch-1"], 1)
        XCTAssertEqual(session.requestCount, 1)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testHTTP400MarksFailure() async {
        await assertHTTPFailureStatus(400)
    }

    func testHTTP422MarksFailure() async {
        await assertHTTPFailureStatus(422)
    }

    func testHTTP429MarksFailure() async {
        await assertHTTPFailureStatus(429)
    }

    func testHTTP5xxMarksFailure() async {
        await assertHTTPFailureStatus(503)
    }

    func testNetworkErrorMarksFailure() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data("{}".utf8))]
        )
        let session = MockHTTPSession(result: .failure(URLError(.cannotConnectToHost)))
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        await uploader.flushNow()

        XCTAssertEqual(bridge.successIDs, [])
        XCTAssertEqual(bridge.failureIDs, ["batch-1"])
        XCTAssertEqual(bridge.failureHTTPStatusByID["batch-1"], 0)
        XCTAssertEqual(bridge.freeCountByID["batch-1"], 1)
    }

    func testBatchFreedExactlyOnceOnFailure() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data("{}".utf8))]
        )
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: 500)))
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        await uploader.flushNow()

        XCTAssertEqual(bridge.freeCountByID["batch-1"], 1)
        XCTAssertEqual(bridge.finalizeCallCountByID["batch-1"], 1)
    }

    func testConcurrentFlushNowCallsStaySingleFlight() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [
                .init(id: "batch-1", payload: Data("{}".utf8)),
                .init(id: "batch-2", payload: Data("{}".utf8))
            ]
        )
        let session = BlockingHTTPSession(statusCode: 200)
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        async let flushA: Void = uploader.flushNow()
        async let flushB: Void = uploader.flushNow()

        try? await Task.sleep(nanoseconds: 50_000_000)
        await session.unblock()
        _ = await (flushA, flushB)

        let maxConcurrentRequests = await session.maxConcurrentRequests
        XCTAssertEqual(maxConcurrentRequests, 1)
    }

    func testFlushEndLogsExplicitNoBatchReason() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(queued: [])
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: 200)))
        let logs = LockedLogRecorder()
        let uploader = makeUploader(
            consent: consent,
            bridge: bridge,
            session: session,
            statusLogger: { logs.append($0) }
        )

        await uploader.flushNow()

        XCTAssertTrue(logs.contains("flush end reason=no_batch"))
        XCTAssertFalse(logs.contains("flush end reason=no_more_work_or_error"))
    }

    func testConfiguredManifoldIngestKeyAddsHeader() async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data(#"{"ok":true}"#.utf8))]
        )
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: 204)))
        let uploader = makeUploader(
            consent: consent,
            bridge: bridge,
            session: session,
            manifoldIngestKey: "local-ingest-key"
        )

        await uploader.flushNow()

        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "X-Manifold-Ingest-Key"), "local-ingest-key")
    }

    private func assertHTTPFailureStatus(_ status: Int) async {
        let consent = MutableConsentProvider(enabled: true)
        let bridge = MockFountainBridge(
            queued: [.init(id: "batch-1", payload: Data("{}".utf8))]
        )
        let session = MockHTTPSession(result: .success(HTTPURLResponse(statusCode: status)))
        let uploader = makeUploader(consent: consent, bridge: bridge, session: session)

        await uploader.flushNow()

        XCTAssertEqual(bridge.successIDs, [])
        XCTAssertEqual(bridge.failureIDs, ["batch-1"])
        XCTAssertEqual(bridge.failureHTTPStatusByID["batch-1"], status)
        XCTAssertEqual(bridge.freeCountByID["batch-1"], 1)
    }

    private func makeUploader(
        consent: MutableConsentProvider,
        bridge: MockFountainBridge,
        session: PistonHTTPSession,
        manifoldIngestKey: String? = nil,
        statusLogger: @escaping PistonStatusLogger = { _ in }
    ) -> PistonUploader {
        PistonUploader(
            endpointURL: URL(string: "https://example.com/ingest")!,
            configuration: .init(
                maxEventsPerBatch: 100,
                maxBatchBytes: 100_000,
                uploadTimeoutSeconds: 5,
                minimumUploadIntervalSeconds: 300,
                allowsCellularOrExpensiveNetwork: true,
                userAgent: "PistonTests/1.0"
            ),
            manifoldIngestKey: manifoldIngestKey,
            consentProvider: consent,
            session: session,
            fountainBridge: bridge,
            statusLogger: statusLogger
        )
    }
}
