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
    }
}

public class StatsParser {
    private var prevCpuTicks: [String: (idle: UInt64, total: UInt64)] = [:]
    
    public init() {}
    
    public func parse(output: String, currentModel: inout StatsModel) {
        let sections = output.components(separatedBy: "---MEM---")
        guard sections.count == 2 else { return }
        
        let statSection = sections[0]
        let memAndLoad = sections[1].components(separatedBy: "---LOAD---")
        guard memAndLoad.count == 2 else { return }
        
        let memSection = memAndLoad[0]
        let loadAndUptime = memAndLoad[1].components(separatedBy: "---UPTIME---")
        guard loadAndUptime.count == 2 else { return }
        
        let loadSection = loadAndUptime[0]
        let uptimeSection = loadAndUptime[1]
        
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
        }
    }
}
