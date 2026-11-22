import ServiceManagement
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var m: Monitor
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue

    private var scheme: ColorScheme {
        switch AppearanceMode(rawValue: appearance) ?? .system {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }
    static let columnWidth: CGFloat = 258

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    ClockCard()
                    CPUCard()
                    GPUCard().fillHeight()
                }
                .frame(width: Self.columnWidth)
                VStack(spacing: 12) {
                    MemoryCard()
                    DiskCard().fillHeight()
                }
                .frame(width: Self.columnWidth)
                VStack(spacing: 12) {
                    NetworkCard()
                    if m.battery != nil {
                        ProcessCard()
                        BatteryCard().fillHeight()
                    } else {
                        ProcessCard().fillHeight()
                    }
                }
                .frame(width: Self.columnWidth)
            }
            FooterBar()
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, scheme)
    }
}

// MARK: - Cards

private struct FillHeightKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var cardFillsHeight: Bool {
        get { self[FillHeightKey.self] }
        set { self[FillHeightKey.self] = newValue }
    }
}

extension View {
    func fillHeight() -> some View { environment(\.cardFillsHeight, true) }
}

struct ClockCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.time(m.now)).font(.system(size: 44, weight: .light)).monospacedDigit()
                    Text(Fmt.seconds(m.now)).font(.system(size: 18, weight: .light)).monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
                .foregroundStyle(Theme.text)
                Text(Fmt.date(m.now)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(Fmt.lunar(m.now)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                Divider().overlay(Theme.stroke).padding(.vertical, 6)
                InfoRow(label: "已运行", value: Fmt.duration(ProcessInfo.processInfo.systemUptime))
            }
        }
    }
}

struct CPUCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        Card("处理器", icon: "cpu", trailing: m.chip.replacingOccurrences(of: "Apple ", with: "")) {
            HStack(alignment: .firstTextBaseline) {
                BigValue(value: Fmt.pct(m.cpu.total), unit: "%", size: 30)
                Spacer()
                Text("负载 " + m.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.faint)
            }
            StackedBars(a: m.cpuUser, b: m.cpuSystem, colorA: Theme.cyan, colorB: Theme.red)
                .frame(height: 52)
            HStack(spacing: 14) {
                HStack(spacing: 6) { Dot(color: Theme.cyan); Text("用户"); Text(Fmt.pct(m.cpu.user) + "%").monospacedDigit() }
                HStack(spacing: 6) { Dot(color: Theme.red); Text("系统"); Text(Fmt.pct(m.cpu.system) + "%").monospacedDigit() }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.text)

            let cores = m.cpu.cores
            if !cores.isEmpty {
                let e = min(m.eCores, cores.count)
                VStack(alignment: .leading, spacing: 8) {
                    if e > 0 {
                        coreGroup("能效核心", Array(cores.prefix(e)), Theme.red)
                    }
                    coreGroup(e > 0 ? "性能核心" : "核心", Array(cores.dropFirst(e)), Theme.cyan)
                }
                .padding(.top, 2)
            }
        }
    }

    private func coreGroup(_ title: String, _ values: [Double], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Dot(color: color)
                Text(title).foregroundStyle(Theme.text.opacity(0.85))
                Spacer()
                Text(Fmt.pct(values.reduce(0, +) / Double(max(1, values.count))) + "%").monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            .font(.system(size: 12))
            CoreRings(values: values, color: color)
        }
    }
}

struct GPUCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        Card("图形处理器", icon: "square.stack.3d.up.fill") {
            HStack(spacing: 14) {
                RingGauge(m.gpu, color: Theme.purple, title: "GPU", size: 64, lineWidth: 6)
                StackedBars(a: m.gpuHistory, b: m.gpuHistory.map { _ in 0 }, colorA: Theme.purple, colorB: .clear)
                    .frame(height: 50)
            }
        }
    }
}

struct MemoryCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        let mem = m.mem
        let t = mem.total
        Card("内存", icon: "memorychip", trailing: Fmt.bytesString(t)) {
            HStack {
                RingGauge(mem.pressure, color: pressureColor(mem.pressure), title: "压力")
                Spacer()
                RingGauge(segments: [(mem.app / t, Theme.cyan), (mem.wired / t, Theme.red),
                                     (mem.compressed / t, Theme.purple)], title: "已用")
            }
            .padding(.horizontal, 6)
            VStack(spacing: 6) {
                LegendRow(color: Theme.cyan, label: "App 内存", value: Fmt.bytesString(mem.app))
                LegendRow(color: Theme.red, label: "联动内存", value: Fmt.bytesString(mem.wired))
                LegendRow(color: Theme.purple, label: "已压缩", value: Fmt.bytesString(mem.compressed))
                LegendRow(color: Theme.gray, label: "可用", value: Fmt.bytesString(mem.available))
            }
            .padding(.top, 2)
            if mem.swapUsed > 0 {
                InfoRow(label: "交换", value: Fmt.bytesString(mem.swapUsed))
            }
        }
    }

    private func pressureColor(_ p: Double) -> Color {
        p > 0.8 ? Theme.red : p > 0.6 ? Theme.orange : Theme.green
    }
}

struct DiskCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        let d = m.disk
        Card("磁盘", icon: "internaldrive") {
            HStack(spacing: 14) {
                RingGauge(d.usage, color: Theme.cyan, title: "已用", size: 64, lineWidth: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text("可用 " + Fmt.bytesString(d.available, base: 1000)).font(.system(size: 12))
                        .foregroundStyle(Theme.text.opacity(0.85))
                    Text("共 " + Fmt.bytesString(d.total, base: 1000)).font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
            HStack {
                rate(d.readRate, "读取", Theme.red)
                Spacer()
                rate(d.writeRate, "写入", Theme.cyan)
            }
            MirrorBars(up: m.diskRead, down: m.diskWrite).frame(minHeight: 48, maxHeight: .infinity)
        }
    }

    private func rate(_ v: Double, _ label: String, _ color: Color) -> some View {
        let (a, b) = Fmt.rate(v)
        return VStack(alignment: .leading, spacing: 1) {
            BigValue(value: a, unit: b, size: 18)
            HStack(spacing: 5) { Dot(color: color); Text(label) }
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }
}

struct BatteryCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        if let b = m.battery {
            Card("电池", icon: b.charging ? "battery.100.bolt" : "battery.75", trailing: b.status) {
                HStack(spacing: 14) {
                    RingGauge(b.level, color: color(b), title: "电量", size: 64, lineWidth: 6)
                    VStack(spacing: 5) {
                        if let mins = b.minutesRemaining {
                            InfoRow(label: b.charging ? "充满还需" : "剩余", value: Fmt.minutes(mins))
                        }
                        if let h = b.health { InfoRow(label: "健康度", value: Fmt.pct(h) + "%") }
                        if let c = b.cycles { InfoRow(label: "循环次数", value: "\(c)") }
                        if let t = b.temperature { InfoRow(label: "温度", value: String(format: "%.1f°", t)) }
                    }
                }
            }
        }
    }

    private func color(_ b: BatterySnapshot) -> Color {
        if b.charging || b.onAC { return Theme.green }
        return b.level < 0.2 ? Theme.red : b.level < 0.4 ? Theme.orange : Theme.green
    }
}

struct NetworkCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        let n = m.net
        Card("网络", icon: "arrow.up.arrow.down") {
            HStack {
                rate(n.up, "上传", Theme.red)
                Spacer()
                rate(n.down, "下载", Theme.cyan, trailing: true)
            }
            MirrorBars(up: m.netUp, down: m.netDown).frame(height: 78)
            VStack(spacing: 7) {
                HStack {
                    Image(systemName: n.isWiFi ? "wifi" : "cable.connector")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cyan)
                    Text(n.interface).foregroundStyle(Theme.text)
                    Spacer()
                    if n.isWiFi && n.rssi != 0 {
                        Text("信号 \(signal(n.rssi)) · \(n.rssi) dBm").foregroundStyle(Theme.dim).monospacedDigit()
                    }
                }
                .font(.system(size: 12))
                InfoRow(label: "内网 IP", value: n.localIP)
                HStack {
                    Text("公网 IP").foregroundStyle(Theme.dim)
                    Spacer()
                    if let ip = m.publicIP {
                        Text(ip).monospacedDigit().foregroundStyle(Theme.text).textSelection(.enabled)
                    } else {
                        Button(m.fetchingIP ? "查询中…" : "点击查询") { m.fetchPublicIP() }
                            .buttonStyle(.plain).foregroundStyle(Theme.cyan)
                    }
                }
                .font(.system(size: 11.5))
                InfoRow(label: "本次累计", value: "↑ \(Fmt.bytesString(n.totalUp, base: 1000))   ↓ \(Fmt.bytesString(n.totalDown, base: 1000))")
            }
        }
    }

    private func signal(_ rssi: Int) -> String {
        rssi >= -55 ? "极佳" : rssi >= -67 ? "良好" : rssi >= -75 ? "一般" : "较弱"
    }

    private func rate(_ v: Double, _ label: String, _ color: Color, trailing: Bool = false) -> some View {
        let (a, b) = Fmt.rate(v)
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            BigValue(value: a, unit: b, size: 20)
            HStack(spacing: 5) { Dot(color: color); Text(label) }
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }
}

struct ProcessCard: View {
    @EnvironmentObject var m: Monitor

    var body: some View {
        Card("进程", icon: "list.bullet", trailing: "CPU    内存") {
            VStack(spacing: 8) {
                if m.processes.isEmpty {
                    Text("正在采集…").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(m.processes) { p in
                    HStack(spacing: 8) {
                        Image(nsImage: p.icon).resizable().frame(width: 16, height: 16)
                        Text(p.name).lineLimit(1).truncationMode(.tail).foregroundStyle(Theme.text)
                        Spacer(minLength: 4)
                        Text(String(format: "%.1f%%", p.cpu * 100)).monospacedDigit().foregroundStyle(Theme.text)
                            .frame(width: 46, alignment: .trailing)
                        Text(Fmt.bytesString(p.memory)).monospacedDigit().foregroundStyle(Theme.dim)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: - Footer

struct FooterBar: View {
    @AppStorage(Prefs.barCPU) private var barCPU = true
    @AppStorage(Prefs.barMem) private var barMem = true
    @AppStorage(Prefs.barNet) private var barNet = true
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.autoUpdate) private var autoUpdate = true
    @EnvironmentObject private var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Theme.cyan)
                Text("观微").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Text("· 系统监视器").font(.system(size: 12)).foregroundStyle(Theme.faint)
                Text("v\(updater.currentVersion)").font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.faint)
                if let r = updater.available {
                    Button { updater.promptUpdate(r) } label: {
                        Text(updater.installing ? "正在更新…" : "新版本 v\(r.version)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.cyan))
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.installing)
                }
            }
            Spacer()
            Menu {
                Section("菜单栏显示") {
                    Toggle("CPU 使用率", isOn: $barCPU)
                    Toggle("内存占用", isOn: $barMem)
                    Toggle("网络速率", isOn: $barNet)
                }
                Picker("外观", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("登录时启动", isOn: Binding(get: { launchAtLogin }, set: { setLaunch($0) }))
                Divider()
                Button(updater.checking ? "正在检查…" : "检查更新…") { updater.checkNow() }
                    .disabled(updater.checking)
                Toggle("自动检查更新", isOn: $autoUpdate)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            footerButton("waveform.path.ecg", "活动监视器") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            footerButton("power", "退出") { NSApp.terminate(nil) }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 4)
    }

    private func footerButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.plain)
            .help(help)
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("登录项设置失败: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
