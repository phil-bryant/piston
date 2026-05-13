import Foundation
import Darwin
import Piston

private struct RunnerConsentProvider: DiagnosticsConsentProvider {
    var diagnosticsUploadEnabled: Bool
}

enum RunnerError: Error {
    case missingEnv(String)
    case invalidEnv(String)
}

@main
struct PistonRunnerMain {
    static func main() async {
        do {
            setbuf(stdout, nil)
            setbuf(stderr, nil)
            try await startUploadService(environment: ProcessInfo.processInfo.environment)
        } catch {
            print("Piston startup failed: \(error)")
            exit(1)
        }
    }

    private static func startUploadService(environment: [String: String]) async throws {
        let resolved = try await resolveUploadTargetEndpoint(environment: environment)

        let uploadEnabled = parseBool(environment["DIAGNOSTICS_UPLOAD_ENABLED"], fallback: true)
        let consent = RunnerConsentProvider(diagnosticsUploadEnabled: uploadEnabled)
        let manifoldIngestKey = nonEmpty(environment["MANIFOLD_INGEST_KEY"])
        let allowsExpensive = parseBool(environment["PISTON_ALLOW_EXPENSIVE_NETWORK"], fallback: true)
        let minUploadInterval = parseDouble(environment["PISTON_MIN_UPLOAD_INTERVAL_SECONDS"], fallback: 30)
        let uploader = PistonUploader(
            endpointURL: resolved.endpointURL,
            configuration: .init(
                maxEventsPerBatch: parseInt(environment["PISTON_MAX_EVENTS_PER_BATCH"], fallback: 200),
                maxBatchBytes: parseInt(environment["PISTON_MAX_BATCH_BYTES"], fallback: 512 * 1024),
                uploadTimeoutSeconds: parseDouble(environment["PISTON_UPLOAD_TIMEOUT_SECONDS"], fallback: 30),
                minimumUploadIntervalSeconds: minUploadInterval,
                allowsCellularOrExpensiveNetwork: allowsExpensive,
                userAgent: environment["PISTON_USER_AGENT"] ?? "PistonRunner/1.0"
            ),
            manifoldIngestKey: manifoldIngestKey,
            consentProvider: consent
        )

        let redacted = redactURL(resolved.endpointURL)
        print(
            "Piston startup: resolved upload target source=\(resolved.source.rawValue) url=\(redacted)"
        )
        if !uploadEnabled {
            print("Piston startup: diagnostics upload disabled by consent provider")
        }
        if manifoldIngestKey == nil {
            print("Piston startup: manifold ingest key not configured (MANIFOLD_INGEST_KEY unset)")
        }

        uploader.start()
        print("Piston startup: uploader started")
        parkForever()
    }

    private static func resolveUploadTargetEndpoint(
        environment: [String: String]
    ) async throws -> UploadTargetResolution {
        let manualUploadTarget = parseURL(environment["MANIFOLD_UPLOAD_URL"])
        let insecureHTTPMode = manualUploadTarget?.scheme?.lowercased() == "http"

        let discoveryURL = try resolveDiscoveryURL(
            environment,
            manualUploadTarget: manualUploadTarget,
            insecureHTTPMode: insecureHTTPMode
        )
        let installID = try resolveInstallID(environment, insecureHTTPMode: insecureHTTPMode)
        let credential = try resolveCredential(environment, insecureHTTPMode: insecureHTTPMode)
        configureFountainRuntime(environment: environment, installID: installID)
        let cachePath = environment["PISTON_UPLOAD_TARGET_CACHE"] ?? ".piston/upload-target-cache.json"
        let cacheURL = URL(fileURLWithPath: cachePath)

        let allowedHosts = parseAllowedHosts(environment["PISTON_ALLOWED_UPLOAD_HOSTS"])
        let discoveryTimeout = parseDouble(environment["PISTON_DISCOVERY_TIMEOUT_SECONDS"], fallback: 8)
        let staleGrace = parseDouble(environment["PISTON_STALE_CACHE_GRACE_SECONDS"], fallback: 0)

        let resolverConfig = UploadTargetResolverConfiguration(
            discoveryURL: discoveryURL,
            cacheFileURL: cacheURL,
            allowedUploadHosts: allowedHosts,
            discoveryTimeoutSeconds: discoveryTimeout,
            staleCacheGracePeriodSeconds: staleGrace
        )
        let resolver = UploadTargetResolver(configuration: resolverConfig)
        return try await resolver.resolve(installID: installID, credential: credential)
    }

    private static func parkForever() {
        let semaphore = DispatchSemaphore(value: 0)
        semaphore.wait()
    }

    private static func requiredString(_ environment: [String: String], key: String) throws -> String {
        guard let value = environment[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.missingEnv(key)
        }
        return value
    }

    private static func requiredURL(_ environment: [String: String], key: String) throws -> URL {
        let raw = try requiredString(environment, key: key)
        guard let parsed = URL(string: raw), parsed.scheme != nil else {
            throw RunnerError.invalidEnv(key)
        }
        return parsed
    }

    private static func requiredDiscoveryURL(_ environment: [String: String]) throws -> URL {
        if let endpoint = environment["VALVE_DISCOVERY_ENDPOINT"],
           !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = URL(string: endpoint), parsed.scheme != nil else {
                throw RunnerError.invalidEnv("VALVE_DISCOVERY_ENDPOINT")
            }
            return parsed
        }
        return try requiredURL(environment, key: "VALVE_DISCOVERY_URL")
    }

    private static func resolveDiscoveryURL(
        _ environment: [String: String],
        manualUploadTarget: URL?,
        insecureHTTPMode: Bool
    ) throws -> URL {
        if insecureHTTPMode, let manualUploadTarget {
            // Resolver short-circuits to MANIFOLD_UPLOAD_URL before using discovery URL.
            return manualUploadTarget
        }
        return try requiredDiscoveryURL(environment)
    }

    private static func resolveInstallID(_ environment: [String: String], insecureHTTPMode: Bool) throws -> String {
        if insecureHTTPMode {
            return nonEmpty(environment["PISTON_INSTALL_ID"]) ?? "dev-http-install"
        }
        return try requiredString(environment, key: "PISTON_INSTALL_ID")
    }

    private static func resolveCredential(_ environment: [String: String], insecureHTTPMode: Bool) throws -> String {
        if insecureHTTPMode {
            return nonEmpty(environment["PISTON_INSTALL_CREDENTIAL"]) ?? "dev-http-credential"
        }
        return try requiredString(environment, key: "PISTON_INSTALL_CREDENTIAL")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseURL(_ raw: String?) -> URL? {
        guard let raw = nonEmpty(raw) else {
            return nil
        }
        return URL(string: raw)
    }

    private static func configureFountainRuntime(environment: [String: String], installID: String) {
        guard let dbPath = nonEmpty(environment["PISTON_FOUNTAIN_DB_PATH"]) else {
            print("Piston startup: fountain runtime not configured (PISTON_FOUNTAIN_DB_PATH unset)")
            return
        }

        let configured = dbPath.withCString { dbPathCString in
            fountainConfigureC(dbPathCString)
        }

        if !configured {
            print("Piston startup: fountain configure failed db=\(dbPath)")
            return
        }

        installID.withCString { installIDCString in
            fountainSetInstallIDC(installIDCString)
        }
        print("Piston startup: fountain configured db=\(dbPath) install_id=\(installID)")
    }

    private static func parseBool(_ rawValue: String?, fallback: Bool) -> Bool {
        guard let lowered = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return fallback
        }
        if lowered == "true" || lowered == "1" || lowered == "yes" {
            return true
        }
        if lowered == "false" || lowered == "0" || lowered == "no" {
            return false
        }
        return fallback
    }

    private static func parseInt(_ rawValue: String?, fallback: Int) -> Int {
        guard let rawValue, let parsed = Int(rawValue), parsed > 0 else {
            return fallback
        }
        return parsed
    }

    private static func parseDouble(_ rawValue: String?, fallback: Double) -> Double {
        guard let rawValue, let parsed = Double(rawValue), parsed > 0 else {
            return fallback
        }
        return parsed
    }

    private static func parseAllowedHosts(_ rawHosts: String?) -> Set<String> {
        guard let rawHosts else {
            return []
        }
        return Set(
            rawHosts
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static func redactURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}
