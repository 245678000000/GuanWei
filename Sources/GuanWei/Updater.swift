import AppKit
import Foundation

struct ReleaseInfo {
    let version: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL?
}

private struct GHRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let tag_name: String
    let html_url: URL
    let body: String?
    let assets: [Asset]
}

enum UpdateError: LocalizedError {
    case noRelease
    case http(Int)
    case badPackage(String)

    var errorDescription: String? {
        switch self {
        case .noRelease: "仓库中还没有发布任何版本，或仓库不可公开访问。"
        case let .http(code): "服务器返回错误（HTTP \(code)）。"
        case let .badPackage(msg): msg
        }
    }
}

/// 基于 GitHub Releases 的检查更新与自动安装
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "245678000000/GuanWei"

    /// 发现的新版本（仅当比当前版本新时才有值）
    @Published var available: ReleaseInfo?
    @Published var checking = false
    @Published var installing = false

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: 自动检查

    func startAutoCheck() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.autoCheck()
        }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoCheck() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func autoCheck() {
        guard UserDefaults.standard.bool(forKey: Prefs.autoUpdate) else { return }
        Task { _ = try? await fetchLatest() }
    }

    // MARK: 手动检查

    func checkNow() {
        guard !checking else { return }
        Task {
            do {
                if let r = try await fetchLatest() {
                    promptUpdate(r)
                } else {
                    alert("已是最新版本", "观微 \(currentVersion) 是当前最新版本。")
                }
            } catch {
                alert("检查更新失败", error.localizedDescription)
            }
        }
    }

    /// 获取最新发行版；返回值不为 nil 表示有新版本
    @discardableResult
    func fetchLatest() async throws -> ReleaseInfo? {
        checking = true
        defer { checking = false }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("GuanWei-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw UpdateError.noRelease }
        guard code == 200 else { throw UpdateError.http(code) }
        let gh = try JSONDecoder().decode(GHRelease.self, from: data)
        let version = gh.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let zip = gh.assets.first { $0.name.lowercased().hasSuffix(".zip") }?.browser_download_url
        let info = ReleaseInfo(version: version, notes: gh.body ?? "", pageURL: gh.html_url, downloadURL: zip)
        available = Self.isNewer(version, than: currentVersion) ? info : nil
        return available
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: 提示与安装

    func promptUpdate(_ r: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "发现新版本 v\(r.version)"
        var notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 600 { notes = String(notes.prefix(600)) + "…" }
        a.informativeText = "当前版本 \(currentVersion)" + (notes.isEmpty ? "" : "\n\n\(notes)")
        if r.downloadURL != nil { a.addButton(withTitle: "立即更新") }
        a.addButton(withTitle: "查看发行说明")
        a.addButton(withTitle: "稍后")
        let res = a.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn
        let second = NSApplication.ModalResponse.alertSecondButtonReturn
        if r.downloadURL != nil {
            if res == first { install(r) } else if res == second { NSWorkspace.shared.open(r.pageURL) }
        } else if res == first {
            NSWorkspace.shared.open(r.pageURL)
        }
    }

    func install(_ r: ReleaseInfo) {
        guard let url = r.downloadURL, !installing else { return }
        installing = true
        Task {
            defer { installing = false }
            do {
                let newApp = try await download(url)
                try replaceAndRelaunch(with: newApp)
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "自动更新失败"
                a.informativeText = error.localizedDescription + "\n\n可前往发行页手动下载。"
                a.addButton(withTitle: "打开发行页")
                a.addButton(withTitle: "取消")
                if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(r.pageURL) }
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.http(code) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("GuanWeiUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("update.zip")
        try fm.moveItem(at: tmp, to: zip)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.badPackage("解压更新包失败。") }

        guard let app = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.badPackage("更新包中没有找到应用。")
        }
        guard Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.badPackage("更新包的应用标识不匹配。")
        }
        return app
    }

    private func replaceAndRelaunch(with newApp: URL) throws {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else {
            throw UpdateError.badPackage("当前不是以 .app 方式运行，无法自动替换。")
        }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", target.path]
        try p.run()
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "好")
        a.runModal()
    }
}
