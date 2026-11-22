import SwiftUI

// MARK: - Ishga tushish dasturlari

/// Mac yoqilganda yoki tizimga kirilganda o'zi ishga tushadigan narsalar.
enum StartupKind: Int, CaseIterable, Identifiable {
    case loginItem, userAgent, globalAgent, daemon

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .loginItem: return L("Kirishda ochiladigan ilovalar", "Open at login", "Открываются при входе")
        case .userAgent: return L("Fon xizmatlari — faqat siz uchun", "Background agents — just you", "Фоновые агенты — только для вас")
        case .globalAgent: return L("Fon xizmatlari — barcha foydalanuvchilar", "Background agents — all users", "Фоновые агенты — все пользователи")
        case .daemon: return L("Tizim xizmatlari", "System daemons", "Системные службы")
        }
    }

    var footer: String {
        switch self {
        case .loginItem:
            return L("Tizimga kirganingizda shu ilovalar o'zi ochiladi. Ro'yxatdan olib tashlansa, ilovaning o'zi qoladi.",
                     "These apps open by themselves when you log in. Removing one keeps the app itself.",
                     "Эти приложения открываются сами при входе. При удалении из списка само приложение остаётся.")
        case .userAgent:
            return L("Ilovalar qo'ygan yangilovchi va yordamchi dasturlar. O'chirilgani keyingi kirishda ham ishga tushmaydi.",
                     "Updaters and helpers installed by apps. A disabled one stays off after the next login too.",
                     "Обновляторы и помощники, установленные приложениями. Отключённый агент не запустится и после следующего входа.")
        case .globalAgent:
            return L("Bular barcha foydalanuvchilar uchun o'rnatilgan, lekin o'chirish faqat sizning hisobingizga ta'sir qiladi.",
                     "These are installed for all users, but turning one off affects only your account.",
                     "Установлены для всех пользователей, но отключение действует только для вашей учётной записи.")
        case .daemon:
            return L("Mac yoqilishi bilan ishga tushadi. Yoqish yoki o'chirish uchun macOS administrator parolini so'raydi.",
                     "Start when the Mac boots. macOS asks for an administrator password to turn them on or off.",
                     "Запускаются при включении Mac. Для включения или отключения macOS запросит пароль администратора.")
        }
    }

    var dir: String? {
        switch self {
        case .loginItem: return nil
        case .userAgent: return Scanner.home.path + "/Library/LaunchAgents"
        case .globalAgent: return "/Library/LaunchAgents"
        case .daemon: return "/Library/LaunchDaemons"
        }
    }

    /// launchctl domeni: agentlar foydalanuvchi seansida, daemonlar tizimda ishlaydi.
    var domain: String { self == .daemon ? "system" : "gui/\(getuid())" }
}

struct StartupItem: Identifiable, Hashable {
    let kind: StartupKind
    /// launchd yorlig'i yoki kirish elementining nomi.
    let label: String
    let name: String
    let detail: String
    let plist: URL?
    /// Ikonka va «Finder'da ko'rsatish» uchun ilova yoki dastur yo'li.
    let target: URL?
    var enabled: Bool
    let running: Bool
    /// Dastur yoki ilova diskda yo'q — o'chirilgan ilovadan qolgan.
    let missing: Bool

    var id: String { "\(kind.rawValue):\(label)" }
}

enum StartupScanner {
    /// Fon xizmatlari — tez, ruxsat so'ramaydi.
    static func scanServices() -> [StartupItem] {
        let guiOverrides = disabledOverrides("gui/\(getuid())")
        let systemOverrides = disabledOverrides("system")
        let running = runningLabels()

        var items: [StartupItem] = []
        for kind in [StartupKind.userAgent, .globalAgent, .daemon] {
            guard let dir = kind.dir else { continue }
            let overrides = kind == .daemon ? systemOverrides : guiOverrides
            for url in Scanner.children(of: URL(fileURLWithPath: dir)) where url.pathExtension == "plist" {
                items.append(item(plist: url, kind: kind, overrides: overrides, running: running))
            }
        }

        return sorted(items)
    }

    static func sorted(_ items: [StartupItem]) -> [StartupItem] {
        items.sorted { ($0.kind.rawValue, $0.name.lowercased()) < ($1.kind.rawValue, $1.name.lowercased()) }
    }

    private static func item(plist: URL, kind: StartupKind, overrides: [String: Bool], running: Set<String>) -> StartupItem {
        let dict = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
        let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first

        var app: URL?
        if let program { app = enclosingApp(program) }
        if app == nil, let ids = dict["AssociatedBundleIdentifiers"] as? [String] {
            app = ids.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        }
        let missing = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false

        let disabledInPlist = dict["Disabled"] as? Bool ?? false
        let enabled = overrides[label].map { !$0 } ?? !disabledInPlist

        return StartupItem(
            kind: kind, label: label,
            name: app?.deletingPathExtension().lastPathComponent ?? label,
            detail: label + (program.map { " · " + Scanner.tildePath(URL(fileURLWithPath: $0)) } ?? ""),
            plist: plist,
            target: app ?? program.map { URL(fileURLWithPath: $0) },
            enabled: enabled,
            running: running.contains(label),
            missing: missing
        )
    }

    /// "/Applications/Foo.app/Contents/MacOS/foo" → "/Applications/Foo.app".
    private static func enclosingApp(_ path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// `launchctl print-disabled` — foydalanuvchi o'chirib qo'ygan xizmatlar.
    private static func disabledOverrides(_ domain: String) -> [String: Bool] {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain]).output
        var result: [String: Bool] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            result[label] = value == "disabled" || value == "true"
        }
        return result
    }

    /// `launchctl list` — hozir jarayoni bor (PID raqamli) xizmatlar.
    private static func runningLabels() -> Set<String> {
        var result: Set<String> = []
        for line in Shell.run("/bin/launchctl", ["list"]).output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t")
            if cols.count == 3, Int(cols[0]) != nil { result.insert(String(cols[2])) }
        }
        return result
    }

    /// Kirish elementlarini System Events orqali o'qiydi — macOS bir marta ruxsat so'raydi.
    static func loginItems() -> (items: [StartupItem], error: String?) {
        let script = """
        set out to ""
        tell application "System Events"
            repeat with li in login items
                set out to out & (name of li) & tab & (path of li) & linefeed
            end repeat
        end tell
        return out
        """
        let result = Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            return ([], L("Kirishda ochiladigan ilovalarni ko'rish uchun Farrosh'ga «System Events»ni boshqarishga ruxsat bering.",
                          "To see apps that open at login, allow Farrosh to control «System Events».",
                          "Чтобы увидеть приложения, открывающиеся при входе, разрешите Farrosh управлять «System Events»."))
        }
        let items = result.output.split(separator: "\n").compactMap { line -> StartupItem? in
            let parts = line.components(separatedBy: "\t")
            guard let name = parts.first, !name.isEmpty else { return nil }
            // Ilova o'chirilgan bo'lsa, AppleScript yo'l o'rniga "missing value" qaytaradi.
            let raw = parts.count > 1 ? parts[1] : ""
            let path = raw == "missing value" ? "" : raw
            let exists = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            return StartupItem(
                kind: .loginItem, label: name, name: name,
                detail: path.isEmpty
                    ? L("Ilova Mac'da topilmadi", "The app isn't on this Mac", "Приложения нет на этом Mac")
                    : Scanner.tildePath(URL(fileURLWithPath: path)),
                plist: nil, target: exists ? URL(fileURLWithPath: path) : nil,
                enabled: true, running: false, missing: !exists
            )
        }
        return (items, nil)
    }
}

/// Buyruqni ishga tushirib, natijasini qaytaradi.
enum Shell {
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Qobiq uchun xavfsiz qo'shtirnoq.
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Administrator huquqi bilan — parolni macOS o'zi so'raydi.
    static func runAsAdmin(_ command: String) -> Bool {
        run("/usr/bin/osascript", [
            "-e", "on run argv", "-e", "do shell script (item 1 of argv) with administrator privileges", "-e", "end run",
            command,
        ]).status == 0
    }
}

enum StartupActions {
    static func setEnabled(_ item: StartupItem, _ on: Bool) -> Bool {
        let service = "\(item.kind.domain)/\(item.label)"
        let plist = item.plist?.path ?? ""
        if item.kind == .daemon {
            let cmd = on
                ? "/bin/launchctl enable \(Shell.quote(service)) && (/bin/launchctl bootstrap system \(Shell.quote(plist)) 2>/dev/null; true)"
                : "/bin/launchctl disable \(Shell.quote(service)) && (/bin/launchctl bootout \(Shell.quote(service)) 2>/dev/null; true)"
            return Shell.runAsAdmin(cmd)
        }
        let ok = Shell.run("/bin/launchctl", [on ? "enable" : "disable", service]).status == 0
        if on {
            Shell.run("/bin/launchctl", ["bootstrap", item.kind.domain, plist])
        } else {
            Shell.run("/bin/launchctl", ["bootout", service])
        }
        return ok
    }

    /// Kirish elementini ro'yxatdan oladi yoki shaxsiy agentni to'xtatib, faylini Savatga tashlaydi.
    static func remove(_ item: StartupItem) -> Bool {
        switch item.kind {
        case .loginItem:
            return Shell.run("/usr/bin/osascript", [
                "-e", "on run argv",
                "-e", "tell application \"System Events\" to delete login item (item 1 of argv)",
                "-e", "end run", item.label,
            ]).status == 0
        case .userAgent:
            Shell.run("/bin/launchctl", ["bootout", "\(item.kind.domain)/\(item.label)"])
            guard let plist = item.plist else { return false }
            return (try? FileManager.default.trashItem(at: plist, resultingItemURL: nil)) != nil
        case .globalAgent, .daemon:
            return false
        }
    }
}

// MARK: - Holat

@MainActor
final class StartupStore: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var loginError: String?
    @Published var loading = false
    @Published var loaded = false
    @Published var waitingLogin = false
    @Published var busy: Set<String> = []
    @Published var removing: StartupItem?
    @Published var failure: String?

    var enabledCount: Int { items.filter(\.enabled).count }

    func load() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            // Avval fon xizmatlari chiqadi; kirish elementlari macOS ruxsatini kutishi mumkin.
            let services = StartupScanner.scanServices()
            await MainActor.run {
                self.items = services + self.items.filter { $0.kind == .loginItem }
                self.loaded = true
                self.waitingLogin = true
            }
            let login = StartupScanner.loginItems()
            await MainActor.run {
                self.items = StartupScanner.sorted(services + login.items)
                self.loginError = login.error
                self.waitingLogin = false
                self.loading = false
            }
        }
    }

    func setEnabled(_ item: StartupItem, _ on: Bool) {
        busy.insert(item.id)
        Task.detached(priority: .userInitiated) {
            let ok = StartupActions.setEnabled(item, on)
            await MainActor.run {
                self.busy.remove(item.id)
                if ok, let i = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[i].enabled = on
                } else if !ok {
                    self.failure = L("«\(item.name)» holatini o'zgartirib bo'lmadi.",
                                     "Couldn't change «\(item.name)».",
                                     "Не удалось изменить «\(item.name)».")
                }
            }
        }
    }

    func remove(_ item: StartupItem) {
        busy.insert(item.id)
        Task.detached(priority: .userInitiated) {
            let ok = StartupActions.remove(item)
            await MainActor.run {
                self.busy.remove(item.id)
                if ok {
                    self.items.removeAll { $0.id == item.id }
                } else {
                    self.failure = L("«\(item.name)»ni olib tashlab bo'lmadi.",
                                     "Couldn't remove «\(item.name)».",
                                     "Не удалось удалить «\(item.name)».")
                }
            }
        }
    }
}

// MARK: - Bo'lim

struct StartupView: View {
    @ObservedObject var store: StartupStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: StartupView.symbol, color: StartupView.color, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(StartupView.title).font(.title3.weight(.semibold))
                        Text(L("Mac yoqilganda yoki tizimga kirganingizda o'zi ishga tushadigan dasturlar. Keraksizini o'chirsangiz, Mac tezroq yoqiladi va kamroq xotira band bo'ladi.",
                               "Programs that start by themselves when the Mac boots or you log in. Turning off the ones you don't need makes startup faster and frees memory.",
                               "Программы, которые запускаются сами при включении Mac или входе. Отключите ненужные — Mac будет загружаться быстрее и занимать меньше памяти."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            if store.loading && !store.loaded {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
            } else {
                ForEach(StartupKind.allCases) { kind in
                    section(kind)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(StartupView.title)
        .task { if !store.loaded { store.load() } }
        .alert(L("«\(store.removing?.name ?? "")» olib tashlansinmi?", "Remove «\(store.removing?.name ?? "")»?", "Удалить «\(store.removing?.name ?? "")»?"), isPresented: Binding(
            get: { store.removing != nil }, set: { if !$0 { store.removing = nil } }
        ), presenting: store.removing) { item in
            Button(L("Olib tashlash", "Remove", "Удалить"), role: .destructive) { store.remove(item) }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: { item in
            Text(item.kind == .loginItem
                 ? L("«\(item.name)» endi tizimga kirganda o'zi ochilmaydi. Ilovaning o'zi qoladi.",
                     "«\(item.name)» will no longer open at login. The app itself stays.",
                     "«\(item.name)» больше не будет открываться при входе. Само приложение останется.")
                 : L("«\(item.name)» to'xtatiladi va uning fayli Savatga ko'chiriladi.",
                     "«\(item.name)» will be stopped and its file moved to the Trash.",
                     "«\(item.name)» будет остановлен, а его файл перемещён в Корзину."))
        }
        .alert(L("Bajarilmadi", "Didn't work", "Не получилось"), isPresented: Binding(
            get: { store.failure != nil }, set: { if !$0 { store.failure = nil } }
        )) {
            Button(L("Yopish", "Close", "Закрыть"), role: .cancel) {}
        } message: {
            Text(store.failure ?? "")
        }
    }

    @ViewBuilder
    private func section(_ kind: StartupKind) -> some View {
        let list = store.items.filter { $0.kind == kind }
        if !list.isEmpty || (kind == .loginItem && (store.loginError != nil || store.waitingLogin)) {
            Section {
                if kind == .loginItem && store.waitingLogin && list.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L("Yuklanmoqda… macOS ruxsat so'rasa, «OK»ni bosing.",
                               "Loading… If macOS asks for permission, click «OK».",
                               "Загрузка… Если macOS запросит разрешение, нажмите «OK»."))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                if kind == .loginItem, let error = store.loginError {
                    HStack(spacing: 12) {
                        IconTile(symbol: "lock.fill", color: .orange)
                        Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("Sozlamalar", "Settings", "Настройки")) {
                            let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                            if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
                        }
                        Button(L("Qayta urinish", "Try again", "Повторить")) { store.load() }
                    }
                    .padding(.vertical, 3)
                }
                ForEach(list) { item in
                    StartupRow(item: item, busy: store.busy.contains(item.id),
                               toggle: { store.setEnabled(item, $0) },
                               remove: { store.removing = item })
                }
            } header: {
                Text("\(kind.title) · \(list.count)")
            } footer: {
                Text(kind.footer)
            }
        }
    }

    static var title: String { L("Ishga tushish", "Startup items", "Автозагрузка") }
    static let symbol = "power"
    static let color = Color.green
}

struct StartupRow: View {
    let item: StartupItem
    let busy: Bool
    let toggle: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1)
                    if item.missing {
                        Badge(text: L("Ilovasi yo'q", "App is gone", "Приложения нет"), color: .yellow)
                            .help(L("Bu ilova o'chirilgan, uning ishga tushish yozuvi qolib ketgan — olib tashlash mumkin.",
                                    "The app was removed but its startup entry was left behind — it's safe to remove.",
                                    "Приложение удалено, а запись автозагрузки осталась — её можно удалить."))
                    } else if item.running {
                        Badge(text: L("Ishlayapti", "Running", "Работает"), color: .green)
                    }
                }
                Text(item.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)

            if busy {
                ProgressView().controlSize(.small)
            }
            if let url = item.plist ?? item.target {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 17)).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder"))
            }
            if item.kind == .loginItem || item.kind == .userAgent {
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 17)).foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(L("Olib tashlash", "Remove", "Удалить"))
                .disabled(busy)
            }
            if item.kind != .loginItem {
                Toggle("", isOn: Binding(get: { item.enabled }, set: toggle))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(busy)
                    .help(item.enabled ? L("Yoqilgan", "On", "Включено") : L("O'chirilgan", "Off", "Отключено"))
            }
        }
        .padding(.vertical, 2)
        .opacity(item.enabled ? 1 : 0.6)
    }

    @ViewBuilder
    private var icon: some View {
        if let target = item.target, FileManager.default.fileExists(atPath: target.path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: target.path)).resizable()
        } else {
            IconTile(symbol: item.kind == .loginItem ? "app.dashed" : "gearshape.2.fill", color: .gray)
        }
    }
}

/// Umumiy ko'rinishdagi «Ishga tushish» qatori.
struct StartupEntryRow: View {
    @ObservedObject var store: StartupStore
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: StartupView.symbol, color: StartupView.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(StartupView.title)
                Text(L("Mac bilan birga o'zi ishga tushadigan dasturlar",
                       "Programs that start along with your Mac",
                       "Программы, которые запускаются вместе с Mac"))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if store.loaded {
                Text(L("\(store.enabledCount) ta yoqilgan", "\(store.enabledCount) on", "Включено: \(store.enabledCount)"))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
