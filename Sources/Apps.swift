import SwiftUI
import ServiceManagement
import CoreServices

// MARK: - Ma'lumotlar

struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    /// Apple Silicon'da faqat Rosetta orqali ishlaydigan (Intel uchun yozilgan) ilova.
    let isIntelOnly: Bool
    var size: Int64?
    var lastUsed: Date?
    var id: String { url.path }

    /// Farrosh'ning o'zi — uni ham o'chirish mumkin, lekin oxirida dastur yopiladi.
    var isSelf: Bool { bundleID == Bundle.main.bundleIdentifier }

    /// 90 kundan beri ochilmagan.
    var isUnused: Bool {
        guard let lastUsed else { return false }
        return lastUsed < Date().addingTimeInterval(-90 * 86_400)
    }
}

enum AppSort: String, CaseIterable {
    case name, size, lastUsed

    var title: String {
        switch self {
        case .name: return L("Nomi", "Name", "Имя")
        case .size: return L("Hajmi", "Size", "Размер")
        case .lastUsed: return L("Ochilgan", "Last opened", "Открыто")
        }
    }
}

/// Ilovaga tegishli fayl turlari. Kesh va loglar ilovani o'chirmasdan ham tozalanadi.
enum FileKind: String, CaseIterable {
    case cache, logs, support, prefs, container, other

    var title: String {
        switch self {
        case .cache: return L("Kesh", "Cache", "Кэш")
        case .logs: return L("Loglar", "Logs", "Журналы")
        case .support: return L("Ilova ma'lumotlari", "App data", "Данные приложения")
        case .prefs: return L("Sozlamalar", "Preferences", "Настройки")
        case .container: return L("Konteynerlar", "Containers", "Контейнеры")
        case .other: return L("Boshqa fayllar", "Other files", "Другие файлы")
        }
    }

    var isCache: Bool { self == .cache || self == .logs }
}

enum AppScanner {
    private static let fm = FileManager.default

    /// Kutubxonadagi papka va undagi fayllar qanday turga kirishi.
    private static let places: [(dir: String, kind: FileKind)] = [
        ("Caches", .cache), ("Logs", .logs), ("Application Support", .support), ("Preferences", .prefs),
        ("Containers", .container), ("Group Containers", .container), ("Saved Application State", .other),
        ("HTTPStorages", .other), ("WebKit", .other), ("Cookies", .other), ("LaunchAgents", .other),
        ("Application Scripts", .other),
    ]

    static func installedApps() -> [AppInfo] {
        var urls: [URL] = []
        for root in ["/Applications", Scanner.home.path + "/Applications"] {
            for url in Scanner.children(of: URL(fileURLWithPath: root)) {
                if url.pathExtension == "app" {
                    urls.append(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // "Adobe Illustrator 2026/" kabi papka ichidagi ilovalar.
                    urls += Scanner.children(of: url).filter { $0.pathExtension == "app" }
                }
            }
        }

        return urls.compactMap(appInfo)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// macOS'ning o'z ilovalari va Farrosh'ning o'zi uchun nil qaytaradi — ularni o'chirib bo'lmaydi.
    /// Apple'ning App Store'dan o'rnatiladigan ilovalari (Xcode, Pages, Keynote, Logic Pro…) ro'yxatda qoladi:
    /// ular oddiy ilova kabi /Applications'da turadi. Safari kabi tizim ilovalari esa aslida
    /// faqat o'qiladigan tizim diskida (/System/...) joylashgan, /Applications'da faqat havolasi bor.
    static func appInfo(for url: URL) -> AppInfo? {
        let bundle = Bundle(url: url)
        let id = bundle?.bundleIdentifier ?? ""
        if isSystemApp(url) { return nil }
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        var intelOnly = false
        #if arch(arm64)
        let archs = bundle?.executableArchitectures?.map(\.intValue) ?? []
        intelOnly = !archs.isEmpty && !archs.contains(NSBundleExecutableArchitectureARM64)
        #endif

        return AppInfo(
            url: url, name: url.deletingPathExtension().lastPathComponent, bundleID: id,
            version: version, isIntelOnly: intelOnly
        )
    }

    /// Ilova tizim diskida (macOS bilan birga keladigan, o'chirib bo'lmaydigan) joylashganmi.
    static func isSystemApp(_ url: URL) -> Bool {
        let real = url.resolvingSymlinksInPath().path
        if real.hasPrefix("/System/") { return true }
        return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
    }

    /// Spotlight yozib boradigan "oxirgi ochilgan" sana.
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func relatedFiles(for app: AppInfo) -> [FileKind: [CleanItem]] {
        let id = app.bundleID.lowercased()
        let bundle = Bundle(url: app.url)
        let names = Set(
            [app.name, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
             bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String]
                .compactMap { $0 }.map(normalize).filter { $0.count >= 3 }
        )
        let lowerName = app.name.lowercased()

        func matches(_ raw: String) -> Bool {
            var s = raw
            for ext in [".plist", ".savedState", ".binarycookies"] where s.hasSuffix(ext) { s.removeLast(ext.count) }
            if let team = s.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { s.removeSubrange(team) }
            if s.hasPrefix("group.") { s.removeFirst(6) }
            let l = s.lowercased()
            if !id.isEmpty && (l == id || l.hasPrefix(id + ".")) { return true }
            if names.contains(normalize(s)) { return true }
            // "Telegram Desktop" kabi papkalar.
            return lowerName.count >= 4 && l.hasPrefix(lowerName + " ")
        }

        var result: [FileKind: [CleanItem]] = [:]
        for place in places {
            for url in Scanner.children(of: Scanner.lib(place.dir)) where matches(url.lastPathComponent) {
                result[place.kind, default: []].append(item(url, kind: place.kind))
                // Konteyner ichidagi keshni alohida ko'rsatamiz — uni ilovani o'chirmasdan tozalash mumkin.
                let inner = url.appendingPathComponent("Data/Library/Caches")
                if place.dir == "Containers", fm.fileExists(atPath: inner.path) {
                    result[.cache, default: []].append(item(inner, kind: .cache))
                }
            }
        }
        for kind in result.keys {
            result[kind] = result[kind]?.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        }
        return result.filter { !$0.value.isEmpty }
    }

    /// Adobe kabi ishlab chiqaruvchilar ilova bilan birga o'z o'chirgichini qo'yadi.
    static func uninstaller(near app: AppInfo) -> URL? {
        let parent = app.url.deletingLastPathComponent()
        guard parent.path != "/Applications" else { return nil }
        return Scanner.children(of: parent).first {
            $0.pathExtension == "app" && $0.lastPathComponent.lowercased().contains("uninstall")
        }
    }

    private static func item(_ url: URL, kind: FileKind) -> CleanItem {
        let name = kind == .cache && url.lastPathComponent == "Caches"
            ? L("Konteyner keshi", "Container cache", "Кэш контейнера")
            : url.lastPathComponent
        return CleanItem(
            id: url.path, name: name, detail: Scanner.tildePath(url), urls: [url],
            size: Scanner.size(of: url), selected: true
        )
    }

    private static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

// MARK: - Ilovalar ro'yxati

@MainActor
final class AppsStore: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var query = ""
    @Published var sort = AppSort.name
    @Published var selectedID: String?
    /// Bir nechta ilovani birdan o'chirish uchun belgilanganlar.
    @Published var checked: Set<String> = []

    var selectedApp: AppInfo? { apps.first { $0.id == selectedID } }

    /// Farrosh o'zini o'chira olmaydi.
    static func canCheck(_ app: AppInfo) -> Bool { true }

    var checkedApps: [AppInfo] { apps.filter { checked.contains($0.id) } }
    var checkedSize: Int64 { checkedApps.reduce(0) { $0 + ($1.size ?? 0) } }

    private var checkableVisible: [AppInfo] { visible.filter(AppsStore.canCheck) }

    var allVisibleChecked: Bool {
        let list = checkableVisible
        return !list.isEmpty && list.allSatisfy { checked.contains($0.id) }
    }

    func toggleCheck(_ app: AppInfo) {
        guard AppsStore.canCheck(app) else { NSSound.beep(); return }
        if checked.contains(app.id) { checked.remove(app.id) } else { checked.insert(app.id) }
    }

    /// Qidiruv natijasidagi hamma ilovani belgilaydi yoki belgini olib tashlaydi.
    func setAllVisible(_ on: Bool) {
        let ids = checkableVisible.map(\.id)
        if on { checked.formUnion(ids) } else { checked.subtract(ids) }
    }

    var visible: [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .name: return list
        case .size: return list.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        // Eng uzoq ochilmaganlar tepada; sanasi noma'lumlar oxirida.
        case .lastUsed: return list.sorted { ($0.lastUsed ?? .distantFuture) < ($1.lastUsed ?? .distantFuture) }
        }
    }

    var unusedCount: Int { apps.filter(\.isUnused).count }

    var totalSize: Int64 { apps.reduce(0) { $0 + ($1.size ?? 0) } }

    func load() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let list = AppScanner.installedApps()
            await MainActor.run { self.apps = list }
            for app in list {
                let size = Scanner.size(of: app.url)
                let used = AppScanner.lastUsed(app.url)
                await MainActor.run {
                    if let i = self.apps.firstIndex(where: { $0.id == app.id }) {
                        self.apps[i].size = size
                        self.apps[i].lastUsed = used
                    }
                }
            }
            await MainActor.run { self.loading = false }
        }
    }

    func reload() {
        guard !loading else { return }
        apps = []
        load()
    }

    private var watcher: FolderWatcher?

    /// /Applications'ga ilova qo'shilsa yoki undan olib tashlansa, ro'yxat o'zi yangilanadi.
    func startWatching() {
        guard watcher == nil else { return }
        let paths = ["/Applications", Scanner.home.appendingPathComponent("Applications").path]
        watcher = FolderWatcher(paths: paths) { [weak self] changed in
            // Ilova ichidagi fayllar (yangilanish, kesh) emas — faqat ilovaning o'zi qo'shilgan/olingan bo'lsa.
            guard changed.contains(where: Self.touchesAppBundle) else { return }
            self?.refresh()
        }
    }

    private static func touchesAppBundle(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return true // papkaning o'zi o'zgardi
        }
        return i == parts.count - 1
    }

    /// Ro'yxatni tozalamasdan yangilaydi: yangi ilovalar qo'shiladi, o'chirilganlari olib tashlanadi,
    /// tanlov va hisoblangan hajmlar saqlanadi.
    func refresh() {
        guard !loading else { return }
        Task.detached(priority: .utility) {
            let fresh = AppScanner.installedApps()
            let known = await MainActor.run { Set(self.apps.map(\.id)) }
            let added = fresh.filter { !known.contains($0.id) }
            let ids = Set(fresh.map(\.id))
            await MainActor.run {
                self.apps.removeAll { !ids.contains($0.id) }
                self.checked.formIntersection(ids)
                if let sel = self.selectedID, !ids.contains(sel) { self.selectedID = nil }
                self.apps.append(contentsOf: added)
                self.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            for app in added {
                let size = Scanner.size(of: app.url)
                let used = AppScanner.lastUsed(app.url)
                await MainActor.run {
                    if let i = self.apps.firstIndex(where: { $0.id == app.id }) {
                        self.apps[i].size = size
                        self.apps[i].lastUsed = used
                    }
                }
            }
        }
    }

    func remove(_ app: AppInfo) {
        apps.removeAll { $0.id == app.id }
        checked.remove(app.id)
        if selectedID == app.id { selectedID = nil }
    }

    /// Sudrab tashlangan yoki ⌘O bilan tanlangan ilovani ro'yxatga qo'shib, tanlaydi.
    func show(_ app: AppInfo) {
        if !apps.contains(where: { $0.id == app.id }) { apps.append(app) }
        query = ""
        selectedID = app.id
    }
}

struct AppsEntryRow: View {
    @ObservedObject var apps: AppsStore
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "square.grid.2x2.fill", color: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Ilovalarni boshqarish", "Manage apps", "Управление приложениями"))
                Text(L("Ilovani butunlay o'chirish yoki keshini tozalash", "Uninstall apps completely or clear their caches", "Полностью удалить приложение или очистить его кэш"))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !apps.apps.isEmpty {
                Text("\(apps.apps.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibleRow(L("Ilovalarni boshqarish", "Manage apps", "Управление приложениями"),
                       value: apps.apps.isEmpty ? "" : L("\(apps.apps.count) ta ilova", "\(apps.apps.count) apps", "Приложений: \(apps.apps.count)"),
                       action: open)
    }
}

/// «Ilovalar» bo'limi: chapda ro'yxat, o'ngda tanlangan ilovaning fayllari.
struct AppsPane: View {
    @ObservedObject var apps: AppsStore
    let onRemoved: (AppInfo) -> Void

    var body: some View {
        GeometryReader { geo in
            content(listWidth: min(330, max(230, geo.size.width * 0.4)))
        }
    }

    /// Tor oynada ro'yxat ham torayadi, o'ng ustunga joy qoladi.
    private func content(listWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            list
                .frame(width: listWidth)
            Divider()
            if !apps.checked.isEmpty {
                BulkUninstallView(apps: apps, onRemoved: onRemoved)
            } else if let app = apps.selectedApp {
                // Hajm keyinroq hisoblanadi — kelganda sahifa yangilanadi.
                AppDetailView(app: app) {
                    apps.remove(app)
                    onRemoved(app)
                }
                .id("\(app.id)#\(app.size ?? -1)")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L("Ilovani tanlang", "Select an app", "Выберите приложение")).font(.title3.weight(.semibold))
                    Text(L("Chapdagi ro'yxatdan ilovani tanlang yoki uni shu oynaga sudrab tashlang.", "Pick an app from the list on the left, or drag one onto this window.", "Выберите приложение в списке слева или перетащите его в это окно."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L("Ilovalar", "Applications", "Приложения"))
            }
        }
    }

    private var selectAllRow: some View {
        let all = apps.allVisibleChecked
        return HStack(spacing: 10) {
            Button { apps.setAllVisible(!all) } label: {
                HStack(spacing: 10) {
                    Image(systemName: all ? "checkmark.circle.fill"
                          : apps.checked.isEmpty ? "circle" : "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(apps.checked.isEmpty ? Color.secondary : Color.accentColor)
                        .frame(width: 28, height: 28)
                    Text(all ? L("Belgini olib tashlash", "Deselect all", "Снять выделение")
                             : L("Hammasini tanlash", "Select all", "Выбрать все"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Spacer()
            if !apps.checked.isEmpty {
                Text(L("\(apps.checked.count) ta tanlandi", "\(apps.checked.count) selected", "Выбрано: \(apps.checked.count)"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
    }

    private var list: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Ilova qidirish", "Search apps", "Поиск приложений"), text: $apps.query).textFieldStyle(.plain)
                    if !apps.query.isEmpty {
                        Button { apps.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Picker(L("Saralash", "Sort", "Сортировка"), selection: $apps.sort) {
                    ForEach(AppSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)

            Divider()

            if apps.apps.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if apps.visible.isEmpty {
                Spacer()
                Text(L("«\(apps.query)» bo'yicha ilova topilmadi", "No apps match «\(apps.query)»", "По запросу «\(apps.query)» ничего не найдено")).foregroundStyle(.secondary)
                Spacer()
            } else {
                selectAllRow
                Divider()
                List(selection: $apps.selectedID) {
                    ForEach(apps.visible) { app in
                        AppRow(app: app, checked: apps.checked.contains(app.id),
                               checkable: AppsStore.canCheck(app)) { apps.toggleCheck(app) }
                            .tag(app.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(L("\(apps.apps.count) ta ilova · jami \(apps.totalSize.bytes)", "\(apps.apps.count) apps · \(apps.totalSize.bytes) total", "Приложений: \(apps.apps.count) · всего \(apps.totalSize.bytes)"))
                    .fontWeight(.medium)
                    .monospacedDigit()
                if apps.unusedCount > 0 {
                    Text(L("\(apps.unusedCount) tasi 3 oydan beri ochilmagan", "\(apps.unusedCount) not opened in 3 months", "Не открывались 3 месяца: \(apps.unusedCount)"))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

struct AppRow: View {
    let app: AppInfo
    var checked = false
    var checkable = true
    var toggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            // Belgilash doirasi: qatorni bosish ilovani ochadi, doirani bosish uni ro'yxatga qo'shadi.
            Button(action: toggle) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary.opacity(checkable ? 1 : 0.35))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!checkable)
            .accessibilityLabel(checked ? L("Belgini olib tashlash: \(app.name)", "Unmark \(app.name)", "Снять отметку: \(app.name)") : L("O'chirish uchun belgilash: \(app.name)", "Mark \(app.name) for uninstall", "Отметить для удаления: \(app.name)"))
            .help(checkable ? L("O'chirish uchun belgilash", "Mark for uninstall", "Отметить для удаления")
                            : L("Farrosh o'zini o'chira olmaydi", "Farrosh can't uninstall itself", "Farrosh не может удалить сам себя"))
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if app.isIntelOnly {
                Badge(text: "Intel", color: .blue)
                    .help(L("Intel protsessor uchun yozilgan — Apple Silicon'da Rosetta orqali sekinroq ishlaydi", "Built for Intel — runs slower on Apple Silicon through Rosetta", "Создано для Intel — на Apple Silicon работает медленнее через Rosetta"))
            }
            if app.isUnused {
                Badge(text: L("Ishlatilmayapti", "Unused", "Не используется"), color: .yellow)
            }
            if let size = app.size {
                Text(size.bytes).monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !app.version.isEmpty { parts.append(L("Versiya", "Version", "Версия") + " \(app.version)") }
        if let used = app.lastUsed { parts.append(L("ochilgan: ", "opened ", "открыто ") + Scanner.ago(used)) }
        return parts.joined(separator: " · ")
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Bitta ilova

struct AppActionResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let success: Bool
    /// Ilova o'chirildimi — oyna yopilgach ro'yxatga qaytiladi.
    let removed: Bool
    var reveal: URL?
}

@MainActor
final class AppDetailModel: ObservableObject {
    let app: AppInfo
    @Published var files: [FileKind: [CleanItem]] = [:]
    @Published var loading = true
    @Published var working = false
    @Published var confirmCache = false
    @Published var confirmUninstall = false
    @Published var askQuit = false
    @Published var confirmReset = false
    /// Hozir bajarilayotgan ish — animatsiya kartasida ko'rsatiladi.
    @Published var activity = ""
    /// Ilova yopilgach bajariladigan amal.
    private var afterQuit: (() -> Void)?
    @Published var result: AppActionResult?
    let uninstaller: URL?

    init(app: AppInfo) {
        self.app = app
        uninstaller = AppScanner.uninstaller(near: app)
    }

    var isRunning: Bool {
        // Farrosh o'zini o'chirayotganda yopishni so'ramaydi — ish tugagach o'zi yopiladi.
        !app.isSelf && !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    var cacheItems: [CleanItem] { FileKind.allCases.filter(\.isCache).flatMap { files[$0] ?? [] } }
    var cacheSize: Int64 { cacheItems.reduce(0) { $0 + $1.size } }
    var filesSize: Int64 { files.values.joined().reduce(0) { $0 + $1.size } }
    var selectedFiles: [CleanItem] { files.values.joined().filter(\.selected) }
    var uninstallSize: Int64 { (app.size ?? 0) + selectedFiles.reduce(0) { $0 + $1.size } }

    func load() {
        loading = true
        let app = app
        Task.detached(priority: .userInitiated) {
            let found = AppScanner.relatedFiles(for: app)
            await MainActor.run {
                self.files = found
                self.loading = false
            }
        }
    }

    func toggle(_ item: CleanItem, in kind: FileKind) {
        guard let i = files[kind]?.firstIndex(where: { $0.id == item.id }) else { return }
        files[kind]?[i].selected.toggle()
    }

    func clearCache() {
        let items = cacheItems
        activity = L("Kesh tozalanmoqda…", "Clearing cache…", "Очистка кэша…")
        working = true
        let started = Date()
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let before = items.reduce(0) { $0 + $1.size }
            for url in items.flatMap(\.urls) {
                // Papkaning o'zini qoldirib, ichini tozalaymiz — ilova uni qayta yaratishi shart emas.
                for child in Scanner.children(of: url) { try? fm.removeItem(at: child) }
            }
            let left = Scanner.size(of: items.flatMap(\.urls))
            let freed = max(0, before - left)
            await AnimationPacing.holdUntilVisible(since: started)
            await MainActor.run {
                self.working = false
                self.result = AppActionResult(
                    title: L("\(freed.bytes) bo'shatildi", "\(freed.bytes) freed", "Освобождено \(freed.bytes)"),
                    message: left > 0
                        ? L("\(left.bytes) qoldi — ilova ochiq bo'lgani uchun ba'zi fayllar band.", "\(left.bytes) left — some files are in use because the app is open.", "Осталось \(left.bytes) — часть файлов занята, так как приложение открыто.")
                        : L("\(self.app.name) keshi tozalandi. Ilova kerakli qismini qayta yaratadi.", "\(self.app.name) cache cleared. The app will recreate what it needs.", "Кэш \(self.app.name) очищен. Приложение заново создаст нужное."),
                    success: true, removed: false
                )
                self.load()
            }
        }
    }

    /// Ilova ochiq bo'lsa, avval yopishni so'raydi.
    func requestUninstall() {
        if isRunning {
            afterQuit = { [weak self] in self?.uninstall() }
            askQuit = true
        } else {
            confirmUninstall = true
        }
    }

    func requestReset() {
        if isRunning {
            afterQuit = { [weak self] in self?.reset() }
            askQuit = true
        } else {
            confirmReset = true
        }
    }

    /// Ilovani qoldirib, barcha sozlama va ma'lumotlarini o'chiradi — xuddi yangi o'rnatilgandek.
    func reset() {
        activity = L("Asl holatiga qaytarilmoqda…", "Resetting…", "Сброс…")
        working = true
        let app = app
        let urls = outermost(files.values.joined().flatMap(\.urls))
        let total = filesSize

        Task.detached(priority: .userInitiated) {
            var failed = 0
            for url in urls { do { try Remover.discard(url) } catch { failed += 1 } }
            let failedCount = failed
            await MainActor.run {
                self.working = false
                self.result = AppActionResult(
                    title: L("\(app.name) asl holatiga qaytdi", "\(app.name) has been reset", "\(app.name) сброшено"),
                    message: L("Sozlama va ma'lumotlar (\(total.bytes)) \(Remover.doneVerb). Ilova keyingi ochilishida yangidek ishga tushadi.", "Settings and data (\(total.bytes)) \(Remover.doneVerb). The app will start fresh next time.", "Настройки и данные (\(total.bytes)) \(Remover.doneVerb). При следующем запуске приложение откроется как новое.")
                        + (failedCount > 0 ? L(" \(failedCount) ta fayl o'chmadi (band yoki himoyalangan).", " \(failedCount) files weren't removed (in use or protected).", " Не удалено файлов: \(failedCount) (заняты или защищены).") : ""),
                    success: failedCount == 0, removed: false
                )
                self.load()
            }
        }
    }

    /// Ichma-ich joylashgan yo'llardan faqat tashqisini qoldiradi (konteyner va uning keshi).
    private func outermost(_ urls: [URL]) -> [URL] {
        urls.filter { url in !urls.contains { $0 != url && url.path.hasPrefix($0.path + "/") } }
    }

    func quitAndContinue() {
        working = true
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }
        Task {
            for _ in 0..<20 where isRunning { try? await Task.sleep(nanoseconds: 300_000_000) }
            if isRunning {
                working = false
                result = AppActionResult(
                    title: L("Ilova yopilmadi", "The app didn't quit", "Приложение не закрылось"),
                    message: L("\(app.name) hali ochiq. Uni o'zingiz yoping (⌘Q) va qayta urinib ko'ring.", "\(app.name) is still open. Quit it yourself (⌘Q) and try again.", "\(app.name) всё ещё открыто. Закройте его (⌘Q) и попробуйте снова."),
                    success: false, removed: false
                )
            } else {
                working = false
                afterQuit?()
                afterQuit = nil
            }
        }
    }

    func uninstall() {
        activity = L("O'chirilmoqda…", "Uninstalling…", "Удаление…")
        working = true
        let app = app
        if app.isSelf { SelfRemoval.prepare() }
        let urls = outermost([app.url] + selectedFiles.flatMap(\.urls))
        let total = uninstallSize

        Task.detached(priority: .userInitiated) {
            var failed: [URL] = []
            for url in urls {
                do { try Remover.discard(url) } catch { failed.append(url) }
            }
            // Administrator o'rnatgan ilova (Xcode kabi): macOS parol so'raydi.
            if failed.contains(app.url) {
                let done = await MainActor.run { Remover.discardAsAdmin([app.url]) }
                failed.removeAll { done.contains($0) }
            }
            let appFailed = failed.contains(app.url)
            let leftFiles = failed.filter { $0 != app.url }.count

            await MainActor.run {
                self.working = false
                if appFailed {
                    self.result = AppActionResult(
                        title: L("Ilovani o'chirib bo'lmadi", "Couldn't uninstall the app", "Не удалось удалить приложение"),
                        message: L("\(app.name) administrator nomidan o'rnatilgan, uni o'chirish uchun parol kerak, lekin parol kiritilmadi. Qaytadan urinib ko'ring yoki Finder'da Savatga sudrab tashlang.", "\(app.name) was installed by an administrator and needs a password to remove, but the password wasn't entered. Try again or drag it to the Trash in Finder.", "\(app.name) установлено администратором, для удаления нужен пароль, но он не был введён. Попробуйте ещё раз или перетащите приложение в Корзину в Finder.")
                            + (urls.count > 1 ? L(" Ilova fayllari Savatga ko'chirildi.", " The app's files were moved to the Trash.", " Файлы приложения перемещены в Корзину.") : ""),
                        success: false, removed: false, reveal: app.url
                    )
                } else {
                    if app.isSelf { SelfRemoval.removed = true }
                    self.result = AppActionResult(
                        title: L("\(app.name) o'chirildi", "\(app.name) uninstalled", "\(app.name) удалено"),
                        message: "\(total.bytes) \(Remover.doneVerb)."
                            + (Remover.permanent ? "" : L(" Savatni bo'shatsangiz, bu joy bo'shaydi.", " Empty the Trash to free this space.", " Очистите Корзину, чтобы освободить место."))
                            + (app.isSelf ? SelfRemoval.note : "")
                            + (leftFiles > 0 ? L(" \(leftFiles) ta fayl ko'chmadi (band yoki himoyalangan).", " \(leftFiles) files weren't moved (in use or protected).", " Не перемещено файлов: \(leftFiles) (заняты или защищены).") : ""),
                        success: true, removed: true
                    )
                }
            }
        }
    }
}

struct AppDetailView: View {
    @StateObject private var model: AppDetailModel
    private let onRemoved: () -> Void

    init(app: AppInfo, onRemoved: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AppDetailModel(app: app))
        self.onRemoved = onRemoved
    }

    var body: some View {
        Form {
            Section { header }

            if let uninstaller = model.uninstaller {
                Section {
                    HStack(spacing: 12) {
                        IconTile(symbol: "info", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Bu ilovaning o'z o'chirgichi bor", "This app has its own uninstaller", "У этого приложения есть свой деинсталлятор"))
                            Text(L("To'liq tozalash uchun avval shu o'chirgichdan foydalanish tavsiya etiladi.", "For a complete removal, it's best to run it first.", "Для полного удаления лучше сначала запустить его."))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Ochish", "Open", "Открыть")) { NSWorkspace.shared.open(uninstaller) }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "arrow.counterclockwise", color: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Asl holatiga qaytarish", "Reset", "Сбросить"))
                        Text(L("Ilova qoladi, barcha sozlama va ma'lumotlari o'chadi — xuddi yangi o'rnatilgandek.", "Keeps the app but removes all its settings and data — as if freshly installed.", "Приложение остаётся, но все его настройки и данные удаляются — как после новой установки."))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Qaytarish", "Reset", "Сбросить")) { model.requestReset() }
                        .disabled(model.working || model.loading || model.files.isEmpty || model.app.isSelf)
                }
                .padding(.vertical, 3)
                .alert(L("\(model.app.name) asl holatiga qaytarilsinmi?", "Reset \(model.app.name)?", "Сбросить \(model.app.name)?"), isPresented: $model.confirmReset) {
                    Button(L("Qaytarish", "Reset", "Сбросить"), role: .destructive) { model.reset() }
                    Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
                } message: {
                    Text(Remover.permanent
                         ? L("Ilovaning barcha fayllari (\(model.filesSize.bytes)) butunlay o'chadi: sozlamalar, kirish ma'lumotlari, saqlangan holat. Ilovaning o'zi qoladi.", "All of the app's files (\(model.filesSize.bytes)) will be deleted for good: settings, sign-in data, saved state. The app itself stays.", "Все файлы приложения (\(model.filesSize.bytes)) будут удалены навсегда: настройки, данные входа, сохранённое состояние. Само приложение останется.")
                         : L("Ilovaning barcha fayllari (\(model.filesSize.bytes)) Savatga ko'chiriladi: sozlamalar, kirish ma'lumotlari, saqlangan holat. Ilovaning o'zi qoladi.", "All of the app's files (\(model.filesSize.bytes)) will be moved to the Trash: settings, sign-in data, saved state. The app itself stays.", "Все файлы приложения (\(model.filesSize.bytes)) будут перемещены в Корзину: настройки, данные входа, сохранённое состояние. Само приложение останется."))
                }
            }

            if model.loading {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
            } else if model.files.isEmpty {
                Section {
                    Text(L("Ilovaning o'zidan boshqa fayl topilmadi", "No files found besides the app itself", "Кроме самого приложения, файлов не найдено"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                ForEach(FileKind.allCases, id: \.self) { kind in
                    if let list = model.files[kind] {
                        Section {
                            ForEach(list) { item in
                                ItemRow(item: item) { model.toggle(item, in: kind) }
                                    .disabled(model.working)
                            }
                        } header: {
                            Text("\(kind.title) · \(list.reduce(0) { $0 + $1.size }.bytes)")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if model.working {
                CleaningOverlay(title: model.activity.isEmpty ? L("Bajarilmoqda…", "Working…", "Выполняется…") : model.activity,
                                subtitle: model.app.name)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.working)
        .navigationTitle(model.app.name)
        .safeAreaInset(edge: .bottom) { actionBar }
        .alert(L("Keshni tozalash", "Clear cache", "Очистить кэш"), isPresented: $model.confirmCache) {
            Button(L("Tozalash", "Clean", "Очистить"), role: .destructive) { model.clearCache() }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L("\(model.app.name) keshi va loglari (\(model.cacheSize.bytes)) butunlay o'chiriladi. Ilovaning o'zi va sozlamalari qoladi.", "The cache and logs of \(model.app.name) (\(model.cacheSize.bytes)) will be deleted for good. The app and its settings stay.", "Кэш и журналы \(model.app.name) (\(model.cacheSize.bytes)) будут удалены навсегда. Приложение и его настройки останутся."))
        }
        .sheet(item: $model.result) { result in
            AppResultView(result: result) {
                model.result = nil
                if result.removed { onRemoved() }
                SelfRemoval.quitIfRemoved()
            }
        }
        .task { model.load() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.app.url.path))
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.app.name).font(.title2.weight(.semibold))
                Text([model.app.version.isEmpty ? nil : L("Versiya", "Version", "Версия") + " \(model.app.version)", model.app.bundleID]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(L("Ilova", "App", "Приложение") + ": \((model.app.size ?? 0).bytes) · " + L("Fayllari", "Files", "Файлы") + ": \(model.loading ? "…" : model.filesSize.bytes)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    if let used = model.app.lastUsed {
                        Text(L("Oxirgi marta \(Scanner.ago(used)) ochilgan", "Last opened \(Scanner.ago(used))", "Последний запуск \(Scanner.ago(used))")).foregroundStyle(.secondary)
                    }
                    if model.app.isIntelOnly { Badge(text: "Intel", color: .blue) }
                    if model.app.isUnused { Badge(text: L("Ishlatilmayapti", "Unused", "Не используется"), color: .yellow) }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button { model.confirmCache = true } label: {
            Text(model.cacheSize > 0 ? L("Keshni tozalash", "Clear cache", "Очистить кэш") + " · \(model.cacheSize.bytes)" : L("Kesh toza", "Cache is clean", "Кэш чист"))
        }
        .buttonStyle(PrimaryButtonStyle(tint: .accentColor, prominent: false))
        .disabled(model.working || model.loading || model.cacheSize == 0)

        Button { model.requestUninstall() } label: {
            HStack(spacing: 8) {
                if model.working { ProgressView().controlSize(.small).tint(.white) }
                Text(model.working ? L("Bajarilmoqda…", "Working…", "Выполняется…") : L("O'chirish", "Uninstall", "Удалить") + " · \(model.uninstallSize.bytes)")
            }
        }
        .buttonStyle(PrimaryButtonStyle(tint: .red))
        .disabled(model.working || model.loading)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            // Keng ustunda tugmalar yonma-yon, torida ustma-ust turadi.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actionButtons }.frame(minWidth: 420)
                VStack(spacing: 10) { actionButtons }
            }
            .frame(maxWidth: FormMetrics.contentWidth)
            .frame(maxWidth: .infinity)
            .alert(L("\(model.app.name) o'chirilsinmi?", "Uninstall \(model.app.name)?", "Удалить \(model.app.name)?"), isPresented: $model.confirmUninstall) {
                Button(L("O'chirish", "Uninstall", "Удалить"), role: .destructive) { model.uninstall() }
                Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
            } message: {
                Text(Remover.permanent
                     ? L("Ilova va tanlangan \(model.selectedFiles.count) ta fayli (jami \(model.uninstallSize.bytes)) butunlay o'chiriladi. Buni qaytarib bo'lmaydi.", "The app and \(model.selectedFiles.count) selected files (\(model.uninstallSize.bytes) in total) will be deleted for good. This can't be undone.", "Приложение и выбранные файлы (\(model.selectedFiles.count), всего \(model.uninstallSize.bytes)) будут удалены навсегда. Это нельзя отменить.")
                     : L("Ilova va tanlangan \(model.selectedFiles.count) ta fayli (jami \(model.uninstallSize.bytes)) Savatga ko'chiriladi. Savatni bo'shatmaguningizcha qaytarib olish mumkin.", "The app and \(model.selectedFiles.count) selected files (\(model.uninstallSize.bytes) in total) will be moved to the Trash. You can restore them until you empty it.", "Приложение и выбранные файлы (\(model.selectedFiles.count), всего \(model.uninstallSize.bytes)) будут перемещены в Корзину. Их можно вернуть, пока Корзина не очищена."))
            }
            .alert(L("\(model.app.name) hozir ochiq", "\(model.app.name) is open", "\(model.app.name) сейчас открыто"), isPresented: $model.askQuit) {
                Button(L("Yopib davom etish", "Quit and continue", "Закрыть и продолжить"), role: .destructive) { model.quitAndContinue() }
                Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
            } message: {
                Text(L("Davom etishdan oldin ilova yopiladi. Saqlanmagan ishlaringizni avval saqlab oling.", "The app will be quit before continuing. Save any unsaved work first.", "Перед продолжением приложение будет закрыто. Сначала сохраните несохранённую работу."))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }
}

struct AppResultView: View {
    let result: AppActionResult
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            SuccessBadge(success: result.success, size: 60)
                .padding(.top, 8)
            Text(result.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(result.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = result.reveal {
                Button(L("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(PrimaryButtonStyle(prominent: false))
            }
            Button(L("Tayyor", "Done", "Готово"), action: done)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 400)
    }
}

// MARK: - Bir nechta ilovani birdan o'chirish

@MainActor
final class BulkUninstallModel: ObservableObject {
    @Published var includeLeftovers = true
    @Published var working = false
    @Published var progress = ""
    @Published var confirming = false
    /// Ochiq turgan ilovalar — o'chirishdan oldin yopish so'raladi.
    @Published var runningNames: [String] = []
    @Published var result: AppActionResult?

    func running(_ apps: [AppInfo]) -> [AppInfo] {
        apps.filter { !$0.isSelf && !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    func request(_ apps: [AppInfo]) {
        let open = running(apps)
        if open.isEmpty { confirming = true } else { runningNames = open.map(\.name) }
    }

    func quitRunningThenConfirm(_ apps: [AppInfo]) {
        let open = running(apps)
        runningNames = []
        for app in open {
            for r in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { r.terminate() }
        }
        working = true
        progress = L("Ilovalar yopilmoqda…", "Quitting apps…", "Закрываем приложения…")
        Task {
            for _ in 0..<20 where !running(apps).isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            working = false
            progress = ""
            confirming = true
        }
    }

    func uninstall(_ apps: [AppInfo], store: AppsStore, onRemoved: @escaping (AppInfo) -> Void) {
        let leftovers = includeLeftovers
        // Hali ochiq qolganlarga tegmaymiz.
        let still = Set(running(apps).map(\.id))
        // Farrosh'ning o'zi eng oxirida o'chiriladi.
        let targets = apps.filter { !still.contains($0.id) }.sorted { !$0.isSelf && $1.isSelf }
        if targets.contains(where: \.isSelf) { SelfRemoval.prepare() }
        working = true

        Task.detached(priority: .userInitiated) {
            var removed: [AppInfo] = []
            var failed: [String] = []
            var needAdmin: [(AppInfo, [URL], Int64)] = []
            var total: Int64 = 0
            for (i, app) in targets.enumerated() {
                await MainActor.run { self.progress = L("\(app.name) o'chirilmoqda… (\(i + 1)/\(targets.count))", "Uninstalling \(app.name)… (\(i + 1)/\(targets.count))", "Удаляем \(app.name)… (\(i + 1)/\(targets.count))") }
                let files = leftovers ? AppScanner.relatedFiles(for: app).values.joined().filter(\.selected) : []
                let all = [app.url] + files.flatMap(\.urls)
                let urls = all.filter { url in !all.contains { $0 != url && url.path.hasPrefix($0.path + "/") } }
                do {
                    try Remover.discard(app.url)
                    for url in urls where url != app.url { try? Remover.discard(url) }
                    removed.append(app)
                    total += (app.size ?? 0) + files.reduce(0) { $0 + $1.size }
                } catch {
                    needAdmin.append((app, urls.filter { $0 != app.url }, files.reduce(0) { $0 + $1.size }))
                }
            }
            // Parol kerak bo'lganlar uchun macOS bitta oynada bir marta so'raydi.
            if !needAdmin.isEmpty {
                let appURLs = needAdmin.map { $0.0.url }
                let done = await MainActor.run { Remover.discardAsAdmin(appURLs) }
                for (app, rest, filesSize) in needAdmin {
                    if done.contains(app.url) {
                        for url in rest { try? Remover.discard(url) }
                        removed.append(app)
                        total += (app.size ?? 0) + filesSize
                    } else {
                        failed.append(app.name)
                    }
                }
            }
            let skipped = apps.filter { still.contains($0.id) }.map(\.name)
            let removedApps = removed, failedNames = failed, freed = total
            await MainActor.run {
                let removed = removedApps, failed = failedNames, total = freed
                for app in removed { store.remove(app); onRemoved(app) }
                if removed.contains(where: \.isSelf) { SelfRemoval.removed = true }
                self.working = false
                self.progress = ""
                var message = L("\(removed.count) ta ilova, \(total.bytes) \(Remover.doneVerb).",
                                "\(removed.count) apps, \(total.bytes) \(Remover.doneVerb).",
                                "Приложений: \(removed.count), \(total.bytes) \(Remover.doneVerb).")
                if !failed.isEmpty {
                    message += L(" O'chmadi: \(failed.joined(separator: ", ")) — administrator paroli kiritilmadi. Qaytadan urinib ko'ring yoki Finder'da Savatga sudrab tashlang.",
                                 " Not removed: \(failed.joined(separator: ", ")) — the administrator password wasn't entered. Try again or drag them to the Trash in Finder.",
                                 " Не удалены: \(failed.joined(separator: ", ")) — пароль администратора не введён. Попробуйте ещё раз или перетащите их в Корзину в Finder.")
                }
                if !skipped.isEmpty {
                    message += L(" Ochiq qolgani uchun tegilmadi: \(skipped.joined(separator: ", ")).",
                                 " Left alone because still open: \(skipped.joined(separator: ", ")).",
                                 " Не тронуты, так как открыты: \(skipped.joined(separator: ", ")).")
                }
                if removed.contains(where: \.isSelf) { message += SelfRemoval.note }
                self.result = AppActionResult(
                    title: removed.isEmpty ? L("Ilovalar o'chirilmadi", "No apps were uninstalled", "Приложения не удалены")
                                           : L("\(removed.count) ta ilova o'chirildi", "\(removed.count) apps uninstalled", "Удалено приложений: \(removed.count)"),
                    message: message,
                    success: !removed.isEmpty && failed.isEmpty,
                    removed: !removed.isEmpty
                )
            }
        }
    }
}

struct BulkUninstallView: View {
    @ObservedObject var apps: AppsStore
    let onRemoved: (AppInfo) -> Void
    @StateObject private var model = BulkUninstallModel()

    var body: some View {
        let list = apps.checkedApps.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: "square.stack.3d.up.fill", color: .teal, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("\(list.count) ta ilova tanlandi", list.count == 1 ? "1 app selected" : "\(list.count) apps selected", "Выбрано приложений: \(list.count)"))
                            .font(.title3.weight(.semibold))
                        Text(L("Ilovalarning o'zi \(apps.checkedSize.bytes)", "The apps themselves take \(apps.checkedSize.bytes)", "Сами приложения занимают \(apps.checkedSize.bytes)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button(L("Belgini olib tashlash", "Deselect all", "Снять выделение")) { apps.checked = [] }
                        .buttonStyle(.borderless)
                        .disabled(model.working)
                }
                .padding(.vertical, 4)

                Toggle(isOn: $model.includeLeftovers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sozlama va keshlarini ham o'chirish", "Also remove their settings and caches", "Удалить также настройки и кэш"))
                        Text(L("Ilova o'chgach ~/Library'da qolib ketadigan fayllar", "Files that stay behind in ~/Library after an app is gone", "Файлы, которые остаются в ~/Library после удаления"))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.working)
            }

            Section {
                ForEach(list) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 28, height: 28)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        if let size = app.size {
                            Text(size.bytes).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button { apps.toggleCheck(app) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help(L("Ro'yxatdan olib tashlash", "Remove from the list", "Убрать из списка"))
                        .disabled(model.working)
                    }
                }
            } header: {
                Text(L("O'chiriladigan ilovalar", "Apps to uninstall", "Приложения к удалению"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Ilovalar", "Applications", "Приложения"))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button { model.request(list) } label: {
                    HStack(spacing: 8) {
                        if model.working { ProgressView().controlSize(.small).tint(.white) }
                        Text(model.working ? model.progress
                             : L("\(list.count) ta ilovani o'chirish", list.count == 1 ? "Uninstall 1 app" : "Uninstall \(list.count) apps", "Удалить приложения (\(list.count))"))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: .red))
                .disabled(model.working || list.isEmpty)
                .frame(maxWidth: FormMetrics.contentWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(.bar)
        }
        .alert(L("\(list.count) ta ilova o'chirilsinmi?", list.count == 1 ? "Uninstall 1 app?" : "Uninstall \(list.count) apps?", "Удалить приложения (\(list.count))?"),
               isPresented: $model.confirming) {
            Button(L("O'chirish", "Uninstall", "Удалить"), role: .destructive) {
                model.uninstall(list, store: apps, onRemoved: onRemoved)
            }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text((Remover.permanent
                  ? L("Ilovalar butunlay o'chiriladi, ularni qaytarib bo'lmaydi.", "The apps will be deleted for good and can't be restored.", "Приложения будут удалены навсегда.")
                  : L("Ilovalar Savatga ko'chiriladi — kerak bo'lsa qaytarib olasiz.", "The apps go to the Trash, so you can restore them if needed.", "Приложения попадут в Корзину — их можно вернуть."))
                 + (model.includeLeftovers ? L(" Sozlama va keshlari ham o'chadi.", " Their settings and caches go too.", " Их настройки и кэш тоже будут удалены.") : ""))
        }
        .alert(L("Bu ilovalar hozir ochiq", "These apps are open", "Эти приложения открыты"),
               isPresented: Binding(get: { !model.runningNames.isEmpty }, set: { if !$0 { model.runningNames = [] } })) {
            Button(L("Yopib davom etish", "Quit and continue", "Закрыть и продолжить")) { model.quitRunningThenConfirm(list) }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L("\(model.runningNames.joined(separator: ", ")) ochiq. O'chirishdan oldin ularni yopish kerak — saqlanmagan ishlaringizni saqlab qo'ying.",
                   "\(model.runningNames.joined(separator: ", ")) are open. They need to quit first — save any unsaved work.",
                   "\(model.runningNames.joined(separator: ", ")) открыты. Их нужно закрыть — сохраните несохранённое."))
        }
        .sheet(item: $model.result) { result in
            AppResultView(result: result) { model.result = nil; SelfRemoval.quitIfRemoved() }
        }
    }
}

/// Farrosh o'zini o'chirganda: kirishda ochilishni o'chiradi va natija oynasi yopilgach dasturni yopadi.
@MainActor
enum SelfRemoval {
    static var removed = false

    static var note: String {
        L(" Farrosh yopiladi.", " Farrosh will now quit.", " Farrosh сейчас закроется.")
    }

    /// Mac yonganda Farrosh ochilmasin.
    static func prepare() {
        try? SMAppService.mainApp.unregister()
    }

    static func quitIfRemoved() {
        guard removed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }
}
