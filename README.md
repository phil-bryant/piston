# Piston

`Piston` periodically claims pre-built JSON event batches from Fountain and uploads them to an HTTPS ingest endpoint with `URLSession`.

## Discovery-driven startup (Option 2)

`05_run_piston.sh` starts `PistonRunner`, which resolves the Manifold upload target from Valve at startup and falls back to a cached target when discovery is temporarily unavailable.

Required environment:

- `VALVE_DISCOVERY_URL`
- `PISTON_INSTALL_ID`
- `PISTON_INSTALL_CREDENTIAL`

Optional behavior controls:

- `PISTON_UPLOAD_TARGET_CACHE` (default: `./.piston/upload-target-cache.json`)
- `PISTON_DISCOVERY_TIMEOUT_SECONDS` (default: `8`)
- `PISTON_STALE_CACHE_GRACE_SECONDS` (default: `300`)
- `PISTON_ALLOWED_UPLOAD_HOSTS` (comma-separated allowlist)
- `MANIFOLD_UPLOAD_URL` (dev/local explicit override)

Example:

```bash
VALVE_DISCOVERY_URL="https://valve.example.com/v1/piston/upload-target" \
PISTON_INSTALL_ID="install-123" \
PISTON_INSTALL_CREDENTIAL="provisioned-credential" \
./05_run_piston.sh
```

Startup flow:

```text
┌────────────────┐
│ runPistonStart │
└───────┬────────┘
        │
        ▼
┌────────────────────────────┐
│ ReadInstallIdAndCredential │
└─────────────┬──────────────┘
              │
              ▼
┌────────────────────────────┐
│ CallValveDiscoveryEndpoint │
└─────────────┬──────────────┘
              │
      ┌───────┴─────────────────────────────┐
      │                                     │
      │ 200 valid                           │ error / timeout
      ▼                                     ▼
┌───────────────────┐               ┌──────────────────┐
│ ValidateUploadUrl │               │ ReadCachedTarget │
└─────────┬─────────┘               └────────┬─────────┘
          │                                  │
          ▼                                  ▼
┌─────────────────────┐              ┌───────────────┐
│ PersistCacheWithTTL │              │ CacheUsable ? │
└──────────┬──────────┘              └───────┬───────┘
           │                                 │
           │                         ┌───────┴─────────────┐
           │                         │                     │
           │                         │ yes                 │ no
           │                         ▼                     ▼
           │              ┌───────────────────┐   ┌─────────────────────────┐
           └─────────────▶│ ConstructAndStart │   │ ExitWithActionableError │
                          │ PistonUploader    │   └─────────────────────────┘
                          └───────────────────┘
```

## App startup integration example

```swift
import Foundation
import Piston

struct AppConsentProvider: DiagnosticsConsentProvider {
    var diagnosticsUploadEnabled: Bool {
        UserDefaults.standard.bool(forKey: "diagnostics_upload_enabled")
    }
}

@main
struct MyMacOSApp {
    static func main() {
        // Fountain initialization happens in your host app / Fountain module.
        // Example:
        // FountainConfigureDatabasePath("/Users/me/Library/Application Support/MyApp/diagnostics.sqlite3")
        // FountainSetApplicationMetadata("com.example.myapp", "1.2.3", "1234")

        let uploader = PistonUploader(
            endpointURL: URL(string: "https://ingest.example.com/v1/diagnostics")!,
            configuration: .init(
                maxEventsPerBatch: 200,
                maxBatchBytes: 512 * 1024,
                uploadTimeoutSeconds: 30,
                minimumUploadIntervalSeconds: 300,
                allowsCellularOrExpensiveNetwork: true,
                userAgent: "MyApp/1.2.3 (macOS)"
            ),
            consentProvider: AppConsentProvider()
        )

        uploader.start()
    }
}
```

## Architecture Diagram

```text
BACKEND
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌────────────────────────────┐        ┌──────────────────────────────────┐  │
│  │           Valve            │        │             Manifold             │  │
│  │                            │        │                                  │  │
│  │ - runs after user sign-in  │        │ - verifies signature / credential│  │
│  │ - verifies Account A access│        │ - derives tenant_id + install_id │  │
│  │ - provisions per-tenant /  │        │   from credential                │  │
│  │   per-install credential   │        │ - stores tenant-scoped events    │  │
│  │ - rotates / revokes creds  │        │ - rejects tenant mismatches      │  │
│  └─────────────┬──────────────┘        │                                  │  │
│                │                       │  ┌───────────────────────┐       │  │
│                │                       │  │ Ingest Endpoint       │       │  │
│                │                 ┌─────┼─►│ POST /v1/events/batch │       │  │
│                │                 │     │  └───────────────────────┘       │  │
│                │                 │     │                                  │  │
│                │                 │     └──────────────────────┬───────────┘  │
│                │                 │                            │              │
└────────────────┼─────────────────┼────────────────────────────┼──────────────┘
                 │                 │                            │
                 │                 │                            │ tenant-scoped
                 │                 │                            │ events
                 │ credential      │             NOC/SOC        ▼
                 │ for Account A   │             ┌──────────────────────────┐
                 │ + Install 123   │             │          Vortex          │
                 │                 │             │                          │
                 │                 │             │ - downstream all-in-one  │
                 │                 │             │ - storage / analytics    │
                 │                 │             │ - dashboards / alerts    │
                 │                 │             │ - incident review        │
    credential   │                 │             │ - strict tenant_id reads │
    provisioned  │                 │             └──────────────────────────┘
   after sign-in │                 │
                 │                 │ HTTPS + signed batch
                 │                 │ credential proves Account A + Install 123
CUSTOMER DEVICE  ▼                 │
┌──────────────────────────────────┼─────────┐
│                                  │         │
│  ┌────────────────────┐   ┌─────────────┐  │
│  │      Fountain      │   │   Piston    │  │
│  │                    │   │             │  │
│  │ - C++ event logger │   │ - Swift     │  │
│  │ - SQLite queue     │   │   uploader  │  │
│  │ - tags events with │   │ - stores    │  │
│  │   tenant_scope     │   │   credential│  │
│  └─────────┬──────────┘   │ - claims    │  │
│            │              │   matching  │  │
│            │ Account A    │   scope     │  │
│            │ events       │ - signs     │  │
│            └─────────────►│   uploads   │  │
│                           └─────────────┘  │
│                                            │
└────────────────────────────────────────────┘
```
