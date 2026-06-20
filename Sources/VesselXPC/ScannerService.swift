import Foundation

// MARK: - Models

public struct TrivyVulnerability: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(vulnerabilityID)-\(pkgName)" }
    public let vulnerabilityID: String
    public let pkgName: String
    public let installedVersion: String?
    public let fixedVersion: String?
    public let title: String?
    public let description: String?
    public let severity: String
    public let primaryURL: String?

    enum CodingKeys: String, CodingKey {
        case vulnerabilityID = "VulnerabilityID"
        case pkgName = "PkgName"
        case installedVersion = "InstalledVersion"
        case fixedVersion = "FixedVersion"
        case title = "Title"
        case description = "Description"
        case severity = "Severity"
        case primaryURL = "PrimaryURL"
    }
}

public struct TrivyResult: Codable, Sendable {
    public let target: String
    public let `class`: String
    public let type: String?
    public let vulnerabilities: [TrivyVulnerability]?

    enum CodingKeys: String, CodingKey {
        case target = "Target"
        case `class` = "Class"
        case type = "Type"
        case vulnerabilities = "Vulnerabilities"
    }
}

public struct TrivyReport: Codable, Sendable {
    public let schemaVersion: Int
    public let createdAt: String
    public let artifactName: String
    public let artifactType: String
    public let results: [TrivyResult]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "SchemaVersion"
        case createdAt = "CreatedAt"
        case artifactName = "ArtifactName"
        case artifactType = "ArtifactType"
        case results = "Results"
    }
}

// MARK: - Scanner Service

public actor ScannerService {
    public init() {}

    private func findTrivyExecutable() -> URL? {
        let paths = [
            "/opt/homebrew/bin/trivy",
            "/usr/local/bin/trivy",
            "/usr/bin/trivy"
        ]

        let fm = FileManager.default
        for path in paths {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    public enum ScannerError: Error, LocalizedError {
        case executableNotFound
        case executionFailed(String)
        case decodingFailed(Error)
        case outputEmpty

        public var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Trivy executable not found. Please ensure it is installed in /opt/homebrew/bin, /usr/local/bin, or /usr/bin."
            case .executionFailed(let msg):
                return "Trivy execution failed: \(msg)"
            case .decodingFailed(let err):
                return "Failed to decode Trivy JSON output: \(err.localizedDescription)"
            case .outputEmpty:
                return "Trivy returned empty output."
            }
        }
    }

    public func scanImage(reference: String) async throws -> [TrivyVulnerability] {
        guard let trivyURL = findTrivyExecutable() else {
            throw ScannerError.executableNotFound
        }

        let process = Process()
        process.executableURL = trivyURL
        process.arguments = ["image", "--format", "json", "--quiet", reference]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class ThreadSafeData: @unchecked Sendable {
            private var data = Data()
            private let lock = NSLock()
            func append(_ newData: Data) {
                lock.lock()
                data.append(newData)
                lock.unlock()
            }
            func get() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let outData = ThreadSafeData()
        let errData = ThreadSafeData()

        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                outData.append(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                errData.append(data)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ScannerError.executionFailed(error.localizedDescription))
                return
            }

            process.terminationHandler = { p in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let finalOutData = outData.get()
                let finalErrData = errData.get()
                
                guard p.terminationStatus == 0 else {
                    let errString = String(data: finalErrData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ScannerError.executionFailed("Exit code \(p.terminationStatus). \(errString)"))
                    return
                }

                if finalOutData.isEmpty {
                    continuation.resume(throwing: ScannerError.outputEmpty)
                    return
                }

                // Parse JSON in background
                Task.detached {
                    do {
                        let decoder = JSONDecoder()
                        let report = try decoder.decode(TrivyReport.self, from: finalOutData)

                        var allVulnerabilities = [TrivyVulnerability]()
                        if let results = report.results {
                            for result in results {
                                if let vulns = result.vulnerabilities {
                                    allVulnerabilities.append(contentsOf: vulns)
                                }
                            }
                        }
                        continuation.resume(returning: allVulnerabilities)
                    } catch {
                        continuation.resume(throwing: ScannerError.decodingFailed(error))
                    }
                }
            }
        }
    }
}
