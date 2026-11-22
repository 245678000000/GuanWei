import AppKit
import CoreWLAN
import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - sysctl

func sysctlInt(_ name: String) -> Int? {
    var buf = [UInt8](repeating: 0, count: 8)
    var size = 8
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    if size == 4 { return Int(buf.withUnsafeBytes { $0.load(as: Int32.self) }) }
    return Int(buf.withUnsafeBytes { $0.load(as: Int64.self) })
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

// MARK: - CPU

struct CPUSnapshot {
    var user: Double = 0
    var system: Double = 0
    var cores: [Double] = []
    var total: Double { user + system }
}

final class CPUSampler {
    private var prev: [[UInt32]] = []

    func sample() -> CPUSnapshot {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSnapshot() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        var cur: [[UInt32]] = []
        for i in 0..<Int(count) {
            cur.append((0..<states).map { UInt32(bitPattern: info[i * states + $0]) })
        }
        defer { prev = cur }
        guard prev.count == cur.count else {
            return CPUSnapshot(cores: Array(repeating: 0, count: cur.count))
        }
        var tu = 0.0, ts = 0.0, tt = 0.0
        var cores: [Double] = []
        for i in 0..<cur.count {
            let d = (0..<states).map { Double(cur[i][$0] &- prev[i][$0]) }
            let user = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_NICE)]
            let sys = d[Int(CPU_STATE_SYSTEM)]
            let total = d.reduce(0, +)
            tu += user; ts += sys; tt += total
            cores.append(total > 0 ? (user + sys) / total : 0)
        }
        return CPUSnapshot(user: tt > 0 ? tu / tt : 0, system: tt > 0 ? ts / tt : 0, cores: cores)
    }
}

// MARK: - Memory

struct MemorySnapshot {
    var total: Double = 1
    var app: Double = 0
    var wired: Double = 0
    var compressed: Double = 0
    var pressure: Double = 0
    var swapUsed: Double = 0
    var used: Double { app + wired + compressed }
    var available: Double { max(0, total - used) }
    var usage: Double { min(1, used / total) }
}

func sampleMemory() -> MemorySnapshot {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    var m = MemorySnapshot()
    m.total = Double(ProcessInfo.processInfo.physicalMemory)
    guard kr == KERN_SUCCESS else { return m }
    var ps: vm_size_t = 0
    host_page_size(mach_host_self(), &ps)
    let page = Double(ps)
    m.app = Double(stats.internal_page_count &- stats.purgeable_count) * page
    m.wired = Double(stats.wire_count) * page
    m.compressed = Double(stats.compressor_page_count) * page
    if let level = sysctlInt("kern.memorystatus_level") {
        m.pressure = max(0, min(1, 1 - Double(level) / 100))
    }
    var xsw = xsw_usage()
    var sz = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &xsw, &sz, nil, 0) == 0 {
        m.swapUsed = Double(xsw.xsu_used)
    }
    return m
}

// MARK: - Disk

struct DiskSnapshot {
    var name: String = "Macintosh HD"
    var total: Double = 1
    var available: Double = 0
    var readRate: Double = 0
    var writeRate: Double = 0
    var usage: Double { total > 0 ? 1 - available / total : 0 }
}

final class DiskSampler {
    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: TimeInterval = 0
    private var capacity: (String, Double, Double)?
    private var capacityTick = 0

    func sample() -> DiskSnapshot {
        var d = DiskSnapshot()
        if capacity == nil || capacityTick % 30 == 0 {
            let url = URL(fileURLWithPath: "/")
            if let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey]) {
                capacity = (v.volumeName ?? "Macintosh HD",
                            Double(v.volumeTotalCapacity ?? 0),
                            Double(v.volumeAvailableCapacityForImportantUsage ?? 0))
            }
        }
        capacityTick += 1
        if let capacity { d.name = capacity.0; d.total = capacity.1; d.available = capacity.2 }

        var read: UInt64 = 0, write: UInt64 = 0
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS {
            var s = IOIteratorNext(iter)
            while s != 0 {
                if let stats = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                    write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                }
                IOObjectRelease(s)
                s = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if prevTime > 0, now > prevTime {
            let dt = now - prevTime
            d.readRate = read >= prevRead ? Double(read - prevRead) / dt : 0
            d.writeRate = write >= prevWrite ? Double(write - prevWrite) / dt : 0
        }
        prevRead = read; prevWrite = write; prevTime = now
        return d
    }
}

// MARK: - Network

struct NetSnapshot {
    var down: Double = 0
    var up: Double = 0
    var totalDown: Double = 0
    var totalUp: Double = 0
    var interface: String = "未连接"
    var isWiFi = false
    var rssi: Int = 0
    var localIP: String = "—"
}

final class NetworkSampler {
    private var prev: [String: (UInt32, UInt32)] = [:]
    private var prevTime: TimeInterval = 0
    private var totalDown: Double = 0
    private var totalUp: Double = 0
    private lazy var wifiName: String? = CWWiFiClient.shared().interface()?.interfaceName

    func sample() -> NetSnapshot {
        var n = NetSnapshot()
        var cur: [String: (UInt32, UInt32)] = [:]
        var ipv4: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return n }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let a = p {
            defer { p = a.pointee.ifa_next }
            let name = String(cString: a.pointee.ifa_name)
            guard name.hasPrefix("en"), let addr = a.pointee.ifa_addr else { continue }
            let flags = Int32(a.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = a.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                cur[name] = (d.ifi_ibytes, d.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ipv4[name] = String(cString: host)
                }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        var din = 0.0, dout = 0.0
        for (k, v) in cur {
            if let o = prev[k] {
                din += Double(v.0 &- o.0)
                dout += Double(v.1 &- o.1)
            }
        }
        if prevTime > 0, now > prevTime {
            let dt = now - prevTime
            n.down = din / dt; n.up = dout / dt
            totalDown += din; totalUp += dout
        }
        prev = cur; prevTime = now
        n.totalDown = totalDown; n.totalUp = totalUp

        if let primary = ipv4.keys.sorted().first {
            n.localIP = ipv4[primary] ?? "—"
            if primary == wifiName {
                n.isWiFi = true
                n.interface = "Wi‑Fi"
                n.rssi = CWWiFiClient.shared().interface()?.rssiValue() ?? 0
            } else {
                n.interface = "以太网"
            }
        }
        return n
    }
}

// MARK: - GPU

func sampleGPU() -> Double {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
    else { return 0 }
    defer { IOObjectRelease(iter) }
    var result = 0.0
    var s = IOIteratorNext(iter)
    while s != 0 {
        if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
            let u = stats["Device Utilization %"] as? NSNumber {
            result = max(result, u.doubleValue / 100)
        }
        IOObjectRelease(s)
        s = IOIteratorNext(iter)
    }
    return min(1, result)
}

// MARK: - Battery

struct BatterySnapshot {
    var level: Double = 0
    var charging = false
    var onAC = false
    var minutesRemaining: Int?
    var cycles: Int?
    var health: Double?
    var temperature: Double?

    var status: String {
        if charging { return "充电中" }
        if onAC { return level >= 0.99 ? "已充满" : "已接通电源" }
        return "使用电池"
    }
}

func sampleBattery() -> BatterySnapshot? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
              (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
        var b = BatterySnapshot()
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        b.level = max > 0 ? Double(cur) / Double(max) : 0
        b.charging = d[kIOPSIsChargingKey] as? Bool ?? false
        b.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let t = b.charging ? d[kIOPSTimeToFullChargeKey] as? Int : d[kIOPSTimeToEmptyKey] as? Int
        if let t, t > 0 { b.minutesRemaining = t }

        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               var p = props?.takeRetainedValue() as? [String: Any] {
                if let nested = p["BatteryData"] as? [String: Any] {
                    p.merge(nested) { top, _ in top }
                }
                b.cycles = p["CycleCount"] as? Int
                let design = p["DesignCapacity"] as? Int ?? 0
                let raw = (p["AppleRawMaxCapacity"] as? Int) ?? (p["NominalChargeCapacity"] as? Int) ?? 0
                if design > 0, raw > 0 { b.health = min(1, Double(raw) / Double(design)) }
                if let temp = p["Temperature"] as? Int { b.temperature = Double(temp) / 100 }
            }
            IOObjectRelease(svc)
        }
        return b
    }
    return nil
}

// MARK: - Processes

struct ProcInfo: Identifiable {
    let id: pid_t
    let name: String
    let cpu: Double
    let memory: Double
    let icon: NSImage
}

final class ProcessSampler {
    private var prev: [pid_t: UInt64] = [:]
    private var prevTime: UInt64 = 0
    private var nameCache: [pid_t: (String, NSImage)] = [:]
    private let ownPID = getpid()

    func sample(limit: Int = 5) -> [ProcInfo] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let cnt = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard cnt > 0 else { return [] }

        let now = mach_absolute_time()
        let elapsed = Double(now &- prevTime)
        var cur: [pid_t: UInt64] = [:]
        var usage: [(pid_t, Double, Double)] = []
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in pids.prefix(Int(cnt)) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else { continue }
            let t = info.pti_total_user + info.pti_total_system
            cur[pid] = t
            if prevTime > 0, let o = prev[pid], t >= o, elapsed > 0 {
                usage.append((pid, Double(t - o) / elapsed, Double(info.pti_resident_size)))
            }
        }
        prev = cur
        prevTime = now
        nameCache = nameCache.filter { cur[$0.key] != nil }

        return usage
            .filter { $0.0 != ownPID }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { p in
                let (name, icon) = describe(p.0)
                return ProcInfo(id: p.0, name: name, cpu: p.1, memory: p.2, icon: icon)
            }
    }

    private func describe(_ pid: pid_t) -> (String, NSImage) {
        if let c = nameCache[pid] { return c }
        var result: (String, NSImage)
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            result = (name, app.icon ?? NSWorkspace.shared.icon(for: .application))
        } else {
            var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let len = proc_pidpath(pid, &buf, UInt32(buf.count))
            let path = len > 0 ? String(cString: buf) : ""
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            var name = String(cString: nameBuf)
            if name.isEmpty { name = (path as NSString).lastPathComponent }
            if name.isEmpty { name = "PID \(pid)" }
            let icon: NSImage
            if let r = path.range(of: ".app/") {
                icon = NSWorkspace.shared.icon(forFile: String(path[..<r.lowerBound]) + ".app")
            } else {
                icon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
            }
            result = (name, icon)
        }
        nameCache[pid] = result
        return result
    }
}
