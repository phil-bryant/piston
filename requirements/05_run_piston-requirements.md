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

R010  Statement: Validate discovery identity inputs based on startup protocol mode.
Design: Print `--help` usage text when no CLI args are provided; in lockdown mode require `--install-id` argument for startup and require install credential; in relaxed dev mode (`MANIFOLD_UPLOAD_URL` uses `http://` or discovery endpoint itself uses `http://`) allow startup without install identity and use placeholder values; when relaxed mode is entered from an `http://` discovery endpoint and `MANIFOLD_UPLOAD_URL` is unset, default it to `http://localhost:8080/v1/events/batch` (override via `PISTON_DEV_MANIFOLD_UPLOAD_URL`); require `VALVE_DISCOVERY_ENDPOINT` (or fallback `VALVE_DISCOVERY_URL`) and install credential when discovery mode is active; if discovery endpoint is unset, attempt resolving it from `1psa` item `VALVE_DISCOVERY_ENDPOINT` (`protocol`/`host`/`port`/`path` fields); if install credential is unset, attempt resolving from `1psa` item `PISTON_INSTALL_CREDENTIAL` field `password` and then item named after `--install-id` field `password`.
Tests:
- Run with no args and verify usage text is printed.
- Run with `--help` and verify usage text is printed and startup exits successfully.
- Run with `MANIFOLD_UPLOAD_URL=http://...` and no install identity; verify startup proceeds.
- Run with `VALVE_DISCOVERY_ENDPOINT=http://...` and no install identity; verify startup proceeds and uses local dev upload default.
- Run with `MANIFOLD_UPLOAD_URL=https://...` and no install identity; verify explicit lockdown-mode failure.
- Run without `--install-id` and verify explicit missing-argument failure.
- Run without override and with each required variable missing; verify explicit failure.
- Run with no credential in CLI/env and verify 1psa fallback can provide install credential.
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

R025  Statement: Surface detached runner lifecycle to operators.
Design: Launch `PistonRunner` detached when startup remains healthy and print `runner_detached_pid=<pid>` and `runner_log=<path>` so operators can inspect or stop it and follow runtime poll logs; if runner exits immediately, propagate failure instead of claiming successful detach.
Tests:
- Stub long-running `swift` invocation and verify startup output contains `runner_detached_pid=` and `runner_log=`, and detached PID remains alive immediately after startup.

## Changelog

- 2026-05-11: Added detached runner PID output and immediate-launch failure guard for operator visibility.
- 2026-05-11: Added install-credential CLI/env/1psa resolution and explicit hint when a credential token is passed as `--install-id`.
- 2026-05-11: Added required `--install-id` CLI argument and help-text behavior for no-arg startup.
- 2026-05-11: Added initial requirements for discovery-driven `05_run_piston.sh` startup flow.
