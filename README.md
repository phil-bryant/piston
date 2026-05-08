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
