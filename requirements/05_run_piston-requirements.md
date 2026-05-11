# Run Piston Requirements

## Scope

Applies to `05_run_piston.sh`.

R001  Statement: Run in strict fail-fast mode from repository root.
Design: Use strict shell mode, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` to script root before startup checks.
Tests:
- Run from a non-repo working directory and verify startup still uses script-root defaults.

R005  Statement: Fail clearly when required runtime tooling is missing.
Design: Require `swift` before startup and print installer guidance to `./01_install_prerequisites.sh` when missing.
Tests:
- Run with `swift` absent from `PATH` and verify explicit missing-command output.

R010  Statement: Validate discovery identity inputs unless explicit upload URL override is provided.
Design: Require `VALVE_DISCOVERY_URL`, `PISTON_INSTALL_ID`, and `PISTON_INSTALL_CREDENTIAL` when `MANIFOLD_UPLOAD_URL` is unset.
Tests:
- Run without override and with each required variable missing; verify explicit failure.
- Run with only `MANIFOLD_UPLOAD_URL` set and verify startup proceeds.

R015  Statement: Provide deterministic cache and startup defaults for discovery fallback behavior.
Design: Default cache location under `.piston/upload-target-cache.json` and set default timeout/stale-grace/min-upload-interval env values when unset.
Tests:
- Run with defaults and verify cache directory and startup hint output are emitted.
- Run with custom `PISTON_CACHE_DIR` and verify resolved cache path uses that directory.

R020  Statement: Start resolver-backed Piston runner.
Design: Execute `swift run PistonRunner` after validation, passing resolved environment through.
Tests:
- Stub `swift` and verify command invocation includes `run PistonRunner`.

## Changelog

- 2026-05-11: Added initial requirements for discovery-driven `05_run_piston.sh` startup flow.
