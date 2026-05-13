import Foundation
@testable import Piston

// Shared mocks and helpers for `PistonUploaderTests` (keeps the test case file under SwiftLint file_length).

final class LockedLogRecorder: @unchecked Sendable {
    private var entries: [String] = []
    private let lock = NSLock()

    func append(_ value: String) {
        lock.withLock {
            entries.append(value)
        }
    }

    func contains(_ fragment: String) -> Bool {
        lock.withLock {
            entries.contains { $0.contains(fragment) }
        }
    }
}

struct MutableConsentProvider: DiagnosticsConsentProvider {
    var diagnosticsUploadEnabled: Bool

    init(enabled: Bool) {
        self.diagnosticsUploadEnabled = enabled
    }
}

final class MockFountainBridge: FountainUploadBatchBridging, @unchecked Sendable {
    struct QueuedBatch {
        let id: String
        let payload: Data?
    }

    private var queuedBatches: [QueuedBatch]
    private(set) var createCallCount = 0
    private(set) var successIDs: [String] = []
    private(set) var failureIDs: [String] = []
    private(set) var failureHTTPStatusByID: [String: Int] = [:]
    private(set) var freeCountByID: [String: Int] = [:]
    private(set) var finalizeCallCountByID: [String: Int] = [:]
    private let lock = NSLock()

    init(queued: [QueuedBatch]) {
        self.queuedBatches = queued
    }

    func createUploadBatch(maxEvents: Int, maxBytes: Int) -> ClaimedUploadBatch? {
        lock.lock()
        defer { lock.unlock() }

        createCallCount += 1
        guard !queuedBatches.isEmpty else {
            return nil
        }

        let next = queuedBatches.removeFirst()
        return ClaimedUploadBatch(batchID: next.id, payload: next.payload) { [weak self] result in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            self.finalizeCallCountByID[next.id, default: 0] += 1
            self.freeCountByID[next.id, default: 0] += 1

            switch result {
            case .succeeded:
                self.successIDs.append(next.id)
            case let .failed(httpStatus, _):
                self.failureIDs.append(next.id)
                self.failureHTTPStatusByID[next.id] = httpStatus
            }
        }
    }
}

final class MockHTTPSession: PistonHTTPSession, @unchecked Sendable {
    enum Result {
        case success(HTTPURLResponse)
        case failure(Error)
    }

    private let result: Result
    private let lock = NSLock()
    private(set) var requestCount = 0
    private(set) var lastRequest: URLRequest?

    init(result: Result) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            requestCount += 1
            lastRequest = request
        }

        switch result {
        case let .success(response):
            return (Data(), response)
        case let .failure(error):
            throw error
        }
    }
}

private actor BlockingGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll(keepingCapacity: true)
        currentWaiters.forEach { $0.resume() }
    }
}

final class BlockingHTTPSession: PistonHTTPSession, @unchecked Sendable {
    private let statusCode: Int
    private let gate = BlockingGate()
    private let state = BlockingSessionState()

    init(statusCode: Int) {
        self.statusCode = statusCode
    }

    var maxConcurrentRequests: Int {
        get async {
            await state.maxConcurrent
        }
    }

    func unblock() async {
        await gate.open()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await state.requestStarted()
        defer { Task { await self.state.requestFinished() } }

        await gate.wait()

        let response = HTTPURLResponse(statusCode: statusCode)
        return (Data(), response)
    }
}

private actor BlockingSessionState {
    private var currentConcurrent = 0
    private(set) var maxConcurrent = 0

    func requestStarted() {
        currentConcurrent += 1
        maxConcurrent = max(maxConcurrent, currentConcurrent)
    }

    func requestFinished() {
        currentConcurrent -= 1
    }
}

extension HTTPURLResponse {
    convenience init(statusCode: Int) {
        self.init(
            url: URL(string: "https://example.com/upload")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
