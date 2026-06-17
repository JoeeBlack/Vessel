import Foundation

public struct StatsModel: Codable, Equatable, Sendable {
    public var cpuUsages: [Double] // Array of percentages (0.0 to 1.0) for each core
    public var memUsedBytes: UInt64
    public var memTotalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var tasks: Int
    public var runningTasks: Int
    public var loadAverage: [Double] // [1m, 5m, 15m]
    public var uptimeSeconds: Double
    public var timestamp: Date
    public var netRxBytes: UInt64
    public var netTxBytes: UInt64
    public var netRxDelta: UInt64
    public var netTxDelta: UInt64
    
    public init() {
        self.cpuUsages = []
        self.memUsedBytes = 0
        self.memTotalBytes = 0
        self.swapUsedBytes = 0
        self.swapTotalBytes = 0
        self.tasks = 0
        self.runningTasks = 0
        self.loadAverage = [0.0, 0.0, 0.0]
        self.uptimeSeconds = 0
        self.timestamp = Date()
        self.netRxBytes = 0
        self.netTxBytes = 0
        self.netRxDelta = 0
        self.netTxDelta = 0
    }
}

public class StatsParser {
    private var prevCpuTicks: [String: (idle: UInt64, total: UInt64)] = [:]
    private var prevNetRx: UInt64?
    private var prevNetTx: UInt64?
    private var prevTimestamp: Date?
    
    public init() {}
    
    public func parse(output: String, currentModel: inout StatsModel) {
        // ⚡ Bolt Optimization: Use range(of:) and Substring slicing instead of components(separatedBy:)
        // This avoids allocating intermediate Arrays and Strings in high-frequency parsing paths.
        guard let memRange = output.range(of: "---MEM---") else { return }
        let statSection = output[..<memRange.lowerBound]
        let remainingAfterMem = output[memRange.upperBound...]
        
        guard let loadRange = remainingAfterMem.range(of: "---LOAD---") else { return }
        let memSection = remainingAfterMem[..<loadRange.lowerBound]
        let remainingAfterLoad = remainingAfterMem[loadRange.upperBound...]
        
        guard let uptimeRange = remainingAfterLoad.range(of: "---UPTIME---") else { return }
        let loadSection = remainingAfterLoad[..<uptimeRange.lowerBound]
        let remainingAfterUptime = remainingAfterLoad[uptimeRange.upperBound...]

        guard let netRange = remainingAfterUptime.range(of: "---NET---") else { return }
        let uptimeSection = remainingAfterUptime[..<netRange.lowerBound]
        let netSection = remainingAfterUptime[netRange.upperBound...]
        
        // Parse /proc/stat
        var cpuUsages: [Double] = []
        var tasks = 0
        var runningTasks = 0
        
        // ⚡ Bolt Optimization: Use .split instead of .components to avoid allocating new Arrays and Strings
        // .split returns Substrings (views into the original string) and automatically handles empty sequences.
        let statLines = statSection.split(whereSeparator: \.isNewline)
        for line in statLines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard !parts.isEmpty else { continue }
            
            if parts[0].hasPrefix("cpu") && parts[0] != "cpu" {
                // Individual core
                if parts.count >= 8 {
                    let user = UInt64(parts[1]) ?? 0
                    let nice = UInt64(parts[2]) ?? 0
                    let system = UInt64(parts[3]) ?? 0
                    let idlePart = UInt64(parts[4]) ?? 0
                    let iowait = UInt64(parts[5]) ?? 0
                    let irq = UInt64(parts[6]) ?? 0
                    let softirq = UInt64(parts[7]) ?? 0
                    
                    let idle = idlePart + iowait
                    let nonIdle = user + nice + system + irq + softirq
                    let total = idle + nonIdle
                    
                    let cpuName = String(parts[0])
                    if let prev = prevCpuTicks[cpuName] {
                        let diffTotal = Double(total > prev.total ? total - prev.total : 0)
                        let diffIdle = Double(idle > prev.idle ? idle - prev.idle : 0)
                        if diffTotal > 0 {
                            let usage = (diffTotal - diffIdle) / diffTotal
                            cpuUsages.append(usage)
                        } else {
                            cpuUsages.append(0.0)
                        }
                    } else {
                        cpuUsages.append(0.0)
                    }
                    prevCpuTicks[cpuName] = (idle: idle, total: total)
                }
            } else if parts[0] == "processes" {
                tasks = Int(parts[1]) ?? 0
            } else if parts[0] == "procs_running" {
                runningTasks = Int(parts[1]) ?? 0
            }
        }
        
        if !cpuUsages.isEmpty {
            currentModel.cpuUsages = cpuUsages
        }
        currentModel.tasks = tasks
        currentModel.runningTasks = runningTasks
        
        // Parse /proc/meminfo
        let memLines = memSection.split(whereSeparator: \.isNewline)
        for line in memLines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let valueStr = parts[1]
            if let kb = UInt64(valueStr) {
                let bytes = kb * 1024
                switch key {
                case "MemTotal:": currentModel.memTotalBytes = bytes
                case "MemFree:": currentModel.memUsedBytes = currentModel.memTotalBytes - bytes
                case "MemAvailable:": currentModel.memUsedBytes = currentModel.memTotalBytes - bytes
                case "SwapTotal:": currentModel.swapTotalBytes = bytes
                case "SwapFree:": currentModel.swapUsedBytes = currentModel.swapTotalBytes - bytes
                default: break
                }
            }
        }
        
        // Parse /proc/loadavg
        let loadParts = loadSection.split(whereSeparator: \.isWhitespace)
        if loadParts.count >= 3 {
            currentModel.loadAverage = [
                Double(loadParts[0]) ?? 0.0,
                Double(loadParts[1]) ?? 0.0,
                Double(loadParts[2]) ?? 0.0
            ]
        }
        
        // Parse /proc/uptime
        let uptimeParts = uptimeSection.split(whereSeparator: \.isWhitespace)
        if let uptime = uptimeParts.first, let uptimeDouble = Double(uptime) {
            currentModel.uptimeSeconds = uptimeDouble
            currentModel.timestamp = Date()
        }

        // Parse /proc/net/dev
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        let netLines = netSection.split(whereSeparator: \.isNewline)
        for line in netLines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            // Example line: eth0: 1234 123 12 1 1 1 1 1 4321 321 32 3 3 3 3 3
            if parts.count >= 10, let interfaceName = parts.first, interfaceName.contains(":") {
                let name = String(interfaceName).replacingOccurrences(of: ":", with: "")
                if name != "lo" {
                    if let rxBytes = UInt64(parts[1]), let txBytes = UInt64(parts[9]) {
                        rx += rxBytes
                        tx += txBytes
                    }
                }
            }
        }
        currentModel.netRxBytes = rx
        currentModel.netTxBytes = tx

        let now = Date()
        if let prx = prevNetRx, let ptx = prevNetTx, let pt = prevTimestamp {
            let timeDiff = now.timeIntervalSince(pt)
            if timeDiff > 0 {
                currentModel.netRxDelta = UInt64(Double(rx > prx ? rx - prx : 0) / timeDiff)
                currentModel.netTxDelta = UInt64(Double(tx > ptx ? tx - ptx : 0) / timeDiff)
            }
        }

        prevNetRx = rx
        prevNetTx = tx
        prevTimestamp = now
    }
}
