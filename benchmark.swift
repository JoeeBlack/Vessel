import Foundation

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
