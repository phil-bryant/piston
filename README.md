# Piston

`Piston` periodically claims pre-built JSON event batches from Fountain and uploads them to an HTTPS ingest endpoint with `URLSession`.

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
