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

    public func start(on output: @escaping (Data?, Error?, Bool) -> Void) {
        Task {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }

                while true {
                    if #available(macOS 10.15.4, *) {
                        if let data = try handle.read(upToCount: 8192) {
                            if data.isEmpty {
                                output(nil, nil, true)
                                break
                            } else {
                                output(data, nil, false)
                            }
                        } else {
                            output(nil, nil, true)
                            break
                        }
                    } else {
                        let data = handle.readData(ofLength: 8192)
                        if data.isEmpty {
                            output(nil, nil, true)
                            break
                        } else {
                            output(data, nil, false)
                        }
                    }
                }
            } catch {
                output(nil, error, true)
            }
        }
    }
}
