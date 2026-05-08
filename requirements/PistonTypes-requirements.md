# PistonTypes Requirements

## Scope

Applies to `Sources/Piston/PistonTypes.swift`.

R001  Statement: Expose consent flag.
Design: `DiagnosticsConsentProvider` defines read-only `diagnosticsUploadEnabled` used by upload control flow to gate batch claims.
Tests:
- Provide a stub consent provider returning true and verify uploader attempts batch claims.
- Provide a stub consent provider returning false and verify uploader skips batch claims.

R005  Statement: Keep sendable uploader config.
Design: `PistonConfiguration` includes batch size/count, timeout, minimum interval, expensive-network policy, and user-agent fields and conforms to `Sendable`.
Tests:
- Construct a custom configuration and verify each property round-trips expected value.
- Pass configuration across actor boundaries in uploader loop tests to validate sendable usage.

R010  Statement: Require explicit config init.
Design: `PistonConfiguration.init(...)` requires all operational fields so call sites select intentional values instead of relying on hidden defaults.
Tests:
- Initialize configuration with non-default values and verify each assigned field matches initializer argument.
- Attempt to initialize without required fields and verify compilation fails.

R015  Statement: Provide conservative defaults.
Design: `PistonConfiguration.default` sets `maxEventsPerBatch=200`, `maxBatchBytes=512*1024`, `uploadTimeoutSeconds=30`, `minimumUploadIntervalSeconds=300`, expensive-network allowed, and `userAgent="Piston/1.0"`.
Tests:
- Read `PistonConfiguration.default` and verify every default field value matches expected constants.
- Use default config in uploader initialization and verify startup succeeds without custom overrides.

## Changelog

- 2026-05-07: Initial reverse-engineered requirements for `Sources/Piston/PistonTypes.swift`.
