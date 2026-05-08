import Foundation

public struct FountainUploadBatch {
    public var batch_id: UnsafeMutablePointer<CChar>?
    public var json_payload: UnsafeMutablePointer<CChar>?
    public var json_payload_length: Int

    public init(
        batch_id: UnsafeMutablePointer<CChar>? = nil,
        json_payload: UnsafeMutablePointer<CChar>? = nil,
        json_payload_length: Int = 0
    ) {
        self.batch_id = batch_id
        self.json_payload = json_payload
        self.json_payload_length = json_payload_length
    }
}

@_silgen_name("FountainCreateUploadBatch")
private func FountainCreateUploadBatchC(
    _ maxEvents: Int,
    _ maxBytes: Int,
    _ outBatch: UnsafeMutablePointer<FountainUploadBatch>
) -> Bool

@_silgen_name("FountainMarkUploadBatchSucceeded")
private func FountainMarkUploadBatchSucceededC(_ batchID: UnsafePointer<CChar>)

@_silgen_name("FountainMarkUploadBatchFailed")
private func FountainMarkUploadBatchFailedC(
    _ batchID: UnsafePointer<CChar>,
    _ httpStatus: Int32,
    _ errorMessage: UnsafePointer<CChar>
)

@_silgen_name("FountainFreeUploadBatch")
private func FountainFreeUploadBatchC(_ batch: UnsafeMutablePointer<FountainUploadBatch>)

enum FountainBatchResult {
    case succeeded
    case failed(httpStatus: Int, errorMessage: String)
}

struct ClaimedUploadBatch {
    let batchID: String
    let payload: Data?
    let finalize: (FountainBatchResult) -> Void
}

protocol FountainUploadBatchBridging {
    func createUploadBatch(maxEvents: Int, maxBytes: Int) -> ClaimedUploadBatch?
}

struct CFountainUploadBatchBridge: FountainUploadBatchBridging {
    func createUploadBatch(maxEvents: Int, maxBytes: Int) -> ClaimedUploadBatch? {
        var raw = FountainUploadBatch()
        let hasBatch = FountainCreateUploadBatchC(maxEvents, maxBytes, &raw)
        guard hasBatch else {
            return nil
        }

        guard let idPtr = raw.batch_id else {
            FountainFreeUploadBatchC(&raw)
            return nil
        }

        let batchID = String(cString: idPtr)
        let payload: Data?
        if raw.json_payload_length == 0 {
            payload = Data()
        } else if let payloadPtr = raw.json_payload, raw.json_payload_length > 0 {
            payload = Data(bytes: payloadPtr, count: raw.json_payload_length)
        } else {
            payload = nil
        }

        let finalized = NSLock()
        var didFinalize = false

        let finalize: (FountainBatchResult) -> Void = { result in
            finalized.lock()
            defer { finalized.unlock() }
            guard !didFinalize else {
                return
            }
            didFinalize = true

            switch result {
            case .succeeded:
                batchID.withCString { FountainMarkUploadBatchSucceededC($0) }
            case let .failed(httpStatus, errorMessage):
                batchID.withCString { batchIDCString in
                    errorMessage.withCString { errorCString in
                        FountainMarkUploadBatchFailedC(batchIDCString, Int32(httpStatus), errorCString)
                    }
                }
            }

            FountainFreeUploadBatchC(&raw)
        }

        return ClaimedUploadBatch(batchID: batchID, payload: payload, finalize: finalize)
    }
}
