import AppKit
import SwiftUI

enum Prefs {
    static let barCPU = "bar.cpu"
    static let barMem = "bar.mem"
    static let barNet = "bar.net"
    static let appearance = "appearance"

    static func register() {
        UserDefaults.standard.register(defaults: [barCPU: true, barMem: true, barNet: true, appearance: AppearanceMode.system.rawValue])
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

@MainActor
final class Monitor: ObservableObject {
    static let shared = Monitor()
    static let historySize = 60

    @Published var cpu = CPUSnapshot()
    @Published var cpuUser: [Double] = []
    @Published var cpuSystem: [Double] = []
    @Published var mem = MemorySnapshot()
    @Published var gpu: Double = 0
    @Published var gpuHistory: [Double] = []
    @Published var net = NetSnapshot()
    @Published var netUp: [Double] = []
    @Published var netDown: [Double] = []
    @Published var disk = DiskSnapshot()
    @Published var diskRead: [Double] = []
    @Published var diskWrite: [Double] = []
    @Published var battery: BatterySnapshot?
    @Published var processes: [ProcInfo] = []
    @Published var load: [Double] = [0, 0, 0]
    @Published var now = Date()
    @Published var publicIP: String?
    @Published var fetchingIP = false
    @Published var menuBarImage = NSImage(size: NSSize(width: 20, height: 22))

    let chip: String
    let eCores: Int
    let pCores: Int

    private let cpuSampler = CPUSampler()
    private let diskSampler = DiskSampler()
    private let netSampler = NetworkSampler()
    private let procSampler = ProcessSampler()
    private var ticks = 0
    private var timer: Timer?

    private init() {
        Prefs.register()
        chip = sysctlString("machdep.cpu.brand_string") ?? "Mac"
        pCores = sysctlInt("hw.perflevel0.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        eCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func tick() {
        now = Date()
        cpu = cpuSampler.sample()
        push(&cpuUser, cpu.user)
        push(&cpuSystem, cpu.system)
        mem = sampleMemory()
        gpu = sampleGPU()
        push(&gpuHistory, gpu)
        net = netSampler.sample()
        push(&netUp, net.up)
        push(&netDown, net.down)
        disk = diskSampler.sample()
        push(&diskRead, disk.readRate)
        push(&diskWrite, disk.writeRate)

        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        load = l

        if ticks % 2 == 0 { processes = procSampler.sample() }
        if ticks % 10 == 0 { battery = sampleBattery() }
        ticks += 1
        updateMenuBarImage()
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > Self.historySize { arr.removeFirst(arr.count - Self.historySize) }
    }

    func fetchPublicIP() {
        guard !fetchingIP else { return }
        fetchingIP = true
        Task {
            var ip: String?
            if let url = URL(string: "https://api.ipify.org"),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            publicIP = ip ?? "查询失败"
            fetchingIP = false
        }
    }

    private func updateMenuBarImage() {
        let d = UserDefaults.standard
        let view = MenuBarLabel(
            cpu: d.bool(forKey: Prefs.barCPU) ? cpu.total : nil,
            mem: d.bool(forKey: Prefs.barMem) ? mem.usage : nil,
            net: d.bool(forKey: Prefs.barNet) ? (net.up, net.down) : nil
        )
        let r = ImageRenderer(content: view)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let img = r.nsImage {
            img.isTemplate = true
            menuBarImage = img
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ v: Double, base: Double = 1024) -> (String, String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var x = max(0, v), i = 0
        while x >= base && i < units.count - 1 { x /= base; i += 1 }
        let s = (i == 0 || x >= 100) ? String(format: "%.0f", x) : String(format: "%.1f", x)
        return (s, units[i])
    }

    static func bytesString(_ v: Double, base: Double = 1024) -> String {
        let (a, b) = bytes(v, base: base)
        return "\(a) \(b)"
    }

    static func rate(_ v: Double) -> (String, String) {
        let (a, b) = bytes(v, base: 1000)
        return (a, b + "/s")
    }

    static func rateString(_ v: Double) -> String {
        let (a, b) = rate(v)
        return "\(a) \(b)"
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))" }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d) 天 \(h % 24) 小时" }
        if h > 0 { return "\(h) 小时 \(m % 60) 分" }
        return "\(m) 分钟"
    }

    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let lunarFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .chinese)
        f.dateFormat = "U年 MMM"
        return f
    }()

    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    static func date(_ d: Date) -> String { dateFmt.string(from: d) }
    static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    static func seconds(_ d: Date) -> String { String(format: "%02d", Calendar.current.component(.second, from: d)) }

    static func lunar(_ d: Date) -> String {
        let day = Calendar(identifier: .chinese).component(.day, from: d)
        return "农历 " + lunarFmt.string(from: d) + lunarDays[max(0, min(29, day - 1))]
    }
}
