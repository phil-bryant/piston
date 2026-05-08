import Foundation

public protocol DiagnosticsConsentProvider: Sendable {
    var diagnosticsUploadEnabled: Bool { get }
}

public struct PistonConfiguration: Sendable {
    public var maxEventsPerBatch: Int
    public var maxBatchBytes: Int
    public var uploadTimeoutSeconds: TimeInterval
    public var minimumUploadIntervalSeconds: TimeInterval
    public var allowsCellularOrExpensiveNetwork: Bool
    public var userAgent: String

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

    public static let `default` = PistonConfiguration(
        maxEventsPerBatch: 200,
        maxBatchBytes: 512 * 1024,
        uploadTimeoutSeconds: 30,
        minimumUploadIntervalSeconds: 300,
        allowsCellularOrExpensiveNetwork: true,
        userAgent: "Piston/1.0"
    )
}
