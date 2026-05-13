import Foundation

// #R001: Abstract upload transport for production and test doubles.
protocol PistonHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PistonHTTPSession {}
typealias PistonStatusLogger = @Sendable (String) -> Void

// #R005: Expose uploader controls around one actor-owned loop.
public final class PistonUploader: @unchecked Sendable {
    private let loop: PistonUploadLoop
    private static let defaultStatusLogger: PistonStatusLogger = { message in
        print(message)
    }

    public init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        manifoldIngestKey: String? = nil,
        consentProvider: DiagnosticsConsentProvider
    ) {
        // #R010: Configure URLSession from explicit uploader config.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.uploadTimeoutSeconds
        sessionConfiguration.timeoutIntervalForResource = configuration.uploadTimeoutSeconds
        sessionConfiguration.allowsCellularAccess = configuration.allowsCellularOrExpensiveNetwork
        sessionConfiguration.allowsExpensiveNetworkAccess = configuration.allowsCellularOrExpensiveNetwork
        let session = URLSession(configuration: sessionConfiguration)

        self.loop = PistonUploadLoop(
            endpointURL: endpointURL,
            configuration: configuration,
            manifoldIngestKey: manifoldIngestKey,
            consentProvider: consentProvider,
            session: session,
            fountainBridge: CFountainUploadBatchBridge(),
            statusLogger: Self.defaultStatusLogger
        )
    }

    init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        manifoldIngestKey: String? = nil,
        consentProvider: DiagnosticsConsentProvider,
        session: PistonHTTPSession,
        fountainBridge: FountainUploadBatchBridging,
        statusLogger: @escaping PistonStatusLogger = { _ in }
    ) {
        // #R015: Allow dependency injection for tests.
        self.loop = PistonUploadLoop(
            endpointURL: endpointURL,
            configuration: configuration,
            manifoldIngestKey: manifoldIngestKey,
            consentProvider: consentProvider,
            session: session,
            fountainBridge: fountainBridge,
            statusLogger: statusLogger
        )
    }

    public func start() {
        Task {
            await loop.start()
        }
    }

    public func stop() {
        Task {
            await loop.stop()
        }
    }

    public func flushNow() async {
        await loop.flushNow(maxBatches: 5)
    }
}

// #R020: Isolate periodic and flush coordination state inside actor.
actor PistonUploadLoop {
    private let endpointURL: URL
    private let configuration: PistonConfiguration
    private let manifoldIngestKey: String?
    private let consentProvider: DiagnosticsConsentProvider
    private let session: PistonHTTPSession
    private let fountainBridge: FountainUploadBatchBridging
    private let statusLogger: PistonStatusLogger
    private let timerIntervalNanoseconds: UInt64

    private var periodicTask: Task<Void, Never>?
    private var isFlushing = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        manifoldIngestKey: String?,
        consentProvider: DiagnosticsConsentProvider,
        session: PistonHTTPSession,
        fountainBridge: FountainUploadBatchBridging,
        statusLogger: @escaping PistonStatusLogger
    ) {
        self.endpointURL = endpointURL
        self.configuration = configuration
        self.manifoldIngestKey = manifoldIngestKey
        self.consentProvider = consentProvider
        self.session = session
        self.fountainBridge = fountainBridge
        self.statusLogger = statusLogger
        let interval = max(configuration.minimumUploadIntervalSeconds, 1.0)
        self.timerIntervalNanoseconds = UInt64(interval * 1_000_000_000)
    }

    func start() {
        // #R025: Start one periodic task only when not already running.
        guard periodicTask == nil else {
            return
        }

        let endpoint = endpointURL.absoluteString
        let intervalSeconds = configuration.minimumUploadIntervalSeconds
        logStatus("periodic loop starting endpoint=\(endpoint) interval_seconds=\(intervalSeconds)")
        periodicTask = Task { [timerIntervalNanoseconds] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: timerIntervalNanoseconds)
                } catch {
                    break
                }
                logStatus("poll tick begin")
                await self.flushNow(maxBatches: 1)
                logStatus("poll tick end")
            }
            self.logStatus("periodic loop stopped")
        }
    }

    func stop() {
        // #R030: Stop periodic task cleanly and clear task reference.
        periodicTask?.cancel()
        periodicTask = nil
    }

    func flushNow(maxBatches: Int) async {
        guard maxBatches > 0 else {
            logStatus("flush skipped reason=invalid_max_batches value=\(maxBatches)")
            return
        }

        // #R035: Keep flush single-flight by queueing waiters.
        if isFlushing {
            logStatus("flush joined reason=already_flushing")
            await withCheckedContinuation { continuation in
                flushWaiters.append(continuation)
            }
            return
        }

        isFlushing = true
        defer {
            isFlushing = false
            let waiters = flushWaiters
            flushWaiters.removeAll(keepingCapacity: true)
            waiters.forEach { $0.resume() }
        }

        // #R040: Cap flush drain count to at most five batches.
        let cappedBatches = min(maxBatches, 5)
        logStatus("flush start requested_max=\(maxBatches) capped_max=\(cappedBatches)")
        // #R085: Log explicit flush-stop outcomes (`flush end reason=<value>` from `flushStopReason`).
        for _ in 0..<cappedBatches {
            let outcome = await uploadOneBatch()
            if !outcome.shouldContinueFlush {
                logStatus("flush end reason=\(outcome.flushStopReason)")
                return
            }
        }
        logStatus("flush end reason=max_batches_reached")
    }

    private func uploadOneBatch() async -> UploadAttemptOutcome {
        // #R045: Gate claims by consent before requesting work.
        guard consentProvider.diagnosticsUploadEnabled else {
            logStatus("poll result consent=disabled action=skip")
            return .consentDisabled
        }

        // #R050: Stop on nil claimed batch without treating as error.
        guard let batch = fountainBridge.createUploadBatch(
            maxEvents: configuration.maxEventsPerBatch,
            maxBytes: configuration.maxBatchBytes
        ) else {
            let maxEv = configuration.maxEventsPerBatch
            let maxBy = configuration.maxBatchBytes
            logStatus("poll result consent=enabled action=no_batch max_events=\(maxEv) max_bytes=\(maxBy)")
            return .noBatch
        }

        let payloadBytes = batch.payload?.count ?? -1
        logStatus(
            "poll result action=batch_claimed batch_id=\(batch.batchID) payload_bytes=\(payloadBytes)"
        )

        // #R055: Fail nil payload safely with status-zero marker.
        guard let body = batch.payload else {
            batch.finalize(.failed(httpStatus: 0, errorMessage: "Invalid payload"))
            logStatus("poll result action=batch_failed batch_id=\(batch.batchID) reason=invalid_payload")
            return .invalidPayload
        }

        do {
            let statusCode = try await post(body: body)
            // #R070: Mark 2xx as success and continue draining.
            if (200..<300).contains(statusCode) {
                batch.finalize(.succeeded)
                logStatus("poll result action=batch_succeeded batch_id=\(batch.batchID) http_status=\(statusCode)")
                return .uploadedBatch
            }

            // #R075: Mark non-2xx as failure and stop flush loop.
            batch.finalize(.failed(httpStatus: statusCode, errorMessage: "HTTP \(statusCode)"))
            logStatus("poll result action=batch_failed batch_id=\(batch.batchID) http_status=\(statusCode)")
            return .httpFailure(statusCode)
        } catch {
            // #R080: Mark transport errors with status zero.
            batch.finalize(.failed(httpStatus: 0, errorMessage: String(describing: error)))
            logStatus("poll result action=batch_failed batch_id=\(batch.batchID) reason=transport_error error=\(error)")
            return .transportFailure
        }
    }

    // #R060: Post JSON payload bytes with configured headers/timeouts.
    private func post(body: Data) async throws -> Int {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = configuration.uploadTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let manifoldIngestKey, !manifoldIngestKey.isEmpty {
            request.setValue(manifoldIngestKey, forHTTPHeaderField: "X-Manifold-Ingest-Key")
        }

        let (_, response) = try await session.data(for: request)
        // #R065: Require HTTPURLResponse and return its status code.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return httpResponse.statusCode
    }

    private func logStatus(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        statusLogger("Piston poll [\(timestamp)]: \(message)")
    }

    private enum UploadAttemptOutcome {
        case uploadedBatch
        case consentDisabled
        case noBatch
        case invalidPayload
        case httpFailure(Int)
        case transportFailure

        var shouldContinueFlush: Bool {
            if case .uploadedBatch = self {
                return true
            }
            return false
        }

        var flushStopReason: String {
            switch self {
            case .uploadedBatch:
                return "max_batches_reached"
            case .consentDisabled:
                return "consent_disabled"
            case .noBatch:
                return "no_batch"
            case .invalidPayload:
                return "invalid_payload"
            case let .httpFailure(statusCode):
                return "batch_failed_http_\(statusCode)"
            case .transportFailure:
                return "transport_error"
            }
        }
    }
}
