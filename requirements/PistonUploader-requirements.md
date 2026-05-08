# PistonUploader Requirements

## Scope

Applies to `Sources/Piston/PistonUploader.swift`.

R001  Statement: Abstract upload transport.
Design: `PistonHTTPSession` defines async `data(for:)` contract and `URLSession` conforms to it, enabling production networking and deterministic test doubles.
Tests:
- Inject a mock session and verify uploader uses mock transport rather than real network.
- Verify `URLSession` can be passed where `PistonHTTPSession` is expected.

R005  Statement: Expose uploader controls.
Design: `PistonUploader` owns one `PistonUploadLoop` actor and exposes `start()`, `stop()`, and async `flushNow()` that delegates to actor flush with bounded batch count.
Tests:
- Initialize uploader and verify `start()`/`stop()` can be called repeatedly without crash.
- Call `flushNow()` and verify upload loop executes immediate attempt path.

R010  Statement: Configure URLSession from config.
Design: Public initializer uses ephemeral `URLSessionConfiguration`, applies request/resource timeout and expensive/cellular access flags from `PistonConfiguration`, then creates session for the actor.
Tests:
- Initialize uploader with custom timeout and verify outgoing request timeout uses configured seconds.
- Initialize with expensive-network disabled and verify session configuration reflects the policy.

R015  Statement: Allow dependency injection.
Design: Internal initializer accepts `PistonHTTPSession` and `FountainUploadBatchBridging`, wiring them into `PistonUploadLoop` without constructing production dependencies.
Tests:
- Initialize uploader with mock bridge/session and verify flush behavior follows mocks.
- Verify production initializer and test initializer both produce functional upload loops.

R020  Statement: Isolate loop in actor.
Design: `PistonUploadLoop` stores endpoint/config/consent/session/bridge plus periodic task and flush coordination state under actor isolation.
Tests:
- Trigger concurrent `flushNow` calls and verify actor preserves single-flight behavior.
- Start and stop periodic loop around concurrent calls and verify no data races or crashes.

R025  Statement: Start one periodic task.
Design: `start()` no-ops when already started; otherwise spawns a cancellable task that sleeps using `max(minimumUploadIntervalSeconds, 1)` and flushes one batch each tick.
Tests:
- Call `start()` twice and verify only one periodic task is active.
- Configure short interval in test and verify periodic task triggers flush attempts.

R030  Statement: Stop periodic task cleanly.
Design: `stop()` cancels existing periodic task and sets stored task reference to nil.
Tests:
- Call `start()` then `stop()` and verify no further periodic upload attempts are triggered.
- Call `stop()` when not started and verify no crash/no-op behavior.

R035  Statement: Keep flush single-flight.
Design: When a flush is already running, additional calls await continuation completion; active flush resumes all waiters in defer after finishing.
Tests:
- Run two concurrent flushes with blocking network and verify max one in-flight request.
- Verify waiter flush returns after active flush completion.

R040  Statement: Cap flush drain count.
Design: `flushNow(maxBatches:)` returns immediately for non-positive values and caps work to `min(maxBatches, 5)`.
Tests:
- Call with `maxBatches <= 0` and verify no upload attempt occurs.
- Queue more than five batches and verify single flush drains no more than five.

R045  Statement: Gate claims by consent.
Design: `uploadOneBatch()` checks `consentProvider.diagnosticsUploadEnabled` before calling bridge create; when disabled it returns without claiming.
Tests:
- With consent disabled, verify bridge create is never called.
- With consent enabled, verify bridge create is attempted.

R050  Statement: Stop on nil batch.
Design: `uploadOneBatch()` returns false when bridge returns nil so flush loop stops gracefully without errors.
Tests:
- Return nil batch from mock bridge and verify flush exits cleanly.
- Verify no network request is made when batch is nil.

R055  Statement: Fail nil payload safely.
Design: When claimed batch payload is nil, uploader finalizes failure with status `0` and `"Invalid payload"` error text and stops current flush.
Tests:
- Return batch with nil payload and verify failure finalization status/message.
- Verify uploader does not attempt HTTP request for nil payload batches.

R060  Statement: Post JSON payload bytes.
Design: `post(body:)` builds `URLRequest` for endpoint, sets `POST`, assigns body bytes directly, applies timeout, and sets `Content-Type`, `Accept`, and `User-Agent`.
Tests:
- Capture request in mock session and verify method, headers, timeout, and body bytes.
- Verify `User-Agent` header equals configured value.

R065  Statement: Require HTTP responses.
Design: `post(body:)` awaits session data call, casts response to `HTTPURLResponse`, returns status code, and throws `URLError(.badServerResponse)` when cast fails.
Tests:
- Return HTTP response and verify status code is propagated.
- Return non-HTTP response and verify badServerResponse error is thrown.

R070  Statement: Mark 2xx success.
Design: `uploadOneBatch()` finalizes `.succeeded` for 2xx status and returns true so caller may process next batch.
Tests:
- Return 204 response and verify batch success finalization.
- Queue multiple successful batches and verify loop continues to next batch.

R075  Statement: Mark non-2xx failures.
Design: `uploadOneBatch()` finalizes `.failed(httpStatus:statusCode,errorMessage:"HTTP <status>")` for non-2xx responses and returns false to stop current flush loop.
Tests:
- Return 400/422/429/5xx responses and verify failure finalization carries corresponding status.
- Verify flush stops after first non-2xx failure.

R080  Statement: Mark network failures status-zero.
Design: `uploadOneBatch()` catches thrown errors, finalizes failure with `httpStatus=0` and stringified error message, and returns false.
Tests:
- Make mock session throw network error and verify failure status is zero.
- Verify failure error message includes thrown error description.

## Changelog

- 2026-05-07: Initial reverse-engineered requirements for `Sources/Piston/PistonUploader.swift`.
