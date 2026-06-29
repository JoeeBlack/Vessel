import Foundation

let url = URL(fileURLWithPath: "/tmp/testfile_bench")
let data = Data(repeating: 0, count: 50 * 1024 * 1024)
try! data.write(to: url)

func readSync() throws -> Data {
    return try Data(contentsOf: url)
}

func readChunkedYield() async throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var result = Data()
    while true {
        if let data = try handle.read(upToCount: 65536) {
            if data.isEmpty { break }
            result.append(data)
            await Task.yield()
        } else {
            break
        }
    }
    return result
}

Task {
    let start = Date()
    _ = try readSync()
    print("Sync read took: \(Date().timeIntervalSince(start))")

    let start2 = Date()
    _ = try await readChunkedYield()
    print("Chunked read with yield took: \(Date().timeIntervalSince(start2))")

    exit(0)
}

RunLoop.main.run()
