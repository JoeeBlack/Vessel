import Foundation
@testable import Vessel
import Containerization

actor TestApp {
    let daemon = ContainerDaemon()
    
    func run() async throws {
        let active = try await daemon.fetchActiveContainers()
        guard let first = active.first else {
            print("No active containers")
            exit(1)
        }
        
        print("Using container: \(first.name) (\(first.id))")
        
        print("Starting container...")
        try await daemon.start(containerId: first.id)
        
        let (stream, cont) = AsyncStream<Data>.makeStream()
        
        let writer = ShellWriter { str in
            print("STDOUT: \(str)")
        }
        
        let process = try await daemon.execShell(containerId: first.id, stdin: ShellReader(stream: stream), stdout: writer)
        print("Shell started")
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("Sending 'ls'")
        cont.yield("ls\n".data(using: .utf8)!)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("Sending 'pwd'")
        cont.yield("pwd\n".data(using: .utf8)!)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }
}

let app = TestApp()
try await app.run()
