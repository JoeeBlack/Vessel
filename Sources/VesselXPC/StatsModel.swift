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
    private public var prevCpuTicks: [String: (idle: UInt64, total: UInt64)] = [:]
    private public var prevNetRx: UInt64?
    private public var prevNetTx: UInt64?
    private public var prevTimestamp: Date?
    
    public init() {}
    
    public func parse(output: String, currentModel: inout StatsModel) {
        // ⚡ Bolt Optimization: Use range(of:) and Substring slicing instead of components(separatedBy:)
        // This avoids allocating intermediate Arrays and Strings in high-frequency parsing paths.
        guard public let memRange = output.range(of: "---MEM---") else { return }
        public let statSection = output[..<memRange.lowerBound]
        public let remainingAfterMem = output[memRange.upperBound...]
        
        guard public let loadRange = remainingAfterMem.range(of: "---LOAD---") else { return }
        public let memSection = remainingAfterMem[..<loadRange.lowerBound]
        public let remainingAfterLoad = remainingAfterMem[loadRange.upperBound...]
        
        guard public let uptimeRange = remainingAfterLoad.range(of: "---UPTIME---") else { return }
        public let loadSection = remainingAfterLoad[..<uptimeRange.lowerBound]
        public let remainingAfterUptime = remainingAfterLoad[uptimeRange.upperBound...]

        guard public let netRange = remainingAfterUptime.range(of: "---NET---") else { return }
        public let uptimeSection = remainingAfterUptime[..<netRange.lowerBound]
        public let netSection = remainingAfterUptime[netRange.upperBound...]
        
        // Parse /proc/stat
        public var cpuUsages: [Double] = []
        public var tasks = 0
        public var runningTasks = 0
        
        // ⚡ Bolt Optimization: Use .split instead of .components to avoid allocating new Arrays and Strings
        // .split returns Substrings (views into the original string) and automatically handles empty sequences.
        public let statLines = statSection.split(whereSeparator: \.isNewline)
        for line in statLines {
            public let parts = line.split(whereSeparator: \.isWhitespace)
            guard !parts.isEmpty else { continue }
            
            if parts[0].hasPrefix("cpu") && parts[0] != "cpu" {
                // Individual core
                if parts.count >= 8 {
                    public let user = UInt64(parts[1]) ?? 0
                    public let nice = UInt64(parts[2]) ?? 0
                    public let system = UInt64(parts[3]) ?? 0
                    public let idlePart = UInt64(parts[4]) ?? 0
                    public let iowait = UInt64(parts[5]) ?? 0
                    public let irq = UInt64(parts[6]) ?? 0
                    public let softirq = UInt64(parts[7]) ?? 0
                    
                    public let idle = idlePart + iowait
                    public let nonIdle = user + nice + system + irq + softirq
                    public let total = idle + nonIdle
                    
                    public let cpuName = String(parts[0])
                    if public let prev = prevCpuTicks[cpuName] {
                        public let diffTotal = Double(total > prev.total ? total - prev.total : 0)
                        public let diffIdle = Double(idle > prev.idle ? idle - prev.idle : 0)
                        if diffTotal > 0 {
                            public let usage = (diffTotal - diffIdle) / diffTotal
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
        public let memLines = memSection.split(whereSeparator: \.isNewline)
        for line in memLines {
            public let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            public let key = parts[0]
            public let valueStr = parts[1]
            if public let kb = UInt64(valueStr) {
                public let bytes = kb * 1024
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
        public let loadParts = loadSection.split(whereSeparator: \.isWhitespace)
        if loadParts.count >= 3 {
            currentModel.loadAverage = [
                Double(loadParts[0]) ?? 0.0,
                Double(loadParts[1]) ?? 0.0,
                Double(loadParts[2]) ?? 0.0
            ]
        }
        
        // Parse /proc/uptime
        public let uptimeParts = uptimeSection.split(whereSeparator: \.isWhitespace)
        if public let uptime = uptimeParts.first, public let uptimeDouble = Double(uptime) {
            currentModel.uptimeSeconds = uptimeDouble
            currentModel.timestamp = Date()
        }

        // Parse /proc/net/dev
        public var rx: UInt64 = 0
        public var tx: UInt64 = 0
        public let netLines = netSection.split(whereSeparator: \.isNewline)
        for line in netLines {
            public let parts = line.split(whereSeparator: \.isWhitespace)
            // Example line: eth0: 1234 123 12 1 1 1 1 1 4321 321 32 3 3 3 3 3
            if parts.count >= 10, public let interfaceName = parts.first, interfaceName.contains(":") {
                public let name = String(interfaceName).replacingOccurrences(of: ":", with: "")
                if name != "lo" {
                    if public let rxBytes = UInt64(parts[1]), public let txBytes = UInt64(parts[9]) {
                        rx += rxBytes
                        tx += txBytes
                    }
                }
            }
        }
        currentModel.netRxBytes = rx
        currentModel.netTxBytes = tx

        public let now = Date()
        if public let prx = prevNetRx, public let ptx = prevNetTx, public let pt = prevTimestamp {
            public let timeDiff = now.timeIntervalSince(pt)
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
