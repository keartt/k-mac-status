import AppKit
import IOKit

func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
}
func percent(_ value: Double) -> String { "\(Int((min(1, max(0, value)) * 100).rounded()))%" }
func registry(_ className: String) -> [String: Any] {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
    guard service != 0 else { return [:] }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties else { return [:] }
    return properties.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:]
}
struct AppUsage {
    let name: String
    let url: URL?
    var memory: UInt64
    let isSelf: Bool
}
struct DetailReading {
    var memory = read_memory()
    var cpu: Double?
    var gpu: Double?
    var temperature: Double?
    var thermal = ""
    var disk = "조회 불가"
    var diskFraction: Double?
    var network = "샘플링 중…"
    var download: Double?
    var upload: Double?
    var apps: [AppUsage] = []
}
final class Collector {
    private var previousCPU: CPUReading?
    private var previousNetwork: NetworkReading?
    private var previousTime: TimeInterval?
    private(set) var collections = 0
    func sample() -> DetailReading {
        collections += 1
        var result = DetailReading()
        let cpu = read_cpu()
        if cpu.valid != 0, let old = previousCPU, old.valid != 0 {
            let now = [cpu.user, cpu.system, cpu.idle, cpu.nice]
            let before = [old.user, old.system, old.idle, old.nice]
            let deltas = zip(now, before).map { Double(UInt32(truncatingIfNeeded: $0) &- UInt32(truncatingIfNeeded: $1)) }
            let total = deltas.reduce(0, +)
            if total > 0 { result.cpu = (total - deltas[2]) / total }
        }
        previousCPU = cpu
        let gpu = registry("AGXAccelerator")["PerformanceStatistics"] as? [String: Any]
        if let value = gpu?["Device Utilization %"] as? NSNumber, (0...100).contains(value.doubleValue) {
            result.gpu = value.doubleValue / 100
        }
        let battery = registry("AppleSmartBattery")
        if let value = battery["Temperature"] as? NSNumber {
            let celsius = value.doubleValue / 10 - 273.15
            if (-20...100).contains(celsius) { result.temperature = celsius }
        }
        let states = ["정상", "주의", "높음", "위험"]
        let state = ProcessInfo.processInfo.thermalState.rawValue
        result.thermal = states.indices.contains(state) ? states[state] : "조회 불가"
        if let volume = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = volume.volumeTotalCapacity, let free = volume.volumeAvailableCapacityForImportantUsage, total > 0 {
            result.disk = "\(bytes(UInt64(max(0, free)))) 여유 / \(bytes(UInt64(total)))"
            result.diskFraction = 1 - min(1, Double(free) / Double(total))
        }
        var network = read_network()
        let time = ProcessInfo.processInfo.systemUptime
        let name = withUnsafePointer(to: &network.name) { $0.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) } }
        if network.valid != 0 {
            result.network = "\(name) · 샘플링 중…"
            if var old = previousNetwork, old.valid != 0, let oldTime = previousTime, time > oldTime {
                let oldName = withUnsafePointer(to: &old.name) { $0.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) } }
                if name == oldName, network.received >= old.received, network.sent >= old.sent {
                    result.download = Double(network.received - old.received) / (time - oldTime)
                    result.upload = Double(network.sent - old.sent) / (time - oldTime)
                    result.network = "\(name)   ↓ \(bytes(UInt64(result.download!)))/s   ↑ \(bytes(UInt64(result.upload!)))/s"
                }
            }
        } else { result.network = "연결 없음 / 조회 불가" }
        previousNetwork = network; previousTime = time
        result.apps = appUsage()
        return result
    }
    func appUsage() -> [AppUsage] {
        var processes = [ProcessReading](repeating: ProcessReading(), count: Int(process_capacity()))
        let count = read_processes(&processes, Int32(processes.count))
        var groups: [String: AppUsage] = [:]
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if count > 0 {
            for index in 0..<Int(count) {
                var process = processes[index]
                guard process.pid != ownPID else { continue }
                let path = withUnsafePointer(to: &process.path) { $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) } }
                // Only an enclosing .app establishes ownership; do not guess from a process name.
                guard let range = path.range(of: ".app/", options: .caseInsensitive) else { continue }
                let root = String(path[..<range.lowerBound]) + ".app"
                if groups[root] != nil { groups[root]!.memory += process.bytes }
                else {
                    let url = URL(fileURLWithPath: root)
                    let name = FileManager.default.displayName(atPath: root).replacingOccurrences(of: ".app", with: "")
                    groups[root] = AppUsage(name: name, url: url, memory: process.bytes, isSelf: false)
                }
            }
        }
        let runningApps = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { $0.bundleURL?.path })
        var result = Array(groups.filter { runningApps.contains($0.key) }.values
            .sorted { $0.memory > $1.memory }.prefix(20))
        result.append(AppUsage(name: "k-mac-status · 이 앱", url: Bundle.main.bundleURL, memory: own_footprint(), isSelf: true))
        return result
    }
}
