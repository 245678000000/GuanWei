import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.dashboard(to: args[i + 1]) }
            return
        }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.icon(to: args[i + 1]) }
            return
        }
        if args.contains("--window") {
            MainActor.assumeIsolated { Snapshot.previewWindow() }
            return
        }
        GuanWeiApp.main()
    }
}

struct GuanWeiApp: App {
    @StateObject private var monitor: Monitor = {
        let m = Monitor.shared
        m.start()
        return m
    }()
    @StateObject private var updater: Updater = {
        let u = Updater.shared
        u.startAutoCheck()
        return u
    }()

    var body: some Scene {
        MenuBarExtra {
            DashboardView().environmentObject(monitor).environmentObject(updater)
        } label: {
            Image(nsImage: monitor.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Offline rendering (used for previews and the app icon)

@MainActor
enum Snapshot {
    static func dashboard(to path: String) {
        _ = NSApplication.shared
        let m = Monitor.shared
        for _ in 0..<3 {
            m.tick()
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        }
        write(DashboardView().environmentObject(m).environmentObject(Updater.shared), scale: 2, to: path)
        write(m.menuBarImageView, scale: 4, to: path.replacingOccurrences(of: ".png", with: "-bar.png"))
    }

    /// 以普通窗口显示面板（调试用）
    static func previewWindow() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if let i = CommandLine.arguments.firstIndex(of: "--appearance"), i + 1 < CommandLine.arguments.count {
            UserDefaults.standard.set(CommandLine.arguments[i + 1], forKey: Prefs.appearance)
        }
        let m = Monitor.shared
        m.start()
        let host = NSHostingController(rootView: DashboardView().environmentObject(m).environmentObject(Updater.shared))
        let win = NSWindow(contentViewController: host)
        win.title = "观微"
        win.styleMask = [.titled, .closable]
        win.center()
        win.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func icon(to path: String) {
        _ = NSApplication.shared
        write(AppIconView().frame(width: 1024, height: 1024), scale: 1, to: path)
    }

    private static func write<V: View>(_ view: V, scale: CGFloat, to path: String) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let cg = r.cgImage else { print("render failed"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

extension Monitor {
    var menuBarImageView: some View {
        MenuBarLabel(cpu: cpu.total, mem: mem.usage, net: (net.up, net.down)).background(.white)
    }
}

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.21), Color(red: 0.04, green: 0.05, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(100)
            Ring(segments: [(0.62, Theme.cyan)], lineWidth: 64).frame(width: 520, height: 520)
            Ring(segments: [(0.38, Theme.red)], lineWidth: 64).frame(width: 340, height: 340)
            Circle().fill(Theme.text).frame(width: 70, height: 70)
        }
    }
}
