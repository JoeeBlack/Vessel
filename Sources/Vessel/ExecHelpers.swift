import Foundation
import Containerization

public class StringWriter: Containerization.Writer, @unchecked Sendable {
    public var output: String = ""
    public init() {}
    public func write(_ data: Data) throws {
        if let str = String(data: data, encoding: .utf8) {
            output += str
        }
    }
    public func close() throws {}
}

public class FileWriter: Containerization.Writer, @unchecked Sendable {
    private let handle: FileHandle
    public init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
    }
    public func write(_ data: Data) throws {
        if #available(macOS 10.15.4, *) {
            try handle.write(contentsOf: data)
        } else {
            handle.write(data)
        }
    }
    public func close() throws {
        try handle.close()
    }
}

public class FileReader: Containerization.ReaderStream, @unchecked Sendable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() async throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var result = Data()
        while true {
            try Task.checkCancellation()
            if #available(macOS 10.15.4, *) {
                if let data = try handle.read(upToCount: 65536) {
                    if data.isEmpty {
                        break
                    }
                    result.append(data)
                    await Task.yield()
                } else {
                    break
                }
            } else {
                let data = handle.readData(ofLength: 65536)
                if data.isEmpty {
                    break
                }
                result.append(data)
                await Task.yield()
            }
        }
        return result
    }

    public func stream() -> AsyncStream<Data> {
        return AsyncStream { continuation in
            Task {
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }

                    while true {
                        if #available(macOS 10.15.4, *) {
                            if let data = try handle.read(upToCount: 8192) {
                                if data.isEmpty {
                                    continuation.finish()
                                    break
                                } else {
                                    continuation.yield(data)
                                }
                            } else {
                                continuation.finish()
                                break
                            }
                        } else {
                            let data = handle.readData(ofLength: 8192)
                            if data.isEmpty {
                                continuation.finish()
                                break
                            } else {
                                continuation.yield(data)
                            }
                        }
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}

public class IdleStreamReader: Containerization.ReaderStream, @unchecked Sendable {
    public init() {}
    public func stream() -> AsyncStream<Data> {
        return AsyncStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000 * 60 * 60 * 24 * 365)
                } catch {}
                continuation.finish()
            }
        }
    }
}
