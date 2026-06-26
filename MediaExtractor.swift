import SwiftUI
import AppKit
import WebKit
import Security
import UniformTypeIdentifiers
import CryptoKit

// MARK: - App Entry

@main
struct MediaExtractorApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.isDark ? .dark : .light)
        }
        .defaultSize(width: 1100, height: 850)
    }
}

// MARK: - Enums

enum SidebarItem: String, Hashable {
    case media, connections, csv, documents, settings, logs
}

enum Platform: String, CaseIterable, Codable, Identifiable {
    case instagram = "Instagram"
    case tiktok = "TikTok"
    case twitter = "Twitter"
    case youtube = "YouTube"
    case soundcloud = "SoundCloud"
    case rednote = "RedNote"
    case spotify = "Spotify"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .twitter: "bubble.left.fill"
        case .youtube: "play.rectangle.fill"
        case .soundcloud: "waveform"
        case .rednote: "text.book.closed.fill"
        case .spotify: "headphones"
        }
    }

    var loginURL: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/accounts/login/")!
        case .tiktok: URL(string: "https://www.tiktok.com/login")!
        case .twitter: URL(string: "https://x.com/i/flow/login")!
        case .youtube: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube")!
        case .soundcloud: URL(string: "https://soundcloud.com/signin")!
        case .rednote: URL(string: "https://www.xiaohongshu.com/login")!
        case .spotify: URL(string: "https://accounts.spotify.com/login")!
        }
    }

    var baseURL: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/")!
        case .tiktok: URL(string: "https://www.tiktok.com/")!
        case .twitter: URL(string: "https://x.com/")!
        case .youtube: URL(string: "https://www.youtube.com/")!
        case .soundcloud: URL(string: "https://soundcloud.com/")!
        case .rednote: URL(string: "https://www.xiaohongshu.com/")!
        case .spotify: URL(string: "https://open.spotify.com/")!
        }
    }

    var domains: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .tiktok: ["tiktok.com"]
        case .twitter: ["twitter.com", "x.com"]
        case .youtube: ["youtube.com", "google.com"]
        case .soundcloud: ["soundcloud.com"]
        case .rednote: ["xiaohongshu.com", "rednote.com"]
        case .spotify: ["spotify.com"]
        }
    }

    func isLoggedIn(url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        switch self {
        case .instagram: return s.contains("instagram.com") && !s.contains("/accounts/login") && !s.contains("/challenge")
        case .tiktok: return s.contains("tiktok.com") && !s.contains("/login")
        case .twitter: return (s.contains("x.com") || s.contains("twitter.com")) && !s.contains("/login") && !s.contains("/i/flow")
        case .youtube: return s.contains("youtube.com")
        case .soundcloud: return s.contains("soundcloud.com") && !s.contains("/signin")
        case .rednote: return s.contains("xiaohongshu.com") && !s.contains("/login")
        case .spotify: return s.contains("open.spotify.com")
        }
    }

    static func detect(from url: String) -> Platform? {
        let l = url.lowercased()
        if l.contains("instagram.com") { return .instagram }
        if l.contains("tiktok.com") { return .tiktok }
        if l.contains("twitter.com") || l.contains("x.com") { return .twitter }
        if l.contains("youtube.com") || l.contains("youtu.be") { return .youtube }
        if l.contains("soundcloud.com") { return .soundcloud }
        if l.contains("xiaohongshu.com") || l.contains("rednote") { return .rednote }
        if l.contains("spotify.com") { return .spotify }
        return nil
    }
}

enum QualityPreset: String, CaseIterable { case best = "Best", q4k = "4K", q1080 = "1080p", q720 = "720p", q480 = "480p" }
enum VidFormat: String, CaseIterable { case mp4 = "MP4", webm = "WebM", mkv = "MKV" }
enum AudFormat: String, CaseIterable { case mp3 = "MP3", flac = "FLAC", wav = "WAV", m4a = "M4A" }
enum AudBitrate: String, CaseIterable { case k128 = "128k", k192 = "192k", k256 = "256k", k320 = "320k" }
enum PhotoFmt: String, CaseIterable { case original = "Original", jpeg = "JPEG", png = "PNG", webp = "WebP" }
enum ProcessPriorityLevel: String, CaseIterable { case low = "low", normal = "normal", high = "high" }
enum KeywordMode: String { case global, perCSV }
enum CSVPhase: Equatable { case idle, ready, downloading, complete, error(String) }
enum ExtractionStatus: Equatable { case pending, inProgress(done: Int, total: Int), complete(success: Int, failed: Int) }

// MARK: - Models

struct ConnectedAccount: Identifiable, Codable {
    let id: UUID
    let platform: Platform
    var displayName: String
    let connectedDate: Date
}

struct CookieData: Codable {
    let name, value, domain, path: String
    let isSecure: Bool
    let expires: Double?
    init(cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        isSecure = cookie.isSecure; expires = cookie.expiresDate?.timeIntervalSince1970
    }
    func toCookie() -> HTTPCookie? {
        var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if isSecure { p[.secure] = "TRUE" }
        if let e = expires { p[.expires] = Date(timeIntervalSince1970: e) }
        return HTTPCookie(properties: p)
    }
}

struct DownloadRecord: Identifiable {
    let id = UUID()
    let date: Date
    let url: String
    let platform: Platform?
    var title: String
    var status: DLStatus
    var filePath: String?
    var fileSize: Int64
    var error: String?
    var taskHandle: Task<Void, Never>?
    var processRef: Process?
}
enum DLStatus { case downloading, complete, failed, cancelled }

struct LogEntry: Identifiable, Codable {
    let id: UUID; let date: Date; let level: String; let message: String; let detail: String?
}

struct SessionRecord: Codable, Identifiable {
    let id: UUID; let date, endDate: Date; let duration: TimeInterval
    let baseFolderPath, sessionName: String; let extractions: [ExtractionRecord]
    var totalSuccess, totalFailed: Int; var totalBytes: Int64; var allErrors: [String: Int]
}
struct ExtractionRecord: Codable, Identifiable {
    var id: String { csvFilename }
    let csvFilename, folderName: String; let urlCount, success, failed: Int
    let bytes: Int64; let typeBreakdown: [String: Int]; let errors: [String: Int]
}
struct OneResult { let ok: Bool; let ext: String; let bytes: Int64; let error: String? }

struct CSVEntry: Identifiable {
    let id = UUID(); let url: URL
    var filename: String { url.lastPathComponent }
    var stem: String { (url.lastPathComponent as NSString).deletingPathExtension }
    var keywords: [String] = []; var mediaURLs: [String] = []
    var urlCount: Int { mediaURLs.count }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case midnight = "Midnight"
    case dracula = "Dracula"
    case catppuccin = "Catppuccin"
    case oneDark = "One Dark"
    case nord = "Nord"
    case ayu = "Ayu"
    case light = "Light"
    case rosePine = "Ros\u{00e9} Pine"
    var id: String { rawValue }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var current: AppTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "appTheme") }
    }
    init() {
        let saved = UserDefaults.standard.string(forKey: "appTheme") ?? "Midnight"
        self.current = AppTheme(rawValue: saved) ?? .midnight
    }
    var isDark: Bool { current != .light }
}

enum T {
    private static var tm: ThemeManager { ThemeManager.shared }
    static var bg: Color { palette.bg }
    static var surface: Color { palette.surface }
    static var surfaceHover: Color { palette.surfaceHover }
    static var border: Color { palette.border }
    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static var accent: Color { palette.accent }
    static var accentDim: Color { palette.accent.opacity(0.4) }
    static var success: Color { palette.success }
    static var danger: Color { palette.danger }

    static var palette: ThemePalette {
        switch tm.current {
        case .midnight: return .midnight
        case .dracula: return .dracula
        case .catppuccin: return .catppuccin
        case .oneDark: return .oneDark
        case .nord: return .nord
        case .ayu: return .ayu
        case .light: return .light
        case .rosePine: return .rosePine
        }
    }
}

struct ThemePalette {
    let bg, surface, surfaceHover, border, text, muted, accent, success, danger: Color

    static let midnight = ThemePalette(
        bg: Color(red: 0.04, green: 0.04, blue: 0.04), surface: Color(white: 0.08), surfaceHover: Color(white: 0.12),
        border: Color.white.opacity(0.06), text: Color(red: 0.91, green: 0.90, blue: 0.88), muted: Color.white.opacity(0.35),
        accent: Color(red: 0.77, green: 0.71, blue: 0.61), success: Color(red: 0.4, green: 0.75, blue: 0.4), danger: Color(red: 0.85, green: 0.35, blue: 0.35))
    static let dracula = ThemePalette(
        bg: Color(red: 0.16, green: 0.16, blue: 0.21), surface: Color(red: 0.21, green: 0.22, blue: 0.28), surfaceHover: Color(red: 0.26, green: 0.27, blue: 0.34),
        border: Color(red: 0.38, green: 0.40, blue: 0.53).opacity(0.3), text: Color(red: 0.97, green: 0.97, blue: 0.95), muted: Color(red: 0.62, green: 0.66, blue: 0.76),
        accent: Color(red: 0.74, green: 0.58, blue: 0.98), success: Color(red: 0.31, green: 0.98, blue: 0.48), danger: Color(red: 1.0, green: 0.33, blue: 0.33))
    static let catppuccin = ThemePalette(
        bg: Color(red: 0.12, green: 0.12, blue: 0.18), surface: Color(red: 0.16, green: 0.16, blue: 0.23), surfaceHover: Color(red: 0.20, green: 0.20, blue: 0.28),
        border: Color(red: 0.27, green: 0.28, blue: 0.35).opacity(0.4), text: Color(red: 0.80, green: 0.84, blue: 0.96), muted: Color(red: 0.44, green: 0.46, blue: 0.58),
        accent: Color(red: 0.54, green: 0.71, blue: 0.98), success: Color(red: 0.65, green: 0.89, blue: 0.63), danger: Color(red: 0.95, green: 0.55, blue: 0.66))
    static let oneDark = ThemePalette(
        bg: Color(red: 0.16, green: 0.18, blue: 0.20), surface: Color(red: 0.20, green: 0.22, blue: 0.24), surfaceHover: Color(red: 0.24, green: 0.26, blue: 0.29),
        border: Color(red: 0.30, green: 0.33, blue: 0.36).opacity(0.4), text: Color(red: 0.67, green: 0.73, blue: 0.82), muted: Color(red: 0.40, green: 0.44, blue: 0.50),
        accent: Color(red: 0.38, green: 0.71, blue: 0.93), success: Color(red: 0.60, green: 0.80, blue: 0.40), danger: Color(red: 0.88, green: 0.43, blue: 0.45))
    static let nord = ThemePalette(
        bg: Color(red: 0.18, green: 0.20, blue: 0.25), surface: Color(red: 0.23, green: 0.26, blue: 0.32), surfaceHover: Color(red: 0.26, green: 0.30, blue: 0.37),
        border: Color(red: 0.30, green: 0.34, blue: 0.42).opacity(0.4), text: Color(red: 0.85, green: 0.87, blue: 0.91), muted: Color(red: 0.50, green: 0.55, blue: 0.65),
        accent: Color(red: 0.53, green: 0.75, blue: 0.82), success: Color(red: 0.64, green: 0.74, blue: 0.55), danger: Color(red: 0.75, green: 0.38, blue: 0.42))
    static let ayu = ThemePalette(
        bg: Color(red: 0.06, green: 0.09, blue: 0.11), surface: Color(red: 0.09, green: 0.13, blue: 0.16), surfaceHover: Color(red: 0.12, green: 0.17, blue: 0.21),
        border: Color(red: 0.18, green: 0.24, blue: 0.28).opacity(0.4), text: Color(red: 0.70, green: 0.74, blue: 0.77), muted: Color(red: 0.36, green: 0.41, blue: 0.46),
        accent: Color(red: 1.0, green: 0.70, blue: 0.28), success: Color(red: 0.67, green: 0.85, blue: 0.38), danger: Color(red: 1.0, green: 0.44, blue: 0.37))
    static let light = ThemePalette(
        bg: Color(red: 0.97, green: 0.97, blue: 0.97), surface: Color.white, surfaceHover: Color(red: 0.94, green: 0.94, blue: 0.95),
        border: Color.black.opacity(0.08), text: Color(red: 0.13, green: 0.13, blue: 0.15), muted: Color.black.opacity(0.40),
        accent: Color(red: 0.20, green: 0.40, blue: 0.90), success: Color(red: 0.20, green: 0.65, blue: 0.32), danger: Color(red: 0.85, green: 0.25, blue: 0.25))
    static let rosePine = ThemePalette(
        bg: Color(red: 0.14, green: 0.13, blue: 0.19), surface: Color(red: 0.18, green: 0.17, blue: 0.24), surfaceHover: Color(red: 0.22, green: 0.20, blue: 0.28),
        border: Color(red: 0.29, green: 0.27, blue: 0.35).opacity(0.4), text: Color(red: 0.88, green: 0.85, blue: 0.87), muted: Color(red: 0.52, green: 0.49, blue: 0.56),
        accent: Color(red: 0.92, green: 0.60, blue: 0.64), success: Color(red: 0.62, green: 0.78, blue: 0.60), danger: Color(red: 0.92, green: 0.45, blue: 0.45))
}

// MARK: - Content View (Custom Sidebar)

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selected: SidebarItem = .media
    @State private var sidebarOpen = true
    @StateObject private var mediaVM = MediaExtractorVM()
    @StateObject private var accountVM = AccountManager()
    @StateObject private var csvVM = CSVDownloadManager()
    @StateObject private var logVM = LogStore()

    var body: some View {
        HStack(spacing: 0) {
            if sidebarOpen {
                sidebar
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(T.bg)
        }
        .background(T.bg)
        .preferredColorScheme(themeManager.isDark ? .dark : .light)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: sidebarOpen)
        .onAppear { csvVM.loadHistory(); AdBlocker.shared.compile() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation(.spring(duration: 0.3, bounce: 0.1)) { sidebarOpen.toggle() } } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 13)).foregroundStyle(T.muted)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 18)

            VStack(spacing: 2) {
                sidebarBtn("Media", "globe", .media)
                sidebarBtn("Connections", "link", .connections)
            }.padding(.horizontal, 10)

            Divider().padding(.vertical, 10).padding(.horizontal, 20).opacity(0.2)

            VStack(spacing: 2) {
                sidebarBtn("CSV Extractor", "tablecells", .csv)
                sidebarBtn("Documents", "doc.richtext", .documents)
            }.padding(.horizontal, 10)

            Divider().padding(.vertical, 10).padding(.horizontal, 20).opacity(0.2)

            VStack(spacing: 2) {
                sidebarBtn("Settings", "gearshape", .settings)
                sidebarBtn("Logs", "doc.text", .logs)
            }.padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("Media Extractor")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(T.muted.opacity(0.45))
                Text("v2.0")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(T.muted.opacity(0.25))
            }
            .padding(.horizontal, 18).padding(.bottom, 16)
        }
        .background(
            ZStack {
                VisualEffectBackground()
                (themeManager.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.5))
            }
        )
    }

    private func sidebarBtn(_ label: String, _ icon: String, _ item: SidebarItem) -> some View {
        SidebarButton(label: label, icon: icon, isSelected: selected == item) {
            withAnimation(.easeInOut(duration: 0.12)) { selected = item }
        }
    }

    @ViewBuilder private var detailView: some View {
        switch selected {
        case .media: MediaView(vm: mediaVM, accounts: accountVM, logs: logVM)
        case .connections: ConnectionsView(vm: accountVM, logs: logVM)
        case .csv: CSVExtractView(manager: csvVM, logs: logVM)
        case .documents: DocumentsView(logs: logVM)
        case .settings: SettingsView(mediaVM: mediaVM, logs: logVM)
        case .logs: LogsView(vm: logVM)
        }
    }
}

// MARK: - Media View (Link Downloader)

struct MediaView: View {
    @ObservedObject var vm: MediaExtractorVM
    @ObservedObject var accounts: AccountManager
    @ObservedObject var logs: LogStore
    @State private var showPreview = false
    @State private var downloadPulse = false
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                urlInput
                if let warning = vm.longDownloadWarning, !vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 13)).foregroundStyle(T.accent)
                        Text(warning).font(.system(.caption, design: .rounded)).foregroundStyle(T.accent.opacity(0.8))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(T.accent.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.accent.opacity(0.1))))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeOut(duration: 0.2), value: vm.longDownloadWarning != nil)
                }
                if showPreview && !vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    previewSection
                }
                formatSection
                downloadArea
                if !vm.history.isEmpty { historySection }
            }
            .padding(32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Media Downloader")
                .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)
            Text("Paste any media link to download")
                .font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var urlInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(T.muted).font(.system(size: 14))
                TextField("Paste URL here...", text: $vm.urlInput)
                    .textFieldStyle(.plain).font(.system(.body, design: .monospaced))
                    .foregroundStyle(T.text)
                    .onChange(of: vm.urlInput) { _, val in
                        vm.detectedPlatform = Platform.detect(from: val)
                        showPreview = !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                if let p = vm.detectedPlatform {
                    HStack(spacing: 4) {
                        Image(systemName: p.icon).font(.system(size: 10))
                        Text(p.rawValue).font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(T.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(T.accent.opacity(0.12)))
                }
                if !vm.urlInput.isEmpty {
                    Button { vm.urlInput = ""; showPreview = false; showSuccess = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(T.muted)
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(T.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
        }
    }

    @State private var previewHeight: CGFloat = 400

    private var previewSection: some View {
        VStack(spacing: 8) {
            AdBlockPreviewWebView(urlString: vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines))
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border))

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(T.muted.opacity(0.5))
                    Slider(value: $previewHeight, in: 200...700, step: 10)
                        .frame(width: 100).controlSize(.mini).tint(T.accent)
                }
                Spacer()
                if let url = URL(string: vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Button {
                        if let brave = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.brave.Browser") {
                            NSWorkspace.shared.open([url], withApplicationAt: brave, configuration: .init(), completionHandler: nil)
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                            Text("Open in Browser").font(.system(.caption2, design: .rounded).weight(.medium))
                        }
                        .foregroundStyle(T.muted).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(T.surface).overlay(Capsule().strokeBorder(T.border)))
                    }.buttonStyle(.plain).pointer()
                }
            }
        }
    }

    private var formatSection: some View {
        HStack(spacing: 12) {
            fmtCard("Video", "film") {
                row("Format") { Picker("", selection: $vm.vidFormat) { ForEach(VidFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 75) }
                row("Quality") { Picker("", selection: $vm.quality) { ForEach(QualityPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 75) }
            }
            fmtCard("Audio", "music.note") {
                row("Format") { Picker("", selection: $vm.audFormat) { ForEach(AudFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 70) }
                row("Bitrate") { Picker("", selection: $vm.audBitrate) { ForEach(AudBitrate.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 80) }
            }
        }
    }

    private func fmtCard<C: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(T.accent)
                Text(title).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(T.text.opacity(0.7))
            }
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
    }

    private func row<C: View>(_ label: String, @ViewBuilder c: () -> C) -> some View {
        HStack { Text(label).font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted); Spacer(); c().pickerStyle(.menu) }
    }

    private var downloadArea: some View {
        VStack(spacing: 10) {
            Button {
                let cookies = vm.detectedPlatform.flatMap { p in accounts.accounts.first { $0.platform == p } }.flatMap { accounts.getCookies(forAccount: $0.id) }
                downloadPulse = true; showSuccess = false
                Task {
                    await vm.download(cookies: cookies)
                    downloadPulse = false
                    if let last = vm.history.first {
                        logs.log(last.status == .complete ? "info" : "error",
                                 "\(last.status == .complete ? "Downloaded" : "Failed"): \(last.title)",
                                 detail: last.error ?? last.filePath)
                        if last.status == .complete {
                            withAnimation(.spring(duration: 0.4)) { showSuccess = true }
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { showSuccess = false }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if vm.isDownloading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else if showSuccess {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 16))
                    }
                    Text(vm.isDownloading ? "Downloading..." : showSuccess ? "Downloaded!" : "Download")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(
                        showSuccess ? T.success :
                        canDownload ? T.accent : Color.gray.opacity(0.3)
                    )
                )
                .scaleEffect(downloadPulse ? 0.97 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: downloadPulse)
            }
            .buttonStyle(.plain).disabled(!canDownload).pointer(scale: 1.01)
        }
    }

    private var canDownload: Bool {
        !vm.isDownloading && !vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Download History").font(.system(.subheadline, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                Text("\(vm.history.count)").font(.system(.caption2, design: .rounded).weight(.bold)).foregroundStyle(T.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(T.surface))
                Spacer()
                if !vm.history.isEmpty {
                    Button { withAnimation { vm.history.removeAll() } } label: {
                        Text("Clear All").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted.opacity(0.5))
                    }.buttonStyle(.plain).pointer()
                }
            }
            ForEach(vm.history) { rec in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(T.surface).frame(width: 44, height: 44)
                            if let p = rec.platform {
                                Image(systemName: platformIcon(p)).font(.system(size: 18)).foregroundStyle(T.accent.opacity(0.6))
                            } else {
                                Image(systemName: "link").font(.system(size: 16)).foregroundStyle(T.muted)
                            }
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    statusDot(rec.status).frame(width: 10, height: 10).offset(x: 2, y: 2)
                                }
                            }.frame(width: 44, height: 44)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Button {
                                if let url = URL(string: rec.url) { NSWorkspace.shared.open(url) }
                            } label: {
                                Text(rec.url)
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundStyle(T.accent)
                                    .lineLimit(1).truncationMode(.middle)
                            }.buttonStyle(.plain).pointer()

                            HStack(spacing: 8) {
                                if let p = rec.platform {
                                    Text(p.rawValue).font(.system(.caption2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(T.text.opacity(0.5))
                                }
                                Label(rec.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                    .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                                if rec.fileSize > 0 {
                                    Label(formatBytes(rec.fileSize), systemImage: "doc").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                                }
                                statusLabel(rec.status)
                            }
                            if let e = rec.error {
                                Text(e).font(.system(.caption2, design: .rounded)).foregroundStyle(T.danger.opacity(0.7)).lineLimit(1)
                            }
                        }
                        Spacer()

                        VStack(spacing: 4) {
                            if rec.status == .downloading {
                                ProgressView().controlSize(.mini).tint(T.accent)
                                Button { vm.cancelDownload(id: rec.id) } label: {
                                    Image(systemName: "xmark.circle").font(.system(size: 13)).foregroundStyle(T.danger.opacity(0.7))
                                }.buttonStyle(.plain).pointer()
                            }
                            if rec.status == .failed || rec.status == .cancelled {
                                Button {
                                    let cookies = rec.platform.flatMap { p in accounts.accounts.first { $0.platform == p } }.flatMap { accounts.getCookies(forAccount: $0.id) }
                                    vm.retryDownload(id: rec.id, cookies: cookies)
                                } label: {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundStyle(T.accent)
                                }.buttonStyle(.plain).pointer()
                            }
                            if rec.status == .complete, let path = rec.filePath {
                                Button { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") } label: {
                                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(T.muted)
                                }.buttonStyle(.plain).pointer()
                            }
                        }
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
    }

    private func platformIcon(_ p: Platform) -> String {
        switch p {
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .twitter: return "bubble.left.fill"
        case .youtube: return "play.rectangle.fill"
        case .soundcloud: return "waveform"
        case .rednote: return "doc.text.fill"
        case .spotify: return "headphones"
        }
    }

    @ViewBuilder private func statusDot(_ s: DLStatus) -> some View {
        Circle().fill(s == .complete ? T.success : s == .failed ? T.danger : s == .cancelled ? T.muted : T.accent)
    }

    @ViewBuilder private func statusLabel(_ s: DLStatus) -> some View {
        switch s {
        case .complete: Text("Completed").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(T.success)
        case .failed: Text("Failed").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(T.danger)
        case .cancelled: Text("Cancelled").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(T.muted)
        case .downloading: Text("Downloading...").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(T.accent)
        }
    }

}

// MARK: - Connections View (Accordion)

struct ConnectionsView: View {
    @ObservedObject var vm: AccountManager
    @ObservedObject var logs: LogStore
    @State private var expandedPlatform: Platform?
    @State private var loginPlatform: Platform?
    @State private var browsePlatform: (Platform, UUID)?

    var body: some View {
        if let (platform, accountId) = browsePlatform {
            PlatformBrowserView(platform: platform, cookies: vm.getCookies(forAccount: accountId) ?? [],
                                logs: logs, onClose: { browsePlatform = nil })
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    platformCards
                }
                .padding(32)
            }
            .sheet(item: $loginPlatform) { platform in
                LoginSheet(platform: platform) { account, cookies in
                    vm.addAccount(account, cookies: cookies)
                    logs.log("info", "Connected \(platform.rawValue) account: \(account.displayName)")
                    loginPlatform = nil
                } onCancel: { loginPlatform = nil }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connections").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)
            Text("Connect accounts to browse and download authenticated content")
                .font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 10)).foregroundStyle(T.muted.opacity(0.5))
                Text("Login cookies are stored securely in your macOS Keychain. You may see a system prompt asking for your password — this is normal. Click \"Always Allow\" so it won't ask again.")
                    .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted.opacity(0.6))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.border)))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var platformCards: some View {
        VStack(spacing: 8) {
            ForEach(Platform.allCases) { platform in
                let accs = vm.accounts.filter { $0.platform == platform }
                let isExpanded = expandedPlatform == platform

                VStack(spacing: 0) {
                    // Card header (always visible)
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            expandedPlatform = isExpanded ? nil : platform
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: platform.icon)
                                .font(.system(size: 18)).foregroundStyle(T.accent)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(T.accent.opacity(0.08)))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(platform.rawValue)
                                    .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                                Text(accs.isEmpty ? "No accounts connected" : "\(accs.count) account\(accs.count > 1 ? "s" : "") connected")
                                    .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                            }

                            Spacer()

                            if !accs.isEmpty {
                                Circle().fill(T.success).frame(width: 8, height: 8)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                                .rotationEffect(isExpanded ? .degrees(90) : .zero)
                                .animation(.spring(duration: 0.25), value: isExpanded)
                        }
                        .padding(16)
                    }.buttonStyle(.plain).pointer()

                    // Expanded section
                    if isExpanded {
                        Divider().padding(.horizontal, 16).opacity(0.2)

                        VStack(spacing: 6) {
                            ForEach(accs) { acc in
                                HStack(spacing: 10) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 22)).foregroundStyle(T.accent.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(acc.displayName)
                                            .font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                                        Text("Connected " + acc.connectedDate.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                                    }
                                    Spacer()
                                    Button {
                                        browsePlatform = (platform, acc.id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "globe").font(.system(size: 10))
                                            Text("Browse")
                                        }
                                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(T.accent).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(T.accent.opacity(0.1)))
                                    }.buttonStyle(.plain).pointer()
                                    Button { vm.removeAccount(acc.id); logs.log("info", "Disconnected \(platform.rawValue): \(acc.displayName)") } label: {
                                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(T.danger.opacity(0.4))
                                    }.buttonStyle(.plain).pointer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
                            }

                            Button { loginPlatform = platform } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 14))
                                    Text("Add Account").font(.system(.caption, design: .rounded).weight(.semibold))
                                }
                                .foregroundStyle(T.accent).frame(maxWidth: .infinity).padding(.vertical, 10)
                            }.buttonStyle(.plain).pointer(scale: 1.03)
                        }
                        .padding(.vertical, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(T.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                        isExpanded ? T.accent.opacity(0.15) : T.border
                    )))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Login Sheet

struct LoginSheet: View {
    let platform: Platform
    let onSuccess: (ConnectedAccount, [HTTPCookie]) -> Void
    let onCancel: () -> Void
    @State private var displayName = ""
    @State private var loggedIn = false
    @State private var capturedCookies: [HTTPCookie] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connect to \(platform.rawValue)").font(.system(.headline, design: .rounded)).foregroundStyle(T.text)
                Spacer()
                if loggedIn {
                    HStack(spacing: 6) {
                        TextField("Display name", text: $displayName).textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded)).foregroundStyle(T.text).frame(width: 140)
                            .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
                        Button("Save") {
                            let name = displayName.isEmpty ? platform.rawValue : displayName
                            let acc = ConnectedAccount(id: UUID(), platform: platform, displayName: name, connectedDate: Date())
                            onSuccess(acc, capturedCookies)
                        }
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(T.success)).buttonStyle(.plain)
                    }
                }
                Button("Cancel") { onCancel() }
                    .font(.system(.caption, design: .rounded)).foregroundStyle(T.muted).buttonStyle(.plain)
            }
            .padding(16)

            if loggedIn {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(T.success)
                    Text("Logged in! Enter a display name and click Save.").foregroundStyle(T.success)
                }.font(.system(.caption, design: .rounded)).padding(.bottom, 8)
            }

            LoginWebView(platform: platform) { cookies in
                capturedCookies = cookies
                loggedIn = true
                displayName = platform.rawValue
            }
        }
        .frame(width: 700, height: 600)
        .background(T.bg)
    }
}

// MARK: - Platform Browser View

struct PlatformBrowserView: View {
    let platform: Platform
    let cookies: [HTTPCookie]
    @ObservedObject var logs: LogStore
    let onClose: () -> Void
    @State private var currentURL = ""
    @State private var isDownloading = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(T.muted)
                }.buttonStyle(.plain)
                Image(systemName: platform.icon).foregroundStyle(T.accent)
                Text(platform.rawValue).font(.system(.headline, design: .rounded)).foregroundStyle(T.text)
                Spacer()
                Text(currentURL).font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted).lineLimit(1).frame(maxWidth: 300, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(T.surface)

            BrowseWebView(url: platform.baseURL, cookies: cookies, currentURL: $currentURL)

            HStack(spacing: 12) {
                if isDownloading {
                    ProgressView().controlSize(.small).tint(T.accent)
                    Text("Downloading...").font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
                } else if let t = toast {
                    Image(systemName: t.hasPrefix("Failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.hasPrefix("Failed") ? T.danger : T.success)
                    Text(t).font(.system(.caption, design: .rounded)).foregroundStyle(t.hasPrefix("Failed") ? T.danger : T.success)
                }
                Spacer()
                Button {
                    guard !currentURL.isEmpty, !isDownloading else { return }
                    isDownloading = true; toast = nil
                    Task {
                        let result = await MediaExtractorVM.downloadURL(currentURL, cookies: cookies, to: dlFolder())
                        isDownloading = false
                        if result.ok {
                            toast = "Downloaded! \(formatBytes(result.bytes))"
                            logs.log("info", "Browser download: \(currentURL)", detail: result.ext)
                        } else {
                            toast = "Failed: \(result.error ?? "Unknown")"
                            logs.log("error", "Browser download failed: \(currentURL)", detail: result.error)
                        }
                        try? await Task.sleep(for: .seconds(4)); toast = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download This Page")
                    }
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(isDownloading ? Color.gray.opacity(0.3) : T.accent))
                }.buttonStyle(.plain).disabled(isDownloading)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(T.surface)
        }
    }

    private func dlFolder() -> URL {
        let f = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor")
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true); return f
    }
}

// MARK: - CSV Extract View (Restyled)

struct CSVExtractView: View {
    @ObservedObject var manager: CSVDownloadManager
    @ObservedObject var logs: LogStore
    @State private var tab: Int = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CSV Extractor").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)
                Spacer()
                Picker("", selection: $tab) { Text("Extract").tag(0); Text("History").tag(1) }
                    .pickerStyle(.segmented).frame(width: 180)
            }.padding(24).padding(.bottom, 0)
            if tab == 0 { csvExtractBody } else { csvHistoryBody }
        }
    }

    private var csvExtractBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                csvSection; folderSection; keywordSection; photoFormatSection
                if manager.phase == .downloading { progressSection }
                if case .complete = manager.phase, let r = manager.lastResult { resultSection(r) }
                Spacer(minLength: 0); csvButtons
            }.padding(24)
        }
    }

    private var csvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CSV Files").font(.system(.subheadline, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                if !manager.csvFiles.isEmpty {
                    Text("\(manager.csvFiles.count)").font(.system(.caption2, design: .rounded).weight(.bold)).foregroundStyle(T.muted)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(T.surface))
                }
                Spacer()
                if !manager.csvFiles.isEmpty { Button("Add More") { manager.chooseCSVFiles() }.font(.system(.caption, design: .rounded)).controlSize(.small) }
            }
            if manager.csvFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 28, weight: .light)).foregroundStyle(T.muted)
                    Text("Drop CSV files here").font(.system(.body, design: .rounded)).foregroundStyle(T.muted)
                    Text("or click to browse").font(.system(.caption, design: .rounded)).foregroundStyle(T.muted.opacity(0.5))
                }
                .frame(maxWidth: .infinity).frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(T.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))))
                .contentShape(Rectangle()).onTapGesture { manager.chooseCSVFiles() }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
            } else {
                VStack(spacing: 4) {
                    ForEach(manager.csvFiles) { csv in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill").font(.system(size: 13)).foregroundStyle(T.accent)
                            Text(csv.filename).font(.system(.caption, design: .monospaced)).foregroundStyle(T.text.opacity(0.8)).lineLimit(1)
                            Spacer()
                            if let st = manager.csvStatuses[csv.id] { csvBadge(st) }
                            else { Text("\(csv.urlCount) URLs").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(T.success)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(T.success.opacity(0.1))) }
                            Button { manager.removeCSV(id: csv.id) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.muted)
                            }.buttonStyle(.plain)
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(T.surface))
                    }
                }.onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
            }
        }
    }

    @ViewBuilder private func csvBadge(_ status: ExtractionStatus) -> some View {
        switch status {
        case .pending: Text("pending").font(.system(.caption2)).foregroundStyle(T.muted)
        case .inProgress(let d, let t):
            Text("\(d)/\(t)").font(.system(.caption2, design: .monospaced).weight(.semibold)).foregroundStyle(T.accent)
                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(T.accent.opacity(0.1)))
        case .complete(let s, let f):
            HStack(spacing: 3) {
                Text("\(s) OK").foregroundStyle(T.success)
                if f > 0 { Text("\(f) err").foregroundStyle(T.danger) }
            }.font(.system(.caption2, design: .rounded).weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(T.success.opacity(0.08)))
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output Folder").font(.system(.subheadline, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(T.muted)
                    Text(manager.baseFolder?.path(percentEncoded: false) ?? "No folder selected")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(T.text.opacity(manager.baseFolder != nil ? 0.6 : 0.3)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(T.surface))
                Button("Choose") { manager.chooseBaseFolder() }.controlSize(.small)
            }
        }
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Filter Keywords").font(.system(.subheadline, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                Spacer()
                Picker("", selection: Binding(get: { manager.keywordMode }, set: { manager.setKeywordMode($0) })) {
                    Text("Same for all").tag(KeywordMode.global); Text("Per CSV").tag(KeywordMode.perCSV)
                }.pickerStyle(.segmented).frame(width: 180)
            }
            if manager.keywordMode == .global {
                KWEditor(keywords: $manager.globalKeywords, onChanged: manager.reparseAll)
            }
        }
    }

    private var photoFormatSection: some View {
        HStack(spacing: 6) {
            Text("Photo Format").font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
            Picker("", selection: $manager.photoFormat) {
                ForEach(PhotoFmt.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).frame(width: 90)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressBar(progress: manager.totalFiles > 0 ? Double(manager.completedFiles + manager.failedFiles) / Double(manager.totalFiles) : 0,
                        label: "\(manager.completedFiles + manager.failedFiles) / \(manager.totalFiles)")
            HStack {
                Text(formatBytes(manager.bytesDownloaded)); Spacer()
                if manager.failedFiles > 0 { Text("\(manager.failedFiles) failed").foregroundStyle(T.danger) }
                Spacer(); Text(formatSpeed(manager.currentSpeed))
            }.font(.system(.caption, design: .monospaced)).foregroundStyle(T.muted)
        }.padding(14).background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
    }

    private func resultSection(_ r: SessionRecord) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(T.success)
                Text("Complete").font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                Spacer()
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: r.baseFolderPath).appendingPathComponent(r.sessionName)) } label: {
                    HStack(spacing: 4) { Image(systemName: "folder"); Text("Open") }.font(.system(.caption, design: .rounded))
                }.controlSize(.small)
            }
            HStack(spacing: 0) {
                stat("\(r.totalSuccess)", "OK", T.success); Spacer()
                stat("\(r.totalFailed)", "Failed", r.totalFailed > 0 ? T.danger : T.muted); Spacer()
                stat(formatBytes(r.totalBytes), "Size", T.accent); Spacer()
                stat(String(format: "%.1fs", r.duration), "Time", T.text.opacity(0.6))
            }
            ForEach(r.extractions, id: \.csvFilename) { e in
                HStack {
                    Text(e.folderName).font(.system(.caption, design: .rounded)).foregroundStyle(T.text.opacity(0.6))
                    Spacer()
                    ForEach(e.typeBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in
                        Text("\(k) \(v)").font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(T.surface))
                    }
                }
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.success.opacity(0.15))))
    }

    private var csvButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await manager.startExtraction()
                    if let r = manager.lastResult { logs.log("info", "CSV extraction: \(r.totalSuccess) files, \(formatBytes(r.totalBytes))") }
                }
            } label: {
                Text(manager.phase == .downloading ? "Downloading..." : "Extract Media")
                    .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 10).fill(csvCanExtract ? T.accent : Color.gray.opacity(0.3)))
            }.buttonStyle(.plain).disabled(!csvCanExtract).pointer(scale: 1.01)

            if case .complete = manager.phase, let r = manager.lastResult {
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: r.baseFolderPath).appendingPathComponent(r.sessionName)) } label: {
                    HStack(spacing: 6) { Image(systemName: "folder.fill"); Text("Open Folder") }
                        .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 10).fill(T.success.opacity(0.7)))
                }.buttonStyle(.plain).pointer(scale: 1.02)
            }
        }
    }

    private var csvCanExtract: Bool {
        manager.phase != .downloading && manager.baseFolder != nil && manager.csvFiles.contains { $0.urlCount > 0 }
    }

    private var csvHistoryBody: some View {
        ScrollView {
            VStack(spacing: 10) {
                if manager.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 32, weight: .light)).foregroundStyle(T.muted)
                        Text("No sessions yet").font(.system(.body, design: .rounded)).foregroundStyle(T.muted)
                    }.frame(maxWidth: .infinity).frame(height: 180)
                } else {
                    ForEach(manager.sessions) { s in
                        CSVSessionRow(session: s) { manager.deleteSession(id: s.id) }
                    }
                }
            }.padding(24)
        }
    }

    private func stat(_ val: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(val).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color)
            Text(label).font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
        }.frame(minWidth: 50)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier as String, options: nil) { item, _ in
                guard let d = item as? Data, let url = URL(dataRepresentation: d, relativeTo: nil, isAbsolute: true),
                      url.pathExtension.lowercased() == "csv" else { return }
                DispatchQueue.main.async { manager.addCSVFile(url: url) }
            }
        }
        return true
    }
}

struct CSVSessionRow: View {
    let session: SessionRecord; let onDelete: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionName).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                    Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                }
                Spacer()
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: session.baseFolderPath).appendingPathComponent(session.sessionName)) } label: {
                    Image(systemName: "folder").font(.system(.caption))
                }.controlSize(.small)
            }
            HStack(spacing: 14) {
                miniStat("\(session.totalSuccess)", "files", T.success)
                miniStat(formatBytes(session.totalBytes), "size", T.accent)
                miniStat(String(format: "%.1fs", session.duration), "time", T.text.opacity(0.5))
                if session.totalFailed > 0 { miniStat("\(session.totalFailed)", "failed", T.danger) }
            }
            if expanded {
                Divider().background(T.border)
                ForEach(session.extractions, id: \.csvFilename) { e in
                    Text("\(e.folderName): \(e.success) OK").font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted)
                }
                HStack { Spacer(); Button(role: .destructive) { onDelete() } label: { Text("Delete").foregroundStyle(T.danger) }.controlSize(.small) }
            }
            Button { withAnimation { expanded.toggle() } } label: {
                Text(expanded ? "Hide" : "Details").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
            }.buttonStyle(.plain)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
    }
    func miniStat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) { Text(v).font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(c)
            Text(l).font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted) }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var mediaVM: MediaExtractorVM
    @ObservedObject var logs: LogStore
    @ObservedObject var themeManager: ThemeManager = ThemeManager.shared
    @State private var dlFolder: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor").path
    @State private var encryptDownloads = false
    @State private var encryptionPassword = ""
    @State private var userName: String = NSFullUserName()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [T.accent.opacity(0.3), T.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 52, height: 52)
                            Text(String(userName.prefix(1)).uppercased())
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(T.text)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(userName).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                            Text("Media Extractor v2.0").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(mediaVM.history.count) downloads").font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
                            let totalBytes = mediaVM.history.reduce(Int64(0)) { $0 + $1.fileSize }
                            Text(formatBytes(totalBytes) + " total").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted.opacity(0.6))
                        }
                    }

                    Divider().background(T.border)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "paintpalette").font(.system(size: 11)).foregroundStyle(T.muted)
                            Text("Theme").font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(AppTheme.allCases) { theme in
                                let pal = themePalette(theme)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { themeManager.current = theme }
                                } label: {
                                    VStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 6).fill(pal.bg)
                                            .frame(height: 32)
                                            .overlay(
                                                HStack(spacing: 2) {
                                                    Circle().fill(pal.accent).frame(width: 6, height: 6)
                                                    Circle().fill(pal.success).frame(width: 6, height: 6)
                                                    Circle().fill(pal.danger).frame(width: 6, height: 6)
                                                    RoundedRectangle(cornerRadius: 2).fill(pal.surface).frame(width: 18, height: 4)
                                                }
                                            )
                                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                                themeManager.current == theme ? T.accent : T.border, lineWidth: themeManager.current == theme ? 1.5 : 0.5))
                                        Text(theme.rawValue)
                                            .font(.system(.caption2, design: .rounded).weight(themeManager.current == theme ? .bold : .regular))
                                            .foregroundStyle(themeManager.current == theme ? T.accent : T.muted)
                                            .lineLimit(1)
                                    }
                                }.buttonStyle(.plain).pointer()
                            }
                        }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))

                settingCard("Download Folder", info: "Where your downloaded files are saved. Pick any folder on your Mac — all media downloads go here.") {
                    HStack {
                        Text(dlFolder).font(.system(.caption, design: .monospaced)).foregroundStyle(T.text.opacity(0.6)).lineLimit(1)
                        Spacer()
                        Button("Change") {
                            let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
                            if p.runModal() == NSApplication.ModalResponse.OK, let url = p.url { dlFolder = url.path; mediaVM.downloadFolder = url }
                        }.controlSize(.small)
                    }
                }

                settingCard("Default Formats", info: "The file type and quality used when downloading. MP4 is the most compatible video format. 'Best' quality gets the highest resolution available. MP3 at 320k gives near-CD audio quality.") {
                    VStack(spacing: 10) {
                        HStack(spacing: 20) {
                            settingRow("Video Format", Picker("", selection: $mediaVM.vidFormat) { ForEach(VidFormat.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 75))
                            settingRow("Video Quality", Picker("", selection: $mediaVM.quality) { ForEach(QualityPreset.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 75))
                        }
                        HStack(spacing: 20) {
                            settingRow("Audio Format", Picker("", selection: $mediaVM.audFormat) { ForEach(AudFormat.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 75))
                            settingRow("Audio Bitrate", Picker("", selection: $mediaVM.audBitrate) { ForEach(AudBitrate.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 80))
                        }
                    }.pickerStyle(.menu)
                }

                settingCard("yt-dlp", info: "The download engine that powers video/audio downloads. It's a free tool that must be installed separately. If it says 'Not found', click Install below or open Terminal and type: brew install yt-dlp") {
                    let path = MediaExtractorVM.findYtdlp()
                    if path.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundStyle(T.danger)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("yt-dlp is not installed").font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(T.danger)
                                    Text("Required for downloading videos and audio from URLs.")
                                        .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                                }
                            }
                            Button {
                                let proc = Process()
                                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                                proc.arguments = ["-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && brew install yt-dlp"]
                                proc.standardOutput = Pipe(); proc.standardError = Pipe()
                                try? proc.run()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle").font(.system(size: 12))
                                    Text("Install yt-dlp").font(.system(.caption, design: .rounded).weight(.semibold))
                                }
                                .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(T.accent))
                            }.buttonStyle(.plain).pointer()
                            Text("Requires Homebrew. If you don't have Homebrew, visit brew.sh first.")
                                .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted.opacity(0.6))
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(T.success)
                            Text(path).font(.system(.caption, design: .monospaced)).foregroundStyle(T.success)
                        }
                    }
                }

                settingCard("Encryption", info: "Protects your downloaded files with a password. Uses AES-256-GCM — the same standard banks use. When turned on, files are scrambled so only someone with your password can open them. Your password is stored safely in macOS Keychain.") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Toggle("Encrypt downloaded files", isOn: $encryptDownloads)
                                .font(.system(.caption, design: .rounded)).foregroundStyle(T.text.opacity(0.7))
                                .toggleStyle(.switch).controlSize(.small)
                        }
                        if encryptDownloads {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(T.accent)
                                SecureField("Encryption password", text: $encryptionPassword)
                                    .textFieldStyle(.plain).font(.system(.caption, design: .monospaced)).foregroundStyle(T.text)
                                    .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
                            }
                            Text("AES-256-GCM encryption. Credentials are stored securely in macOS Keychain.")
                                .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                        } else {
                            Text("Session cookies are encrypted via macOS Keychain by default.")
                                .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                        }
                    }
                }

                settingCard("Performance", info: "Fine-tune download speed vs resource usage. More fragments = faster downloads but more CPU. Increase chunk size for large files. Set process priority to control how aggressively downloads compete for system resources.") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 20) {
                            settingRow("Threads", Picker("", selection: $mediaVM.concurrentFragments) {
                                ForEach([1, 2, 4, 8, 12, 16], id: \.self) { Text("\($0)") }
                            }.frame(width: 60).onChange(of: mediaVM.concurrentFragments) { _ in mediaVM.savePerformanceSettings() })
                            settingRow("Chunk Size", Picker("", selection: $mediaVM.chunkSizeMB) {
                                ForEach([5, 10, 25, 50, 100], id: \.self) { Text("\($0) MB") }
                            }.frame(width: 80).onChange(of: mediaVM.chunkSizeMB) { _ in mediaVM.savePerformanceSettings() })
                        }.pickerStyle(.menu)
                        HStack(spacing: 20) {
                            settingRow("CPU Cores", Picker("", selection: $mediaVM.maxCPUCores) {
                                ForEach(Array(1...ProcessInfo.processInfo.activeProcessorCount), id: \.self) { Text("\($0)") }
                            }.frame(width: 60).onChange(of: mediaVM.maxCPUCores) { _ in mediaVM.savePerformanceSettings() })
                            settingRow("RAM Limit", Picker("", selection: $mediaVM.maxRAMMB) {
                                ForEach([256, 512, 1024, 2048, 4096], id: \.self) { Text("\($0) MB") }
                            }.frame(width: 80).onChange(of: mediaVM.maxRAMMB) { _ in mediaVM.savePerformanceSettings() })
                        }.pickerStyle(.menu)
                        HStack(spacing: 6) {
                            settingRow("Priority", Picker("", selection: $mediaVM.processPriority) {
                                ForEach(ProcessPriorityLevel.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                            }.frame(width: 80).onChange(of: mediaVM.processPriority) { _ in mediaVM.savePerformanceSettings() })
                        }.pickerStyle(.menu)
                        Text("Higher thread count and chunk size = faster downloads. Lower priority = less system impact.")
                            .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted.opacity(0.6))
                    }
                }

                settingCard("Export as ZIP", info: "Bundles all your downloads into a single .zip file. Useful for sending files to someone, making a backup, or moving them to another computer.") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Package your download folder into a ZIP archive for sharing or backup.")
                            .font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                        Button {
                            let src = mediaVM.downloadFolder
                            let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
                            panel.nameFieldStringValue = "MediaExtractor_\(Date().formatted(.dateTime.year().month().day())).zip"
                            guard panel.runModal() == NSApplication.ModalResponse.OK, let dest = panel.url else { return }
                            let proc = Process()
                            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                            proc.arguments = ["-c", "-k", "--sequesterRsrc", src.path, dest.path]
                            proc.standardOutput = Pipe(); proc.standardError = Pipe()
                            try? proc.run(); proc.waitUntilExit()
                            if proc.terminationStatus == 0 {
                                NSWorkspace.shared.selectFile(dest.path, inFileViewerRootedAtPath: "")
                                logs.log("info", "Exported ZIP: \(dest.lastPathComponent)")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox").font(.system(size: 12))
                                Text("Create ZIP Archive").font(.system(.caption, design: .rounded).weight(.semibold))
                            }
                            .foregroundStyle(T.accent).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(T.accent.opacity(0.1)))
                        }.buttonStyle(.plain).pointer()
                    }
                }

                settingCard("Data", info: "Clear your logs or download history. This doesn't delete any actual downloaded files — just the records shown in the app.") {
                    HStack(spacing: 12) {
                        Button("Clear Logs") { logs.clear() }.controlSize(.small).pointer()
                        Button("Clear Download History") { mediaVM.history.removeAll() }.controlSize(.small).pointer()
                    }
                }
            }.padding(32)
        }
    }

    private func settingCard<C: View>(_ title: String, info: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(.subheadline, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                if let info {
                    InfoButton(text: info)
                }
            }
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.surface).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.border)))
    }

    private func settingRow<C: View>(_ label: String, _ content: C) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(.caption, design: .rounded)).foregroundStyle(T.muted).fixedSize()
            content
        }
    }

    private func themePalette(_ theme: AppTheme) -> ThemePalette {
        switch theme {
        case .midnight: return .midnight; case .dracula: return .dracula; case .catppuccin: return .catppuccin
        case .oneDark: return .oneDark; case .nord: return .nord; case .ayu: return .ayu
        case .light: return .light; case .rosePine: return .rosePine
        }
    }
}

// MARK: - Documents View (PDF / EPUB Reader)

struct DocumentsView: View {
    @ObservedObject var logs: LogStore
    @StateObject private var docVM = DocumentVM()
    @State private var showingFilePicker = false

    var body: some View {
        HStack(spacing: 0) {
            if docVM.currentDocument == nil {
                emptyState
            } else {
                readerView
            }
        }
        .background(T.bg)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf, .epub], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { docVM.openDocument(url: url) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text("Documents").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)
            Text("Read PDFs and EPUBs with a fast, minimal viewer")
                .font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)

            VStack(spacing: 12) {
                Button { showingFilePicker = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus").font(.system(size: 28)).foregroundStyle(T.accent)
                        Text("Open Document").font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(T.text)
                        Text("PDF, EPUB").font(.system(.caption2, design: .rounded)).foregroundStyle(T.muted)
                    }
                    .frame(maxWidth: 280).padding(28)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(T.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))))
                }.buttonStyle(.plain).pointer()
            }

            if !docVM.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent").font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(T.muted)
                    ForEach(docVM.recentFiles, id: \.self) { path in
                        Button {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: path) { docVM.openDocument(url: url) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: path.hasSuffix(".pdf") ? "doc.fill" : "book.fill")
                                    .font(.system(size: 11)).foregroundStyle(T.accent)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(.caption, design: .rounded)).foregroundStyle(T.text).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
                        }.buttonStyle(.plain).pointer()
                    }
                }.frame(maxWidth: 280, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readerView: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider().background(T.border)
            if docVM.isPDF {
                PDFReaderView(url: docVM.documentURL!, viewModel: docVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EPUBReaderView(url: docVM.documentURL!, viewModel: docVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            readerBottomBar
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 12) {
            Button { docVM.closeDocument() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Library").font(.system(.caption, design: .rounded).weight(.medium))
                }.foregroundStyle(T.accent)
            }.buttonStyle(.plain).pointer()

            Divider().frame(height: 16)

            Text(docVM.documentTitle).font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(T.text).lineLimit(1)
            Spacer()

            HStack(spacing: 8) {
                Button { docVM.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass").font(.system(size: 12)).foregroundStyle(T.muted)
                }.buttonStyle(.plain).pointer()
                Text("\(Int(docVM.zoomLevel * 100))%").font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted).frame(width: 40)
                Button { docVM.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass").font(.system(size: 12)).foregroundStyle(T.muted)
                }.buttonStyle(.plain).pointer()
            }

            Divider().frame(height: 16)

            Button { docVM.toggleDarkReading() } label: {
                Image(systemName: docVM.darkReading ? "sun.max" : "moon")
                    .font(.system(size: 12)).foregroundStyle(docVM.darkReading ? T.accent : T.muted)
            }.buttonStyle(.plain).pointer()

            Button { showingFilePicker = true } label: {
                Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(T.muted)
            }.buttonStyle(.plain).pointer()

            if docVM.isPDF {
                Button { docVM.toggleTOC() } label: {
                    Image(systemName: "list.bullet").font(.system(size: 12))
                        .foregroundStyle(docVM.showTOC ? T.accent : T.muted)
                }.buttonStyle(.plain).pointer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(T.surface)
    }

    private var readerBottomBar: some View {
        HStack(spacing: 12) {
            if docVM.totalPages > 0 {
                Button { docVM.previousPage() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10)).foregroundStyle(T.muted)
                }.buttonStyle(.plain).pointer().disabled(docVM.currentPage <= 1)

                Text("Page \(docVM.currentPage) of \(docVM.totalPages)")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted)

                Slider(value: Binding(
                    get: { Double(docVM.currentPage) },
                    set: { docVM.goToPage(Int($0)) }
                ), in: 1...Double(max(1, docVM.totalPages)), step: 1)
                    .frame(maxWidth: 200).controlSize(.mini).tint(T.accent)

                Button { docVM.nextPage() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(T.muted)
                }.buttonStyle(.plain).pointer().disabled(docVM.currentPage >= docVM.totalPages)
            }
            Spacer()
            if docVM.isPDF {
                Button {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.nameFieldStringValue = docVM.documentTitle
                    if panel.runModal() == .OK, let dest = panel.url, let src = docVM.documentURL {
                        try? FileManager.default.copyItem(at: src, to: dest)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 10))
                        Text("Save Copy").font(.system(.caption2, design: .rounded))
                    }.foregroundStyle(T.muted)
                }.buttonStyle(.plain).pointer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(T.surface)
    }
}

@MainActor
final class DocumentVM: ObservableObject {
    @Published var documentURL: URL?
    @Published var documentTitle = ""
    @Published var isPDF = true
    @Published var currentPage = 1
    @Published var totalPages = 0
    @Published var zoomLevel: Double = 1.0
    @Published var darkReading = false
    @Published var showTOC = false
    @Published var recentFiles: [String] = []
    @Published var currentDocument: String? = nil

    init() {
        recentFiles = (UserDefaults.standard.stringArray(forKey: "recentDocuments") ?? []).filter {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    func openDocument(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        documentURL = url
        documentTitle = url.lastPathComponent
        isPDF = url.pathExtension.lowercased() == "pdf"
        currentPage = 1
        currentDocument = url.path

        var recent = recentFiles.filter { $0 != url.path }
        recent.insert(url.path, at: 0)
        recentFiles = Array(recent.prefix(10))
        UserDefaults.standard.set(recentFiles, forKey: "recentDocuments")

        if isPDF {
            if let doc = PDFKitDocument(url: url) { totalPages = doc.pageCount }
        }
    }

    func closeDocument() {
        if let url = documentURL { url.stopAccessingSecurityScopedResource() }
        documentURL = nil; currentDocument = nil; documentTitle = ""; totalPages = 0; currentPage = 1
    }

    func zoomIn() { zoomLevel = min(3.0, zoomLevel + 0.25) }
    func zoomOut() { zoomLevel = max(0.25, zoomLevel - 0.25) }
    func toggleDarkReading() { darkReading.toggle() }
    func toggleTOC() { showTOC.toggle() }
    func nextPage() { if currentPage < totalPages { currentPage += 1 } }
    func previousPage() { if currentPage > 1 { currentPage -= 1 } }
    func goToPage(_ page: Int) { currentPage = max(1, min(totalPages, page)) }
}

import PDFKit
typealias PDFKitDocument = PDFKit.PDFDocument

struct PDFReaderView: NSViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: DocumentVM

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        if let doc = PDFKitDocument(url: url) {
            pdfView.document = doc
            DispatchQueue.main.async { viewModel.totalPages = doc.pageCount }
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                                name: .PDFViewPageChanged, object: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.scaleFactor = viewModel.zoomLevel * pdfView.scaleFactorForSizeToFit

        if viewModel.darkReading {
            pdfView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        } else {
            pdfView.backgroundColor = .clear
        }

        if let doc = pdfView.document, viewModel.currentPage >= 1, viewModel.currentPage <= doc.pageCount {
            if let page = doc.page(at: viewModel.currentPage - 1), pdfView.currentPage != page {
                pdfView.go(to: page)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    class Coordinator: NSObject {
        let viewModel: DocumentVM
        init(viewModel: DocumentVM) { self.viewModel = viewModel }
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let doc = pdfView.document,
                  let idx = doc.index(for: page) as Int? else { return }
            DispatchQueue.main.async { self.viewModel.currentPage = idx + 1 }
        }
    }
}

struct EPUBReaderView: NSViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: DocumentVM

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadEPUB(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let bgColor = viewModel.darkReading ? "#0a0a0a" : "#ffffff"
        let textColor = viewModel.darkReading ? "#e0e0e0" : "#1a1a1a"
        let fontSize = Int(16 * viewModel.zoomLevel)
        webView.evaluateJavaScript("""
            document.body.style.backgroundColor='\(bgColor)';
            document.body.style.color='\(textColor)';
            document.body.style.fontSize='\(fontSize)px';
        """)
    }

    private func loadEPUB(into webView: WKWebView) {
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("epub_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", url.path, "-d", extractDir.path]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        try? proc.run(); proc.waitUntilExit()

        let fm = FileManager.default
        var htmlFile: URL?
        if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "xhtml" || ext == "html" || ext == "htm" {
                    htmlFile = fileURL; break
                }
            }
        }

        if let html = htmlFile {
            webView.loadFileURL(html, allowingReadAccessTo: extractDir)
        } else {
            webView.loadHTMLString("""
                <html><body style="font-family:-apple-system;color:#888;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
                <div style="text-align:center"><h2>Could not parse EPUB</h2><p>The file format may be unsupported.</p></div></body></html>
            """, baseURL: nil)
        }
    }
}

// MARK: - Logs View

struct LogsView: View {
    @ObservedObject var vm: LogStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.text)
                Spacer()
                Text("\(vm.entries.count) entries").font(.system(.caption, design: .rounded)).foregroundStyle(T.muted)
                Button("Clear") { vm.clear() }.controlSize(.small)
            }.padding(24).padding(.bottom, 0)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.entries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.level == "error" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(entry.level == "error" ? T.danger : T.accent)
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted).frame(width: 70, alignment: .leading)
                            Text(entry.message).font(.system(.caption, design: .rounded)).foregroundStyle(T.text).lineLimit(1)
                            Spacer()
                            if let d = entry.detail {
                                Text(d).font(.system(.caption2, design: .monospaced)).foregroundStyle(T.muted).lineLimit(1).frame(maxWidth: 200, alignment: .trailing)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }.padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Media Extractor VM (yt-dlp)

@MainActor
final class MediaExtractorVM: ObservableObject {
    @Published var urlInput = ""
    @Published var detectedPlatform: Platform?
    @Published var isDownloading = false
    @Published var history: [DownloadRecord] = []
    @Published var vidFormat: VidFormat = .mp4
    @Published var quality: QualityPreset = .best
    @Published var audFormat: AudFormat = .mp3
    @Published var audBitrate: AudBitrate = .k320
    @Published var showLongWarning = false
    @Published var concurrentFragments: Int = UserDefaults.standard.object(forKey: "concurrentFragments") as? Int ?? 8
    @Published var maxCPUCores: Int = UserDefaults.standard.object(forKey: "maxCPUCores") as? Int ?? ProcessInfo.processInfo.activeProcessorCount
    @Published var maxRAMMB: Int = UserDefaults.standard.object(forKey: "maxRAMMB") as? Int ?? 512
    @Published var chunkSizeMB: Int = UserDefaults.standard.object(forKey: "chunkSizeMB") as? Int ?? 10
    @Published var processPriority: ProcessPriorityLevel = ProcessPriorityLevel(rawValue: UserDefaults.standard.string(forKey: "processPriority") ?? "normal") ?? .normal
    var downloadFolder: URL
    private var activeTask: Task<Void, Never>?

    init() {
        let f = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor")
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        downloadFolder = f
    }

    func savePerformanceSettings() {
        UserDefaults.standard.set(concurrentFragments, forKey: "concurrentFragments")
        UserDefaults.standard.set(maxCPUCores, forKey: "maxCPUCores")
        UserDefaults.standard.set(maxRAMMB, forKey: "maxRAMMB")
        UserDefaults.standard.set(chunkSizeMB, forKey: "chunkSizeMB")
        UserDefaults.standard.set(processPriority.rawValue, forKey: "processPriority")
    }

    var longDownloadWarning: String? {
        let url = urlInput.lowercased()
        if quality == .q4k || quality == .best {
            if url.contains("youtube.com") || url.contains("youtu.be") { return "YouTube videos in high quality may take 30s-2min depending on length." }
        }
        if url.contains("tiktok.com") { return nil }
        if url.contains("instagram.com") && (url.contains("/reel") || url.contains("/tv")) { return "Instagram video downloads may take 10-30s due to format merging." }
        if url.contains("soundcloud.com") || url.contains("spotify.com") { return "Audio downloads require transcoding and may take 10-20s." }
        if quality == .q4k { return "4K downloads are large and may take 1-3 minutes." }
        return nil
    }

    func download(cookies: [HTTPCookie]? = nil) async {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isDownloading = true
        let rec = DownloadRecord(date: Date(), url: url, platform: detectedPlatform,
                                  title: "Downloading...", status: .downloading,
                                  filePath: nil, fileSize: 0, error: nil)
        history.insert(rec, at: 0)
        let result = await Self.downloadURL(url, cookies: cookies, to: downloadFolder,
                                             vidFmt: vidFormat, quality: quality, audFmt: audFormat, audBit: audBitrate,
                                             fragments: concurrentFragments, chunkMB: chunkSizeMB, priority: processPriority)
        if Task.isCancelled {
            if let idx = history.firstIndex(where: { $0.id == rec.id }) {
                history[idx].status = .cancelled; history[idx].title = "Cancelled"
            }
        } else {
            if let idx = history.firstIndex(where: { $0.id == rec.id }) {
                history[idx].status = result.ok ? .complete : .failed
                history[idx].title = result.ext.isEmpty ? url : "Media\(result.ext)"
                history[idx].filePath = result.ok ? downloadFolder.path : nil
                history[idx].fileSize = result.bytes
                history[idx].error = result.error
            }
        }
        isDownloading = false
    }

    func cancelDownload(id: UUID) {
        activeTask?.cancel()
        if let idx = history.firstIndex(where: { $0.id == id }) {
            history[idx].status = .cancelled; history[idx].title = "Cancelled"
            history[idx].taskHandle?.cancel()
        }
        isDownloading = false
    }

    func retryDownload(id: UUID, cookies: [HTTPCookie]? = nil) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let url = history[idx].url
        history[idx].status = .downloading; history[idx].title = "Retrying..."; history[idx].error = nil
        isDownloading = true
        let handle = Task {
            let result = await Self.downloadURL(url, cookies: cookies, to: downloadFolder,
                                                 vidFmt: vidFormat, quality: quality, audFmt: audFormat, audBit: audBitrate,
                                                 fragments: concurrentFragments, chunkMB: chunkSizeMB, priority: processPriority)
            if let i = history.firstIndex(where: { $0.id == id }) {
                history[i].status = result.ok ? .complete : .failed
                history[i].title = result.ext.isEmpty ? url : "Media\(result.ext)"
                history[i].filePath = result.ok ? downloadFolder.path : nil
                history[i].fileSize = result.bytes; history[i].error = result.error
            }
            isDownloading = false
        }
        if let i = history.firstIndex(where: { $0.id == id }) { history[i].taskHandle = handle }
    }

    nonisolated static func downloadURL(_ url: String, cookies: [HTTPCookie]? = nil, to folder: URL,
                                         vidFmt: VidFormat = .mp4, quality: QualityPreset = .best,
                                         audFmt: AudFormat = .mp3, audBit: AudBitrate = .k320,
                                         fragments: Int = 8, chunkMB: Int = 10, priority: ProcessPriorityLevel = .normal) async -> OneResult {
        let ytdlp = findYtdlp()
        guard !ytdlp.isEmpty else { return OneResult(ok: false, ext: "", bytes: 0, error: "yt-dlp not found. Install: brew install yt-dlp") }
        var args = [url, "-o", "%(title)s.%(ext)s", "-P", folder.path, "--no-playlist", "--no-overwrites",
                    "--concurrent-fragments", "\(fragments)", "--retries", "5", "--fragment-retries", "5",
                    "--buffer-size", "64K", "--http-chunk-size", "\(chunkMB)M"]
        let fmtSpec: String
        switch quality {
        case .best: fmtSpec = "bestvideo+bestaudio/best"
        case .q4k: fmtSpec = "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case .q1080: fmtSpec = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .q720: fmtSpec = "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .q480: fmtSpec = "bestvideo[height<=480]+bestaudio/best[height<=480]"
        }
        args += ["-f", fmtSpec, "--merge-output-format", vidFmt.rawValue.lowercased()]
        if let cookies, !cookies.isEmpty {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("me_cookies_\(UUID().uuidString).txt")
            writeCookieFile(cookies, to: tmp); args += ["--cookies", tmp.path]
        }
        return await runProcess(path: ytdlp, args: args, folder: folder, priority: priority)
    }

    nonisolated static func findYtdlp() -> String {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].first { FileManager.default.fileExists(atPath: $0) } ?? ""
    }

    nonisolated static func writeCookieFile(_ cookies: [HTTPCookie], to file: URL) {
        var lines = ["# Netscape HTTP Cookie File"]
        for c in cookies {
            let flag = c.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let secure = c.isSecure ? "TRUE" : "FALSE"
            let exp = c.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            lines.append("\(c.domain)\t\(flag)\t\(c.path)\t\(secure)\t\(exp)\t\(c.name)\t\(c.value)")
        }
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    nonisolated static func runProcess(path: String, args: [String], folder: URL, priority: ProcessPriorityLevel = .normal) async -> OneResult {
        await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
            proc.environment = ProcessInfo.processInfo.environment
            switch priority {
            case .low: proc.qualityOfService = .background
            case .normal: proc.qualityOfService = .userInitiated
            case .high: proc.qualityOfService = .userInteractive
            }
            proc.standardOutput = Pipe(); proc.standardError = Pipe()
            do {
                try proc.run(); proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let fm = FileManager.default
                    let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
                    let newest = files.filter { !$0.lastPathComponent.hasSuffix(".csv") && $0.lastPathComponent != "session_log.json" && !$0.lastPathComponent.hasPrefix(".") }
                        .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast >
                                  (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }.first
                    if let f = newest {
                        let sz = (try? fm.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
                        cont.resume(returning: OneResult(ok: true, ext: ".\(f.pathExtension)", bytes: sz, error: nil))
                    } else { cont.resume(returning: OneResult(ok: true, ext: "", bytes: 0, error: nil)) }
                } else {
                    let errData = (proc.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let msg = String(data: errData, encoding: .utf8)?.prefix(150) ?? "Unknown error"
                    cont.resume(returning: OneResult(ok: false, ext: "", bytes: 0, error: String(msg)))
                }
            } catch { cont.resume(returning: OneResult(ok: false, ext: "", bytes: 0, error: error.localizedDescription)) }
        }
    }
}

// MARK: - Account Manager

@MainActor
final class AccountManager: ObservableObject {
    @Published var accounts: [ConnectedAccount] = []

    private var storeURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("accounts.json")
    }

    init() { loadAccounts() }

    func addAccount(_ account: ConnectedAccount, cookies: [HTTPCookie]) {
        accounts.append(account)
        saveCookies(cookies, forAccount: account.id); saveAccounts()
    }

    func removeAccount(_ id: UUID) {
        KeychainHelper.delete(forKey: "cookies_\(id.uuidString)")
        accounts.removeAll { $0.id == id }; saveAccounts()
    }

    func getCookies(forAccount id: UUID) -> [HTTPCookie]? {
        guard let data = KeychainHelper.load(forKey: "cookies_\(id.uuidString)"),
              let arr = try? JSONDecoder().decode([CookieData].self, from: data) else { return nil }
        return arr.compactMap { $0.toCookie() }
    }

    private func saveCookies(_ cookies: [HTTPCookie], forAccount id: UUID) {
        let arr = cookies.map { CookieData(cookie: $0) }
        guard let data = try? JSONEncoder().encode(arr) else { return }
        KeychainHelper.save(data, forKey: "cookies_\(id.uuidString)")
    }

    private func loadAccounts() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        accounts = (try? JSONDecoder().decode([ConnectedAccount].self, from: data)) ?? []
    }

    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: storeURL)
    }
}

// MARK: - CSV Download Manager

@MainActor
final class CSVDownloadManager: ObservableObject {
    @Published var phase: CSVPhase = .idle
    @Published var csvFiles: [CSVEntry] = []
    @Published var baseFolder: URL?
    @Published var globalKeywords: [String] = ["twimg", "pbs", "media"]
    @Published var keywordMode: KeywordMode = .global
    @Published var sessions: [SessionRecord] = []
    @Published var photoFormat: PhotoFmt = .original
    @Published var csvStatuses: [UUID: ExtractionStatus] = [:]
    @Published var totalFiles = 0; @Published var completedFiles = 0; @Published var failedFiles = 0
    @Published var bytesDownloaded: Int64 = 0; @Published var currentSpeed: Double = 0
    @Published var lastResult: SessionRecord?
    private let concurrency = 120
    private static let sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 20
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 90
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    func addCSVFile(url: URL) {
        guard !csvFiles.contains(where: { $0.url == url }) else { return }
        var e = CSVEntry(url: url, keywords: globalKeywords)
        parseEntry(&e); csvFiles.append(e); updatePhase()
    }
    func removeCSV(id: UUID) { csvFiles.removeAll { $0.id == id }; csvStatuses.removeValue(forKey: id); updatePhase() }

    func chooseCSVFiles() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for url in p.urls where url.pathExtension.lowercased() == "csv" { addCSVFile(url: url) }
    }
    func chooseBaseFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.prompt = "Choose"; p.message = "Select base folder for extraction sessions"
        guard p.runModal() == .OK, let url = p.url else { return }; baseFolder = url
    }
    func setKeywordMode(_ m: KeywordMode) {
        keywordMode = m
        if m == .perCSV { for i in csvFiles.indices where csvFiles[i].keywords.isEmpty { csvFiles[i].keywords = globalKeywords } }
        reparseAll()
    }
    func reparseAll() { for i in csvFiles.indices { reparseCSV(at: i) }; updatePhase() }
    func reparseCSV(at i: Int) { guard i < csvFiles.count else { return }; parseEntry(&csvFiles[i]) }
    private func parseEntry(_ e: inout CSVEntry) {
        let kws = keywordMode == .global ? globalKeywords : e.keywords
        e.mediaURLs = (try? Self.extractURLs(from: e.url, keywords: kws)) ?? []
    }
    private func updatePhase() { phase = csvFiles.isEmpty ? .idle : .ready }

    func startExtraction() async {
        guard let base = baseFolder, !csvFiles.isEmpty else { return }
        phase = .downloading; completedFiles = 0; failedFiles = 0; bytesDownloaded = 0; currentSpeed = 0
        totalFiles = csvFiles.reduce(0) { $0 + $1.urlCount }
        csvStatuses = Dictionary(uniqueKeysWithValues: csvFiles.map { ($0.id, ExtractionStatus.pending) })
        let fm = FileManager.default; try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        let sNum = Self.nextSessionNumber(in: base); let sName = "Session \(sNum)"
        let sFolder = base.appendingPathComponent(sName); try? fm.createDirectory(at: sFolder, withIntermediateDirectories: true)
        let t0 = CFAbsoluteTimeGetCurrent(); var recs: [ExtractionRecord] = []
        for (i, csv) in csvFiles.enumerated() {
            let fn = "Extraction \(i+1) - \(csv.stem)"; let ef = sFolder.appendingPathComponent(fn)
            try? fm.createDirectory(at: ef, withIntermediateDirectories: true)
            try? fm.copyItem(at: csv.url, to: ef.appendingPathComponent(csv.filename))
            csvStatuses[csv.id] = .inProgress(done: 0, total: csv.urlCount)
            let rec = await downloadBatch(urls: csv.mediaURLs, to: ef, csvId: csv.id, folderName: fn, csvFilename: csv.filename)
            recs.append(rec); csvStatuses[csv.id] = .complete(success: rec.success, failed: rec.failed)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        var allErr: [String: Int] = [:]; for r in recs { for (k,v) in r.errors { allErr[k, default: 0] += v } }
        let session = SessionRecord(id: UUID(), date: Date(), endDate: Date(), duration: elapsed,
            baseFolderPath: base.path(percentEncoded: false), sessionName: sName, extractions: recs,
            totalSuccess: recs.reduce(0){$0+$1.success}, totalFailed: recs.reduce(0){$0+$1.failed},
            totalBytes: recs.reduce(0){$0+$1.bytes}, allErrors: allErr)
        Self.saveSessionLog(session, to: sFolder); HistoryStore.shared.append(session)
        sessions = HistoryStore.shared.load(); lastResult = session; phase = .complete
    }

    private func downloadBatch(urls: [String], to folder: URL, csvId: UUID, folderName: String, csvFilename: String) async -> ExtractionRecord {
        var seen: [String: Int] = [:]
        let tasks = urls.map { u in (url: u, dest: folder.appendingPathComponent(Self.buildFilename(from: u, seen: &seen))) }
        var types: [String: Int] = [:]; var errs: [String: Int] = [:]
        var bBytes: Int64 = 0; var bOK = 0; var bFail = 0; let t0 = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: OneResult.self) { group in
            var n = 0
            for t in tasks {
                if n >= concurrency, let r = await group.next() { apply(r, &types, &errs, &bBytes, &bOK, &bFail, csvId, t0) }
                n += 1; let u = t.url; let d = t.dest
                group.addTask { await Self.downloadOne(urlString: u, to: d) }
            }
            for await r in group { apply(r, &types, &errs, &bBytes, &bOK, &bFail, csvId, t0) }
        }
        return ExtractionRecord(csvFilename: csvFilename, folderName: folderName, urlCount: urls.count,
                                success: bOK, failed: bFail, bytes: bBytes, typeBreakdown: types, errors: errs)
    }

    private func apply(_ r: OneResult, _ types: inout [String: Int], _ errs: inout [String: Int],
                        _ bBytes: inout Int64, _ bOK: inout Int, _ bFail: inout Int, _ csvId: UUID, _ t0: CFAbsoluteTime) {
        if r.ok { completedFiles += 1; bOK += 1; bytesDownloaded += r.bytes; bBytes += r.bytes; types[r.ext, default: 0] += 1 }
        else { failedFiles += 1; bFail += 1; if let e = r.error { errs[e, default: 0] += 1 } }
        let dt = CFAbsoluteTimeGetCurrent() - t0; if dt > 0 { currentSpeed = Double(bytesDownloaded) / dt }
        csvStatuses[csvId] = .inProgress(done: bOK + bFail, total: totalFiles)
    }

    func loadHistory() { sessions = HistoryStore.shared.load() }
    func deleteSession(id: UUID) {
        if let s = sessions.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: s.baseFolderPath).appendingPathComponent(s.sessionName))
        }
        HistoryStore.shared.delete(id: id); sessions = HistoryStore.shared.load()
    }

    nonisolated static func downloadOne(urlString: String, to dest: URL) async -> OneResult {
        guard let url = URL(string: urlString) else { return OneResult(ok: false, ext: "", bytes: 0, error: "InvalidURL") }
        do {
            var req = URLRequest(url: url)
            req.httpShouldHandleCookies = false
            let (tmp, resp) = try await sharedSession.download(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return OneResult(ok: false, ext: "", bytes: 0, error: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            var fd = dest
            if let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";").first {
                let me: String? = switch String(mime).trimmingCharacters(in: .whitespaces) {
                    case "image/webp": "webp"; case "image/png": "png"; case "image/gif": "gif"
                    case "image/jpeg","image/jpg": "jpg"; case "image/avif": "avif"; case "image/heic": "heic"
                    case "video/mp4": "mp4"; case "video/webm": "webm"; default: nil
                }
                if let me, dest.pathExtension.lowercased() != me { fd = dest.deletingPathExtension().appendingPathExtension(me) }
            }
            let fm = FileManager.default; if fm.fileExists(atPath: fd.path) { try fm.removeItem(at: fd) }
            try fm.moveItem(at: tmp, to: fd)
            let sz = (try? fm.attributesOfItem(atPath: fd.path)[.size] as? Int64) ?? 0
            return OneResult(ok: true, ext: ".\(fd.pathExtension.lowercased())", bytes: sz, error: nil)
        } catch let e as URLError where e.code == .timedOut { return OneResult(ok: false, ext: "", bytes: 0, error: "Timeout") }
        catch { return OneResult(ok: false, ext: "", bytes: 0, error: String(describing: type(of: error))) }
    }

    static func extractURLs(from csvURL: URL, keywords: [String]) throws -> [String] {
        var c = try String(contentsOf: csvURL, encoding: .utf8); if c.hasPrefix("\u{FEFF}") { c = String(c.dropFirst()) }
        let (rows, _) = parseCSV(c); var urls: [String] = []; var seen = Set<String>()
        for row in rows { for cell in row { for m in findURLs(in: cell) {
            if keywords.isEmpty || keywords.contains(where: { m.lowercased().contains($0.lowercased()) }) {
                if seen.insert(m).inserted { urls.append(m) }
            }
        } } }; return urls
    }
    static func findURLs(in text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: "https?://[^\\s,\"'<>]+") else { return [] }
        return rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    static func parseCSV(_ c: String) -> (rows: [[String]], header: [String]) {
        var rows: [[String]] = []; var row: [String] = []; var f = ""; var inQ = false; var pQ = false
        for ch in c {
            if pQ { pQ = false; if ch == "\"" { f.append("\""); continue } else { inQ = false } }
            switch ch {
            case "\"" where inQ: pQ = true; case "\"" where !inQ: inQ = true
            case "," where !inQ: row.append(f); f = ""
            case "\n" where !inQ: row.append(f); f = ""; if !row.isEmpty { rows.append(row) }; row = []
            case "\r" where !inQ: break; default: f.append(ch)
            }
        }; if !f.isEmpty || !row.isEmpty { row.append(f); rows.append(row) }
        guard let h = rows.first else { return ([], []) }; return (Array(rows.dropFirst()), h)
    }
    static func buildFilename(from urlString: String, seen: inout [String: Int]) -> String {
        let fb = "media_\(seen.count).jpg"; guard let url = URL(string: urlString) else { return fb }
        let b = url.lastPathComponent; if b.isEmpty || b == "/" { return fb }
        var n = (b as NSString).deletingPathExtension; var e = (b as NSString).pathExtension
        if n.isEmpty { n = "media_\(seen.count)" }; if e.isEmpty { e = "jpg" }
        if let q = e.firstIndex(of: "?") { e = String(e[..<q]) }
        let k = "\(n).\(e)"; let c = seen[k, default: 0]; seen[k] = c + 1
        return c > 0 ? "\(n)_\(c).\(e)" : k
    }
    static func nextSessionNumber(in base: URL) -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        var mx = 0; for i in items { if i.lastPathComponent.hasPrefix("Session "), let n = Int(i.lastPathComponent.dropFirst(8)) { mx = max(mx, n) } }
        return mx + 1
    }
    static func saveSessionLog(_ s: SessionRecord, to folder: URL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(s) else { return }; try? d.write(to: folder.appendingPathComponent("session_log.json"))
    }
}

// MARK: - Log Store

@MainActor
final class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []
    private var storeURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("logs.json")
    }
    init() { load() }
    func log(_ level: String, _ message: String, detail: String? = nil) {
        entries.insert(LogEntry(id: UUID(), date: Date(), level: level, message: message, detail: detail), at: 0)
        if entries.count > 500 { entries = Array(entries.prefix(500)) }; save()
    }
    func clear() { entries.removeAll(); save() }
    private func load() {
        guard let d = try? Data(contentsOf: storeURL) else { return }
        entries = (try? JSONDecoder().decode([LogEntry].self, from: d)) ?? []
    }
    private func save() {
        guard let d = try? JSONEncoder().encode(entries) else { return }; try? d.write(to: storeURL)
    }
}

// MARK: - History Store

class HistoryStore {
    static let shared = HistoryStore()
    private var historyURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MediaExtractor")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("history.json")
    }
    func load() -> [SessionRecord] {
        guard let d = try? Data(contentsOf: historyURL) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([SessionRecord].self, from: d))?.sorted(by: { $0.date > $1.date }) ?? []
    }
    func append(_ r: SessionRecord) { var all = load(); all.append(r); save(all) }
    func delete(id: UUID) { var all = load(); all.removeAll { $0.id == id }; save(all) }
    private func save(_ r: [SessionRecord]) {
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted; enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(r) else { return }; try? d.write(to: historyURL)
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(_ data: Data, forKey key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                 kSecAttrService as String: "com.mediaextractor.app"]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load(forKey key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                 kSecAttrService as String: "com.mediaextractor.app",
                                 kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?; SecItemCopyMatching(q as CFDictionary, &result); return result as? Data
    }
    static func delete(forKey key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                 kSecAttrService as String: "com.mediaextractor.app"]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Ad Blocker

class AdBlocker {
    static let shared = AdBlocker()
    var ruleList: WKContentRuleList?

    func compile() {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "mediaextractor_adblock", encodedContentRuleList: Self.rules
        ) { [weak self] list, _ in self?.ruleList = list }
    }

    static let rules = """
    [
    {"trigger":{"url-filter":".*googlesyndication\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*doubleclick\\\\.net.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*googleadservices\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*google-analytics\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*adservice\\\\.google\\\\..*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*pagead2\\\\.googlesyndication\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*static\\\\.ads-twitter\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*analytics\\\\.twitter\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*ads\\\\.tiktok\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*analytics\\\\.tiktok\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*log.*\\\\.tiktokv\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*connect\\\\.facebook\\\\.net.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*cdn\\\\.taboola\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*cdn\\\\.outbrain\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*amazon-adsystem\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*moatads\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*scorecardresearch\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*quantserve\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*criteo\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*adsrvr\\\\.org.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*adnxs\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*rubiconproject\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*pubmatic\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*openx\\\\.net.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*casalemedia\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*sharethis\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*addthis\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*hotjar\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*newrelic\\\\.com.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*segment\\\\.io.*"},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*mixpanel\\\\.com.*"},"action":{"type":"block"}}
    ]
    """
}

// MARK: - Encryption Helper

enum FileEncryptor {
    static func encrypt(data: Data, password: String) -> Data? {
        let keyData = SHA256.hash(data: Data(password.utf8))
        let key = SymmetricKey(data: keyData)
        guard let sealed = try? AES.GCM.seal(data, using: key) else { return nil }
        return sealed.combined
    }

    static func decrypt(data: Data, password: String) -> Data? {
        let keyData = SHA256.hash(data: Data(password.utf8))
        let key = SymmetricKey(data: keyData)
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key) else { return nil }
        return opened
    }
}

// MARK: - WebViews

struct AdBlockPreviewWebView: NSViewRepresentable {
    let urlString: String

    private static func ytVideoID(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("youtube.com/watch"), let comps = URLComponents(string: s), let vid = comps.queryItems?.first(where: { $0.name == "v" })?.value { return vid }
        if s.contains("youtu.be/"), let vid = URL(string: s)?.lastPathComponent, !vid.isEmpty { return vid }
        return nil
    }

    private static func isYouTube(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("youtube.com") || l.contains("youtu.be")
    }

    private static func ytThumbnailHTML(_ vid: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:#0a0a0a;display:flex;align-items:center;justify-content:center;height:100vh;overflow:hidden;font-family:-apple-system,sans-serif}
        .c{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center}
        img{max-width:100%;max-height:100%;object-fit:contain;opacity:0;transition:opacity .4s}
        img.loaded{opacity:1}
        .play{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:72px;height:50px;
              background:rgba(0,0,0,0.75);border-radius:14px;cursor:pointer;display:flex;align-items:center;justify-content:center;
              transition:all .2s;backdrop-filter:blur(8px)}
        .play:hover{background:rgba(200,30,30,0.9);transform:translate(-50%,-50%) scale(1.08)}
        .play::after{content:'';border-style:solid;border-width:11px 0 11px 20px;border-color:transparent transparent transparent #fff;margin-left:3px}
        .badge{position:absolute;top:12px;right:12px;background:rgba(10,10,10,0.7);color:#d4c4a8;font-size:11px;font-weight:500;
               padding:5px 12px;border-radius:20px;backdrop-filter:blur(6px);letter-spacing:0.3px}
        </style></head><body>
        <div class="c">
          <img id="t" src="https://img.youtube.com/vi/\(vid)/maxresdefault.jpg"
               onload="this.classList.add('loaded')"
               onerror="this.src='https://img.youtube.com/vi/\(vid)/hqdefault.jpg'">
          <div class="play" onclick="window.open('https://www.youtube.com/watch?v=\(vid)')"></div>
          <div class="badge">Ad-Free Preview</div>
        </div></body></html>
        """
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.preferences.setValue(true, forKey: "acceleratedDrawingEnabled")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if let rules = AdBlocker.shared.ruleList { wv.configuration.userContentController.add(rules) }
        loadContent(wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isYouTube(trimmed) {
            if let vid = Self.ytVideoID(trimmed) {
                let js = "document.getElementById('t')?.src || ''"
                wv.evaluateJavaScript(js) { r, _ in
                    if let src = r as? String, src.contains(vid) { return }
                    wv.loadHTMLString(Self.ytThumbnailHTML(vid), baseURL: nil)
                }
            }
        } else if let url = URL(string: trimmed) {
            let current = wv.url?.absoluteString ?? ""
            if !current.contains(url.host ?? "___") { wv.load(URLRequest(url: url)) }
        }
    }

    private func loadContent(_ wv: WKWebView) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let vid = Self.ytVideoID(trimmed) {
            wv.loadHTMLString(Self.ytThumbnailHTML(vid), baseURL: nil)
        } else if let url = URL(string: trimmed) {
            wv.load(URLRequest(url: url))
        }
    }
}

struct BrowseWebView: NSViewRepresentable {
    let url: URL; let cookies: [HTTPCookie]; @Binding var currentURL: String

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BrowseWebView
        init(_ p: BrowseWebView) { parent = p }
        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) { parent.currentURL = wv.url?.absoluteString ?? "" }
        func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) { parent.currentURL = wv.url?.absoluteString ?? "" }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        if let rules = AdBlocker.shared.ruleList { cfg.userContentController.add(rules) }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        Task {
            let store = wv.configuration.websiteDataStore.httpCookieStore
            for c in cookies { await store.setCookie(c) }
            let _ = await MainActor.run { wv.load(URLRequest(url: url)) }
        }
        return wv
    }
    func updateNSView(_ wv: WKWebView, context: Context) {}
}

struct LoginWebView: NSViewRepresentable {
    let platform: Platform; let onLogin: ([HTTPCookie]) -> Void

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView; var detected = false
        init(_ p: LoginWebView) { parent = p }
        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            guard !detected, let url = wv.url, parent.platform.isLoggedIn(url: url) else { return }
            detected = true
            Task {
                let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
                let filtered = cookies.filter { c in parent.platform.domains.contains(where: { c.domain.contains($0) }) }
                await MainActor.run { parent.onLogin(filtered) }
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        wv.load(URLRequest(url: platform.loginURL))
        return wv
    }
    func updateNSView(_ wv: WKWebView, context: Context) {}
}

// MARK: - View Modifiers

struct PointerHover: ViewModifier {
    @State private var hovering = false
    var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1.0)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { h in hovering = h; if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
extension View {
    func pointer(scale: CGFloat = 1.0) -> some View { modifier(PointerHover(scale: scale)) }
}

// MARK: - Shared Components

struct SidebarButton: View {
    let label: String; let icon: String; let isSelected: Bool; let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(label).font(.system(.body, design: .rounded).weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? T.text : hovering ? T.text.opacity(0.7) : T.muted.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? T.text.opacity(0.07) : hovering ? T.text.opacity(0.04) : .clear))
            .scaleEffect(hovering && !isSelected ? 1.015 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct InfoButton: View {
    let text: String
    @State private var showing = false
    var body: some View {
        Button { withAnimation(.spring(duration: 0.2)) { showing.toggle() } } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(showing ? T.accent : T.muted.opacity(0.5))
        }
        .buttonStyle(.plain).pointer()
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(T.text.opacity(0.85))
                .frame(width: 240)
                .padding(12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KWEditor: View {
    @Binding var keywords: [String]; var onChanged: () -> Void; @State private var newKW = ""
    var body: some View {
        HStack(spacing: 5) {
            ForEach(keywords, id: \.self) { kw in
                HStack(spacing: 4) {
                    Text(kw).font(.system(.caption, design: .monospaced).weight(.medium))
                    Button { withAnimation { keywords.removeAll { $0 == kw } }; onChanged() } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(T.muted)
                    }.buttonStyle(.plain)
                }.foregroundStyle(T.text.opacity(0.7)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
            }
            HStack(spacing: 3) {
                TextField("add", text: $newKW).textFieldStyle(.plain).font(.system(.caption, design: .monospaced)).frame(width: 50)
                    .onSubmit { add() }
                Button(action: add) { Image(systemName: "plus").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }.foregroundStyle(T.muted).padding(.horizontal, 7).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(T.border, lineWidth: 1))
            Spacer()
        }
    }
    private func add() {
        let k = newKW.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty, !keywords.contains(k) else { return }
        withAnimation { keywords.append(k) }; newKW = ""; onChanged()
    }
}

struct ProgressBar: View {
    let progress: Double; let label: String
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(T.surface)
                RoundedRectangle(cornerRadius: 6).fill(T.accent)
                    .frame(width: max(0, g.size.width * min(progress, 1.0)))
                    .animation(.easeOut(duration: 0.2), value: progress)
                Text(label).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(T.text.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
        }.frame(height: 28)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        DispatchQueue.main.async { v.window?.isOpaque = false; v.window?.backgroundColor = .clear }; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Helpers

func formatBytes(_ b: Int64) -> String {
    let d = Double(b); if d < 1024 { return "\(b) B" }
    if d < 1_048_576 { return String(format: "%.1f KB", d/1024) }
    if d < 1_073_741_824 { return String(format: "%.1f MB", d/1_048_576) }
    return String(format: "%.2f GB", d/1_073_741_824)
}
func formatSpeed(_ bps: Double) -> String {
    if bps < 1024 { return String(format: "%.0f B/s", bps) }
    if bps < 1_048_576 { return String(format: "%.1f KB/s", bps/1024) }
    return String(format: "%.1f MB/s", bps/1_048_576)
}
