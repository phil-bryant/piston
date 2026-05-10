import Foundation

// #R001: Abstract upload transport for production and test doubles.
protocol PistonHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PistonHTTPSession {}

// #R005: Expose uploader controls around one actor-owned loop.
public final class PistonUploader: @unchecked Sendable {
    private let loop: PistonUploadLoop

    public init(
        endpointURL: URL,
        configuration: PistonConfiguration,
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
            consentProvider: consentProvider,
            session: session,
            fountainBridge: CFountainUploadBatchBridge()
        )
    }

    init(
        endpointURL: URL,
        configuration: PistonConfiguration,
        consentProvider: DiagnosticsConsentProvider,
        session: PistonHTTPSession,
        fountainBridge: FountainUploadBatchBridging
    ) {
        // #R015: Allow dependency injection for tests.
        self.loop = PistonUploadLoop(
            endpointURL: endpointURL,
            configuration: configuration,
            consentProvider: consentProvider,
            session: session,
            fountainBridge: fountainBridge
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
        // #R025: Start one periodic task only when not already running.
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
        // #R030: Stop periodic task cleanly and clear task reference.
        periodicTask?.cancel()
        periodicTask = nil
    }

    func flushNow(maxBatches: Int) async {
        guard maxBatches > 0 else {
            return
        }

        // #R035: Keep flush single-flight by queueing waiters.
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

        // #R040: Cap flush drain count to at most five batches.
        let cappedBatches = min(maxBatches, 5)
        for _ in 0..<cappedBatches {
            let uploadedOne = await uploadOneBatch()
            if !uploadedOne {
                return
            }
        }
    }

    private func uploadOneBatch() async -> Bool {
        // #R045: Gate claims by consent before requesting work.
        guard consentProvider.diagnosticsUploadEnabled else {
            return false
        }

        // #R050: Stop on nil claimed batch without treating as error.
        guard let batch = fountainBridge.createUploadBatch(
            maxEvents: configuration.maxEventsPerBatch,
            maxBytes: configuration.maxBatchBytes
        ) else {
            return false
        }

        // #R055: Fail nil payload safely with status-zero marker.
        guard let body = batch.payload else {
            batch.finalize(.failed(httpStatus: 0, errorMessage: "Invalid payload"))
            return false
        }

        do {
            let statusCode = try await post(body: body)
            // #R070: Mark 2xx as success and continue draining.
            if (200..<300).contains(statusCode) {
                batch.finalize(.succeeded)
                return true
            }

            // #R075: Mark non-2xx as failure and stop flush loop.
            batch.finalize(.failed(httpStatus: statusCode, errorMessage: "HTTP \(statusCode)"))
            return false
        } catch {
            // #R080: Mark transport errors with status zero.
            batch.finalize(.failed(httpStatus: 0, errorMessage: String(describing: error)))
            return false
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

        let (_, response) = try await session.data(for: request)
        // #R065: Require HTTPURLResponse and return its status code.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return httpResponse.statusCode
    }
}
