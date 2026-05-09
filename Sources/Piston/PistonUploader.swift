import Foundation

// #R001: Abstract HTTP transport so uploader can use injected deterministic test doubles.
protocol PistonHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PistonHTTPSession {}

public final class PistonUploader: @unchecked Sendable {
    private let loop: PistonUploadLoop

    // #R010: Build URLSession from uploader configuration using ephemeral policy and configured timeout/network flags.
    public init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        consentProvider: DiagnosticsConsentProvider
    ) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.uploadTimeoutSeconds
        sessionConfiguration.timeoutIntervalForResource = configuration.uploadTimeoutSeconds
        sessionConfiguration.allowsCellularAccess = configuration.allowsCellularOrExpensiveNetwork
        sessionConfiguration.allowsExpensiveNetworkAccess = configuration.allowsCellularOrExpensiveNetwork
        let session = URLSession(configuration: sessionConfiguration)

        self.loop = PistonUploadLoop(
            endpointURL: endpointURL,
            configuration: configuration,
            consentProvider: consentProvider,
            session: session,
            fountainBridge: CFountainUploadBatchBridge()
        )
    }

    // #R015: Allow dependency injection of session and Fountain bridge for tests.
    init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        consentProvider: DiagnosticsConsentProvider,
        session: PistonHTTPSession,
        fountainBridge: FountainUploadBatchBridging
    ) {
        self.loop = PistonUploadLoop(
            endpointURL: endpointURL,
            configuration: configuration,
            consentProvider: consentProvider,
            session: session,
            fountainBridge: fountainBridge
        )
    }

    // #R005: Expose uploader controls that delegate start/stop/flush behavior to the actor loop.
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

// #R020: Isolate upload loop state/coordination inside an actor.
actor PistonUploadLoop {
    private let endpointURL: URL
    private let configuration: PistonConfiguration
    private let consentProvider: DiagnosticsConsentProvider
    private let session: PistonHTTPSession
    private let fountainBridge: FountainUploadBatchBridging
    private let timerIntervalNanoseconds: UInt64

    private var periodicTask: Task<Void, Never>?
    private var isFlushing = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        consentProvider: DiagnosticsConsentProvider,
        session: PistonHTTPSession,
        fountainBridge: FountainUploadBatchBridging
    ) {
        self.endpointURL = endpointURL
        self.configuration = configuration
        self.consentProvider = consentProvider
        self.session = session
        self.fountainBridge = fountainBridge
        let interval = max(configuration.minimumUploadIntervalSeconds, 1.0)
        self.timerIntervalNanoseconds = UInt64(interval * 1_000_000_000)
    }

    func start() {
        // #R025: Start at most one periodic task and flush one batch per interval tick.
        guard periodicTask == nil else {
            return
        }

        periodicTask = Task { [timerIntervalNanoseconds] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: timerIntervalNanoseconds)
                } catch {
                    break
                }
                await self.flushNow(maxBatches: 1)
            }
        }
    }

    func stop() {
        // #R030: Cancel and clear periodic task reference for clean stop behavior.
        periodicTask?.cancel()
        periodicTask = nil
    }

    func flushNow(maxBatches: Int) async {
        // #R040: Return immediately for non-positive counts and cap flush drain count to 5 batches.
        guard maxBatches > 0 else {
            return
        }

        // #R035: Keep flush single-flight; additional callers await active flush completion.
        if isFlushing {
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

        let cappedBatches = min(maxBatches, 5)
        for _ in 0..<cappedBatches {
            let uploadedOne = await uploadOneBatch()
            if !uploadedOne {
                return
            }
        }
    }

    private func uploadOneBatch() async -> Bool {
        // #R045: Gate claims by consent flag before attempting batch creation.
        guard consentProvider.diagnosticsUploadEnabled else {
            return false
        }

        // #R050: Stop current flush gracefully when no batch is available.
        guard let batch = fountainBridge.createUploadBatch(
            maxEvents: configuration.maxEventsPerBatch,
            maxBytes: configuration.maxBatchBytes
        ) else {
            return false
        }

        // #R055: Finalize nil payloads as status-zero failure with explicit invalid-payload message.
        guard let body = batch.payload else {
            batch.finalize(.failed(httpStatus: 0, errorMessage: "Invalid payload"))
            return false
        }

        do {
            let statusCode = try await post(body: body)
            // #R070: Mark 2xx uploads as success and continue batch drain.
            if (200..<300).contains(statusCode) {
                batch.finalize(.succeeded)
                return true
            }

            // #R075: Mark non-2xx responses as failures and stop current flush.
            batch.finalize(.failed(httpStatus: statusCode, errorMessage: "HTTP \(statusCode)"))
            return false
        } catch {
            // #R080: Mark transport errors as status-zero failures carrying error description.
            batch.finalize(.failed(httpStatus: 0, errorMessage: String(describing: error)))
            return false
        }
    }

    // #R060: Post JSON payload bytes with configured timeout and required headers.
    // #R065: Require HTTPURLResponse and propagate status code; throw badServerResponse for non-HTTP responses.
    private func post(body: Data) async throws -> Int {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = configuration.uploadTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return httpResponse.statusCode
    }
}
