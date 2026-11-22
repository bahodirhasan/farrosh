import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Fonda ishlash sozlamalari

enum Prefs {
    static let menuBar = "showMenuBar"
    static let lowSpaceGB = "lowSpaceGB"
    static let reminder = "cleanReminder"
    static let watchTrash = "watchTrash"
    static let lastReminder = "lastReminderDate"
    static let lastLowSpace = "lastLowSpaceDate"

    static func register() {
        UserDefaults.standard.register(defaults: [
            menuBar: true, lowSpaceGB: 10, reminder: Reminder.weekly.rawValue, watchTrash: true,
        ])
    }

    static var menuBarOn: Bool { UserDefaults.standard.bool(forKey: menuBar) }
}

enum Reminder: String, CaseIterable, Identifiable {
    case off, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return L("O'chiq", "Off", "Выключено")
        case .weekly: return L("Har hafta", "Weekly", "Каждую неделю")
        case .monthly: return L("Har oy", "Monthly", "Каждый месяц")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .weekly: return 7 * 86_400
        case .monthly: return 30 * 86_400
        }
    }
}

/// Savatga tashlangan ilova va uning topilgan qoldiqlari.
struct TrashedApp: Identifiable {
    let id = UUID()
    let app: AppInfo
    var files: [CleanItem]
}

extension Notification.Name {
    static let farroshDidClean = Notification.Name("farroshDidClean")
}

// MARK: - Fon xizmati

/// Menyu satri, kam joy ogohlantirishi, muntazam eslatma va Savatni kuzatish.
@MainActor
final class Background: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Background()

    @Published var disk = DiskInfo.current()
    @Published var cacheSize: Int64?
    @Published var quickCleaning = false
    @Published var lastFreed: Int64?
    @Published var trashedApp: TrashedApp?

    /// Asosiy oynani ochish — SwiftUI'ning openWindow'i ko'rinishdan olinadi.
    var openMain: (() -> Void)?

    private var timer: Timer?
    private var trashSource: DispatchSourceFileSystemObject?
    private var knownTrashApps: Set<String> = []

    func start() {
        Prefs.register()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in Background.shared.tick() }
        }
        tick()
        updateTrashWatcher()

        // Menyu satri sahnasi bo'lganda SwiftUI ba'zan asosiy oynani ochmaydi — o'zimiz ochamiz.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Task { @MainActor in
                if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                    Background.shared.showMain()
                }
            }
        }
    }

    // MARK: Davriy tekshiruv

    func tick() {
        disk = .current()
        checkLowSpace()
        checkReminder()
    }

    private func checkLowSpace() {
        let gb = UserDefaults.standard.integer(forKey: Prefs.lowSpaceGB)
        guard gb > 0, disk.free < Int64(gb) * 1_000_000_000 else { return }
        // Kuniga bir martadan ko'p bezovta qilmaymiz.
        if let last = UserDefaults.standard.object(forKey: Prefs.lastLowSpace) as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }
        UserDefaults.standard.set(Date(), forKey: Prefs.lastLowSpace)
        notify(
            id: "lowSpace",
            title: L("Diskda joy kam qoldi", "Your disk is almost full", "На диске мало места"),
            body: L("Faqat \(disk.free.bytes) bo'sh. Farrosh'ni ochib, keraksiz fayllarni tozalang.",
                    "Only \(disk.free.bytes) free. Open Farrosh to clean up junk files.",
                    "Свободно всего \(disk.free.bytes). Откройте Farrosh и удалите ненужные файлы.")
        )
    }

    private func checkReminder() {
        let reminder = Reminder(rawValue: UserDefaults.standard.string(forKey: Prefs.reminder) ?? "") ?? .weekly
        guard let interval = reminder.interval else { return }
        let defaults = UserDefaults.standard
        guard let last = defaults.object(forKey: Prefs.lastReminder) as? Date else {
            // Birinchi ishga tushishda darhol emas, keyingi davrda eslatamiz.
            defaults.set(Date(), forKey: Prefs.lastReminder)
            return
        }
        guard Date().timeIntervalSince(last) >= interval else { return }
        defaults.set(Date(), forKey: Prefs.lastReminder)
        Task.detached(priority: .utility) {
            let size = CacheCleaner.cleanableSize()
            guard size >= 500_000_000 else { return }
            await MainActor.run {
                Background.shared.cacheSize = size
                Background.shared.notify(
                    id: "reminder",
                    title: L("\(size.bytes) tozalash mumkin", "\(size.bytes) can be cleaned", "Можно очистить \(size.bytes)"),
                    body: L("Kesh va loglar yig'ilib qoldi. Menyu satridagi Farrosh belgisidan bir bosishda tozalang.",
                            "Caches and logs have piled up. Clean them in one click from the Farrosh icon in the menu bar.",
                            "Накопились кэш и журналы. Очистите их одним нажатием через значок Farrosh в строке меню.")
                )
            }
        }
    }

    // MARK: Menyu satridan tez tozalash

    func refreshCacheSize() {
        disk = .current()
        Task.detached(priority: .userInitiated) {
            let size = CacheCleaner.cleanableSize()
            await MainActor.run { Background.shared.cacheSize = size }
        }
    }

    func quickClean() {
        guard !quickCleaning else { return }
        quickCleaning = true
        lastFreed = nil
        Task.detached(priority: .userInitiated) {
            let freed = CacheCleaner.clean()
            await MainActor.run {
                let bg = Background.shared
                bg.quickCleaning = false
                bg.lastFreed = freed
                bg.cacheSize = 0
                bg.disk = .current()
                NotificationCenter.default.post(name: .farroshDidClean, object: nil)
            }
        }
    }

    // MARK: Savatni kuzatish

    /// Savatni o'qish uchun «To'liq disk ruxsati» kerak — bo'lmasa kuzatuv jim turadi.
    func updateTrashWatcher() {
        trashSource?.cancel()
        trashSource = nil
        guard UserDefaults.standard.bool(forKey: Prefs.watchTrash) else { return }
        let trash = Scanner.home.appendingPathComponent(".Trash")
        let fd = open(trash.path, O_EVTONLY)
        guard fd >= 0 else { return }
        knownTrashApps = Set(trashApps().map(\.path))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler {
            Task { @MainActor in Background.shared.trashChanged() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        trashSource = source
    }

    var trashWatching: Bool { trashSource != nil }

    private func trashApps() -> [URL] {
        Scanner.children(of: Scanner.home.appendingPathComponent(".Trash")).filter { $0.pathExtension == "app" }
    }

    private func trashChanged() {
        let now = trashApps()
        let added = now.filter { !knownTrashApps.contains($0.path) }
        knownTrashApps = Set(now.map(\.path))
        for url in added { inspectTrashed(url) }
    }

    private func inspectTrashed(_ url: URL) {
        Task.detached(priority: .utility) {
            guard let info = AppScanner.appInfo(for: url), !info.bundleID.isEmpty else { return }
            // Ilovaning boshqa nusxasi hali o'rnatilgan bo'lsa (masalan, yangilanish), qoldiq emas.
            if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: info.bundleID),
               !installed.path.contains("/.Trash/") { return }
            let files = AppScanner.relatedFiles(for: info).values.joined().sorted { $0.size > $1.size }
            let total = files.reduce(0) { $0 + $1.size }
            guard total > 0 else { return }
            await MainActor.run {
                let bg = Background.shared
                bg.trashedApp = TrashedApp(app: info, files: Array(files))
                bg.notify(
                    id: "trashed",
                    title: L("\(info.name) Savatga tashlandi", "\(info.name) moved to the Trash", "\(info.name) перемещено в Корзину"),
                    body: L("Uning \(total.bytes) qoldig'i topildi. Tozalash uchun bosing.",
                            "Found \(total.bytes) of its leftovers. Click to clean them up.",
                            "Найдено \(total.bytes) остатков. Нажмите, чтобы очистить.")
                )
            }
        }
    }

    // MARK: Bildirishnomalar

    func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id + UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in Background.shared.showMain() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Kesh tozalovchi (menyu satri va eslatma uchun)

enum CacheCleaner {
    /// Faqat xavfsiz, qayta yaratiladigan turlar: ilova keshi, loglar, dasturchi keshlari.
    static let categories: [Category] = [.appCaches, .logs, .devCaches]

    static func cleanableSize() -> Int64 {
        categories.flatMap(Scanner.scan).filter(\.selected).reduce(0) { $0 + $1.size }
    }

    static func clean() -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        for item in categories.flatMap(Scanner.scan) where item.selected {
            for url in item.urls {
                do { try fm.removeItem(at: url) } catch {
                    for child in Scanner.children(of: url) { try? fm.removeItem(at: child) }
                }
            }
            freed += max(0, item.size - Scanner.size(of: item.urls))
        }
        return freed
    }
}

// MARK: - Mac yoqilganda ishga tushish

enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Menyu satri

struct MenuBarLabel: View {
    @ObservedObject var bg: Background
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: lowSpace ? "exclamationmark.triangle.fill" : "sparkles")
            Text(bg.disk.free.bytes)
        }
        .onAppear { bg.openMain = { openWindow(id: "main") } }
    }

    private var lowSpace: Bool {
        let gb = UserDefaults.standard.integer(forKey: Prefs.lowSpaceGB)
        return gb > 0 && bg.disk.free < Int64(gb) * 1_000_000_000
    }
}

struct MenuBarPanel: View {
    @ObservedObject var bg: Background
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Farrosh").font(.headline)
                    Text(bg.disk.name).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(bg.disk.used), total: Double(max(bg.disk.total, 1)))
                    .tint(lowSpace ? .red : .accentColor)
                Text(L("\(bg.disk.free.bytes) bo'sh · jami \(bg.disk.total.bytes)",
                       "\(bg.disk.free.bytes) free of \(bg.disk.total.bytes)",
                       "Свободно \(bg.disk.free.bytes) из \(bg.disk.total.bytes)"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if lowSpace {
                    Label(L("Diskda joy kam qoldi", "Disk is almost full", "На диске мало места"),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                Text(L("Kesh va loglar", "Caches and logs", "Кэш и журналы"))
                Spacer()
                if let size = bg.cacheSize {
                    Text(size.bytes).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            Button { bg.quickClean() } label: {
                HStack(spacing: 8) {
                    if bg.quickCleaning { ProgressView().controlSize(.small).tint(.white) }
                    Text(bg.quickCleaning ? L("Tozalanmoqda…", "Cleaning…", "Очистка…")
                                          : L("Keshni tozalash", "Clean caches", "Очистить кэш"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(bg.quickCleaning || (bg.cacheSize ?? 0) == 0)

            if let freed = bg.lastFreed {
                Label(L("\(freed.bytes) bo'shatildi", "\(freed.bytes) freed", "Освобождено \(freed.bytes)"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Divider()

            Button(L("Farrosh'ni ochish", "Open Farrosh", "Открыть Farrosh")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .buttonStyle(.borderless)
            Button(L("Farrosh'dan chiqish", "Quit Farrosh", "Выйти из Farrosh")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { bg.refreshCacheSize() }
    }

    private var lowSpace: Bool {
        let gb = UserDefaults.standard.integer(forKey: Prefs.lowSpaceGB)
        return gb > 0 && bg.disk.free < Int64(gb) * 1_000_000_000
    }
}

// MARK: - Savatga tashlangan ilova qoldiqlari

struct TrashedAppSheet: View {
    let trashed: TrashedApp
    let done: () -> Void
    @StateObject private var model: TrashedModel

    init(trashed: TrashedApp, done: @escaping () -> Void) {
        self.trashed = trashed
        self.done = done
        _model = StateObject(wrappedValue: TrashedModel(files: trashed.files))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: trashed.app.url.path)).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("\(trashed.app.name) qoldiqlari", "\(trashed.app.name) leftovers", "Остатки \(trashed.app.name)"))
                        .font(.title3.weight(.semibold))
                    Text(L("Ilova Savatga tashlandi, lekin uning sozlama va ma'lumotlari qolib ketdi.",
                           "The app went to the Trash, but its settings and data were left behind.",
                           "Приложение в Корзине, но его настройки и данные остались."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)

            if let message = model.message {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text(message).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                Form {
                    ForEach(model.files) { item in
                        ItemRow(item: item) { model.toggle(item) }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack(spacing: 12) {
                Button(model.message == nil ? L("Keyinroq", "Later", "Позже") : L("Tayyor", "Done", "Готово"), action: done)
                    .buttonStyle(PrimaryButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                if model.message == nil {
                    Button { model.clean() } label: {
                        Text(L("Tozalash", "Clean", "Очистить") + " · \(model.selectedSize.bytes)")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .red))
                    .disabled(model.working || model.selectedSize == 0)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
    }
}

@MainActor
final class TrashedModel: ObservableObject {
    @Published var files: [CleanItem]
    @Published var working = false
    @Published var message: String?

    init(files: [CleanItem]) { self.files = files }

    var selectedSize: Int64 { files.filter(\.selected).reduce(0) { $0 + $1.size } }

    func toggle(_ item: CleanItem) {
        guard let i = files.firstIndex(where: { $0.id == item.id }) else { return }
        files[i].selected.toggle()
    }

    func clean() {
        let targets = files.filter(\.selected)
        let total = selectedSize
        working = true
        Task.detached(priority: .userInitiated) {
            for url in targets.flatMap(\.urls) { try? Remover.discard(url) }
            await MainActor.run {
                self.working = false
                self.message = L("\(total.bytes) \(Remover.doneVerb).", "\(total.bytes) \(Remover.doneVerb).", "\(total.bytes) \(Remover.doneVerb).")
            }
        }
    }
}
