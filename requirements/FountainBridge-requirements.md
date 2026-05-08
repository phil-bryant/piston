# FountainBridge Requirements

## Scope

Applies to `Sources/Piston/FountainBridge.swift`.

R001  Statement: Mirror C batch fields.
Design: `FountainUploadBatch` exposes `batch_id`, `json_payload`, and `json_payload_length` with matching pointer/int storage and a memberwise-style initializer defaulting to nil/zero.
Tests:
- Construct `FountainUploadBatch()` and verify all fields default to null/zero values.
- Construct with explicit pointer/length values and verify stored fields match inputs.

R005  Statement: Bind exact ABI symbols.
Design: Bridge declares `@_silgen_name` functions for create/success/failure/free operations using ABI-compatible parameter order and pointer types.
Tests:
- Link against a test Fountain shim and verify each symbol resolves at runtime.
- Invoke create/mark/free through bridge path and verify shim call counters increment.

R010  Statement: Model finalize outcomes.
Design: `FountainBatchResult` models either `.succeeded` or `.failed(httpStatus:errorMessage:)` for downstream mark calls.
Tests:
- Finalize one claimed batch with `.succeeded` and verify success mark path is used.
- Finalize one claimed batch with `.failed` and verify failure mark path carries status/message.

R015  Statement: Expose claimed batch copies.
Design: `ClaimedUploadBatch` stores copied `batchID` string, optional copied payload `Data`, and a `finalize` closure that performs mark+free behavior.
Tests:
- Claim a valid batch and verify returned `batchID` and payload bytes are Swift-owned copies.
- Claim a batch with invalid payload pointer/length combination and verify payload becomes nil.

R020  Statement: Abstract batch creation bridge.
Design: `FountainUploadBatchBridging` defines `createUploadBatch(maxEvents:maxBytes:) -> ClaimedUploadBatch?` as the integration seam for production and test bridges.
Tests:
- Inject a mock bridge into uploader tests and verify uploader behavior is driven by mock outputs.
- Return nil from mock bridge and verify uploader treats it as no batch available.

R025  Statement: Return nil on no work.
Design: `CFountainUploadBatchBridge.createUploadBatch` calls `FountainCreateUploadBatch...` and immediately returns nil when the C layer reports false.
Tests:
- Configure Fountain shim to return false and verify bridge returns nil.
- Verify mark/free callbacks are not invoked when no batch is created.

R030  Statement: Free null-id raw batches.
Design: If `batch_id` pointer is null, bridge calls `FountainFreeUploadBatch` and returns nil to avoid leaking raw batch allocations.
Tests:
- Return create=true with null batch id and verify free is called once.
- Verify nil batch is returned for null-id create results.

R035  Statement: Copy payload bytes exactly.
Design: Bridge maps zero-length payload to empty `Data`; maps positive-length+nonnull pointer to copied bytes; maps invalid pointer/length state to nil payload.
Tests:
- Return non-empty payload and verify resulting `Data` equals source bytes exactly.
- Return zero length payload and verify resulting payload is empty `Data`.

R040  Statement: Finalize exactly once.
Design: `finalize` closure uses lock-protected `didFinalize` guard so mark/free work executes at most once even if finalize is called repeatedly.
Tests:
- Call `finalize(.succeeded)` twice and verify success mark and free each execute once.
- Call `finalize(.failed(...))` then finalize again and verify only first call mutates Fountain state.

R045  Statement: Mark then free batch.
Design: Finalizer routes `.succeeded` to `FountainMarkUploadBatchSucceeded`; routes `.failed` to `FountainMarkUploadBatchFailed` with `Int32` status and error string; always frees after marking.
Tests:
- Finalize with success and verify success mark receives the claimed batch id.
- Finalize with failure and verify failure mark receives batch id, status, and message.

## Changelog

- 2026-05-07: Initial reverse-engineered requirements for `Sources/Piston/FountainBridge.swift`.
