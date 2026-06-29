import Foundation

struct TrivyVulnerability {
    let severity: String
}

let severities = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN", "critical", "high", "Medium", "Low", "Critical", "High"]
var vulns = [TrivyVulnerability]()
for _ in 0..<100_000 {
    vulns.append(TrivyVulnerability(severity: severities.randomElement()!))
}

let start1 = CFAbsoluteTimeGetCurrent()
for _ in 0..<100 {
    let critical = vulns.filter { $0.severity.uppercased() == "CRITICAL" }.count
    let high = vulns.filter { $0.severity.uppercased() == "HIGH" }.count
    let other = vulns.count - critical - high
}
let end1 = CFAbsoluteTimeGetCurrent()

let start2 = CFAbsoluteTimeGetCurrent()
for _ in 0..<100 {
    var critical = 0
    var high = 0
    for vuln in vulns {
        if vuln.severity.localizedCaseInsensitiveCompare("CRITICAL") == .orderedSame {
            critical += 1
        } else if vuln.severity.localizedCaseInsensitiveCompare("HIGH") == .orderedSame {
            high += 1
        }
    }
    let other = vulns.count - critical - high
}
let end2 = CFAbsoluteTimeGetCurrent()

print("Original: \(end1 - start1) s")
print("Optimized: \(end2 - start2) s")

// --- File Loading Benchmark ---

// Create a 50MB dummy file
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("largefile.txt")
let dummyText = String(repeating: "Hello, World! This is a test file for performance benchmarking.\n", count: 800_000)
try! dummyText.write(to: url, atomically: true, encoding: .utf8)
print("File size: \(try! FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int) bytes")

// Simulate main thread blocking
let start = DispatchTime.now()

do {
    let _ = try String(contentsOf: url, encoding: .utf8)
} catch {
    print("Error: \(error)")
}

let end = DispatchTime.now()
let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
let timeInterval = Double(nanoTime) / 1_000_000_000

print("Baseline synchronous read blocked the thread for: \(timeInterval) seconds")

// Clean up
try! FileManager.default.removeItem(at: url)
