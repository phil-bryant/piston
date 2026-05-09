import Foundation

// #R001: Expose diagnostics upload consent flag used to gate batch-claim behavior.
public protocol DiagnosticsConsentProvider: Sendable {
    var diagnosticsUploadEnabled: Bool { get }
}

// #R005: Keep uploader configuration sendable across actor boundaries.
public struct PistonConfiguration: Sendable {
    public var maxEventsPerBatch: Int
    public var maxBatchBytes: Int
    public var uploadTimeoutSeconds: TimeInterval
    public var minimumUploadIntervalSeconds: TimeInterval
    public var allowsCellularOrExpensiveNetwork: Bool
    public var userAgent: String

    // #R010: Require explicit initializer fields for all operational uploader settings.
    public init(
        maxEventsPerBatch: Int,
        maxBatchBytes: Int,
        uploadTimeoutSeconds: TimeInterval,
        minimumUploadIntervalSeconds: TimeInterval,
        allowsCellularOrExpensiveNetwork: Bool,
        userAgent: String
    ) {
        self.maxEventsPerBatch = maxEventsPerBatch
        self.maxBatchBytes = maxBatchBytes
        self.uploadTimeoutSeconds = uploadTimeoutSeconds
        self.minimumUploadIntervalSeconds = minimumUploadIntervalSeconds
        self.allowsCellularOrExpensiveNetwork = allowsCellularOrExpensiveNetwork
        self.userAgent = userAgent
    }

    // #R015: Provide conservative production defaults for batch sizing, timing, network policy, and user-agent.
    public static let `default` = PistonConfiguration(
        maxEventsPerBatch: 200,
        maxBatchBytes: 512 * 1024,
        uploadTimeoutSeconds: 30,
        minimumUploadIntervalSeconds: 300,
        allowsCellularOrExpensiveNetwork: true,
        userAgent: "Piston/1.0"
    )
}
