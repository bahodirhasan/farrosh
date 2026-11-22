import SwiftUI
import UniformTypeIdentifiers

@main
struct FarroshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // Til almashganda oyna qayta chiziladi, lekin skaner natijalari saqlanib qoladi.
    @StateObject private var store = Store()
    @StateObject private var apps = AppsStore()
    @StateObject private var ui = WindowState()
    @StateObject private var largeFiles = LargeFilesStore()
    @StateObject private var startup = StartupStore()
    @StateObject private var duplicates = DuplicatesStore()
    @AppStorage(AppLanguage.key) private var language = AppLanguage.uz.rawValue
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @AppStorage(Prefs.menuBar) private var showMenuBar = true
    @StateObject private var background = Background.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store, apps: apps, ui: ui, largeFiles: largeFiles, startup: startup, duplicates: duplicates)
                .id(language)
                .environment(\.locale, AppLanguage.current.locale)
                .frame(minWidth: 780, minHeight: 520)
                .onChange(of: language) { value in
                    AppLanguage.syncSystemMenus(value)
                    store.scan()
                }
                .onChange(of: appearance) { value in
                    Appearance.apply(Appearance(rawValue: value) ?? .system)
                }
        }
        .defaultSize(width: 1220, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // ⌘, alohida oyna emas, chap paneldagi «Sozlamalar» bo'limini ochadi.
            CommandGroup(replacing: .appSettings) {
                Button(L("Sozlamalar…", "Settings…", "Настройки…")) { ui.selection = .settings }
                    .keyboardShortcut(",")
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel(bg: background)
                .id(language)
                .environment(\.locale, AppLanguage.current.locale)
        } label: {
            MenuBarLabel(bg: background)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply()
        Task { @MainActor in Background.shared.start() }
    }

    /// Menyu satrida belgi bo'lsa, oyna yopilganda ilova fonda ishlashda davom etadi.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Prefs.menuBarOn }

    /// Dock belgisi bosilganda oyna yopiq bo'lsa, qayta ochamiz.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in Background.shared.showMain() } }
        return true
    }
}

// MARK: - Asosiy oyna: chapda bo'limlar, o'ngda tanlangan bo'lim

enum SidebarItem: Hashable {
    case overview
    case apps
    case category(Category)
    case largeFiles
    case startup
    case duplicates
    case settings
}

/// Oyna holati. Command Line Tools'da `@State` makrosi yo'q, shuning uchun ObservableObject ishlatiladi.
final class WindowState: ObservableObject {
    @Published var selection: SidebarItem? = .overview
    @Published var confirming = false
    /// Tasdiqlash oynasi qaysi bo'limlarni tozalashi.
    @Published var cleanScope = Category.allCases
}

struct ContentView: View {
    @ObservedObject var store: Store
    @ObservedObject var apps: AppsStore
    @ObservedObject var ui: WindowState
    @ObservedObject var largeFiles: LargeFilesStore
    @ObservedObject var startup: StartupStore
    @ObservedObject var duplicates: DuplicatesStore
    @ObservedObject private var background = Background.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, apps: apps, largeFiles: largeFiles, startup: startup, duplicates: duplicates, selection: $ui.selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 285, max: 360)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        Button(action: pickApp) {
                            Label(L("Ilovani tanlab o'chirish", "Uninstall an app", "Удалить приложение"), systemImage: "trash")
                        }
                        .help(L("Ilovani tanlab o'chirish (⌘O) — yoki ilovani shu oynaga sudrab tashlang", "Choose an app to uninstall (⌘O) — or drag an app onto this window", "Выбрать приложение для удаления (⌘O) — или перетащите его в это окно"))
                        .keyboardShortcut("o")
                    }
                    ToolbarItem {
                        Button {
                            store.scan()
                            apps.reload()
                            if largeFiles.scanned { largeFiles.scan() }
                            if duplicates.scanned { duplicates.scan() }
                            if startup.loaded { startup.load() }
                        } label: {
                            Label(L("Qayta skanerlash", "Rescan", "Пересканировать"), systemImage: "arrow.clockwise")
                        }
                        .help(L("Qayta skanerlash (⌘R)", "Rescan (⌘R)", "Пересканировать (⌘R)"))
                        .keyboardShortcut("r")
                        .disabled(store.isBusy)
                    }
                }
        }
        .alert(confirmTitle, isPresented: $ui.confirming) {
            Button(L("Tozalash", "Clean", "Очистить"), role: .destructive) { store.clean(ui.cleanScope) }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .overlay {
            if store.cleaning {
                CleaningOverlay(subtitle: store.selectedSize(of: ui.cleanScope).bytes)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.cleaning)
        .sheet(item: $store.result) { ResultView(result: $0) }
        .sheet(item: $background.trashedApp) { trashed in
            TrashedAppSheet(trashed: trashed) {
                background.trashedApp = nil
                store.scan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .farroshDidClean)) { _ in
            if !store.isBusy { store.scan() }
        }
        .task {
            // Til almashganda qayta skanerlash shart emas.
            if store.items.isEmpty && store.scanning.isEmpty { store.scan() }
            if apps.apps.isEmpty { apps.load() }
            // Yangi ilova yoki fayl paydo bo'lsa, ro'yxatlar qayta ochishsiz yangilanadi.
            store.startWatching()
            apps.startWatching()
            largeFiles.startWatching()
            duplicates.startWatching()
            background.openMain = { openWindow(id: "main") }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                DispatchQueue.main.async { openApp(url) }
            }
            return true
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch ui.selection ?? .overview {
        case .overview:
            OverviewView(store: store, apps: apps, largeFiles: largeFiles, startup: startup) { ui.selection = $0 }
                .safeAreaInset(edge: .bottom) { cleanBar(Category.allCases) }
        case .apps:
            AppsPane(apps: apps) { _ in store.scan() }
        case .category(let category):
            DetailView(category: category, store: store)
                .safeAreaInset(edge: .bottom) { cleanBar([category]) }
        case .largeFiles:
            LargeFilesView(store: largeFiles)
        case .duplicates:
            DuplicatesView(store: duplicates)
        case .startup:
            StartupView(store: startup)
        case .settings:
            SettingsView()
        }
    }

    /// ⌘O: o'chirish uchun ilovani Finder oynasidan tanlash.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Tanlash", "Choose", "Выбрать")
        panel.message = L("O'chirmoqchi yoki tozalamoqchi bo'lgan ilovani tanlang", "Choose the app you want to uninstall or clean", "Выберите приложение, которое хотите удалить или очистить")
        if panel.runModal() == .OK, let url = panel.url { openApp(url) }
    }

    /// Tanlangan yoki sudrab tashlangan ilovani «Ilovalar» bo'limida ochadi.
    private func openApp(_ url: URL) {
        Task.detached(priority: .userInitiated) {
            guard var info = AppScanner.appInfo(for: url) else { return }
            info.size = Scanner.size(of: url)
            info.lastUsed = AppScanner.lastUsed(url)
            let app = info
            await MainActor.run {
                apps.show(app)
                ui.selection = .apps
            }
        }
    }

    private func cleanBar(_ scope: [Category]) -> some View {
        let size = store.selectedSize(of: scope)
        return VStack(spacing: 0) {
            Divider()
            Button {
                ui.cleanScope = scope
                ui.confirming = true
            } label: {
                HStack(spacing: 8) {
                    if store.cleaning { ProgressView().controlSize(.small).tint(.white) }
                    Text(buttonTitle(size, scope))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isBusy || size == 0)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: FormMetrics.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }

    private func buttonTitle(_ size: Int64, _ scope: [Category]) -> String {
        if store.cleaning { return L("Tozalanmoqda…", "Cleaning…", "Очистка…") }
        if scope.contains(where: store.scanning.contains) { return L("Skanerlanmoqda…", "Scanning…", "Сканирование…") }
        if size == 0 { return L("Tozalash", "Clean", "Очистить") }
        if scope == [.trash] { return L("Savatni bo'shatish · \(size.bytes)", "Empty Trash · \(size.bytes)", "Очистить Корзину · \(size.bytes)") }
        return L("Tozalash · \(size.bytes)", "Clean · \(size.bytes)", "Очистить · \(size.bytes)")
    }

    /// «Ishonchingiz komilmi?» o'rniga — aniq nima va qancha.
    private var confirmTitle: String {
        let total = store.selectedSize(of: ui.cleanScope).bytes
        return ui.cleanScope == [.trash]
            ? L("Savat bo'shatilsinmi? \(total)", "Empty the Trash? \(total)", "Очистить Корзину? \(total)")
            : L("\(total) tozalansinmi?", "Clean \(total)?", "Очистить \(total)?")
    }

    private var confirmMessage: String {
        let scope = ui.cleanScope
        let total = store.selectedSize(of: scope).bytes
        var lines = [L("Jami \(total) tozalanadi.", "\(total) will be cleaned in total.", "Всего будет очищено \(total).")]
        let kept = store.selectedSize(of: scope.filter { $0 == .leftovers || $0 == .installers })
        if kept > 0 {
            lines.append(Remover.permanent
                ? L("O'rnatish fayllari va qoldiqlar (\(kept.bytes)) butunlay o'chadi.", "Installers and leftovers (\(kept.bytes)) will be deleted permanently.", "Установщики и остатки (\(kept.bytes)) будут удалены навсегда.")
                : L("O'rnatish fayllari va qoldiqlar (\(kept.bytes)) Savatga ko'chiriladi.", "Installers and leftovers (\(kept.bytes)) will be moved to the Trash.", "Установщики и остатки (\(kept.bytes)) будут перемещены в Корзину."))
        }
        if scope.contains(.trash), store.selectedSize(.trash) > 0 {
            let trash = store.selectedSize(.trash).bytes
            lines.append(L("Savatdagi \(trash) butunlay o'chadi va qaytarib bo'lmaydi.", "\(trash) in the Trash will be deleted for good and can't be recovered.", "\(trash) в Корзине будут удалены навсегда без возможности восстановления."))
        }
        lines.append(L("Ochiq ilovalarni yopib qo'ysangiz, ko'proq joy bo'shaydi.", "Quit open apps to free up more space.", "Закройте открытые приложения, чтобы освободить больше места."))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Chap panel

struct Sidebar: View {
    @ObservedObject var store: Store
    @ObservedObject var apps: AppsStore
    @ObservedObject var largeFiles: LargeFilesStore
    @ObservedObject var startup: StartupStore
    @ObservedObject var duplicates: DuplicatesStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            SidebarRow(
                title: L("Umumiy ko'rinish", "Overview", "Обзор"), symbol: "internaldrive.fill", color: .blue,
                trailing: store.totalSelected > 0 ? store.totalSelected.bytes : nil
            )
            .tag(SidebarItem.overview)

            Section(L("Ilovalar", "Applications", "Приложения")) {
                SidebarRow(
                    title: L("Ilovalar", "Applications", "Приложения"), symbol: "square.grid.2x2.fill", color: .teal,
                    trailing: apps.apps.isEmpty ? nil : "\(apps.apps.count)"
                )
                .tag(SidebarItem.apps)
                SidebarRow(
                    title: StartupView.title, symbol: StartupView.symbol, color: StartupView.color,
                    trailing: startup.loaded ? "\(startup.enabledCount)" : nil
                )
                .tag(SidebarItem.startup)
                row(.leftovers)
                row(.installers)
            }

            Section(L("Fayllar", "Files", "Файлы")) {
                SidebarRow(
                    title: LargeFilesView.title, symbol: LargeFilesView.symbol, color: LargeFilesView.color,
                    trailing: largeFiles.scanning ? "…" : (largeFiles.scanned && largeFiles.visibleSize > 0 ? largeFiles.visibleSize.bytes : nil)
                )
                .tag(SidebarItem.largeFiles)
                SidebarRow(
                    title: DuplicatesView.title, symbol: DuplicatesView.symbol, color: DuplicatesView.color,
                    trailing: duplicates.scanning ? "…" : (duplicates.scanned && duplicates.wasted > 0 ? duplicates.wasted.bytes : nil)
                )
                .tag(SidebarItem.duplicates)
            }

            Section(L("Keraksiz fayllar", "Junk files", "Ненужные файлы")) {
                ForEach([Category.appCaches, .logs, .devCaches, .trash]) { row($0) }
            }

            Section("Farrosh") {
                SidebarRow(title: L("Sozlamalar", "Settings", "Настройки"), symbol: "gearshape.fill", color: .gray)
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { DiskFooter(disk: store.disk) }
    }

    private func row(_ category: Category) -> some View {
        let trailing: String?
        if store.scanning.contains(category) {
            trailing = "…"
        } else {
            let found = store.foundSize(category)
            trailing = found > 0 ? found.bytes : nil
        }
        return SidebarRow(title: category.shortTitle, symbol: category.symbol, color: category.color, trailing: trailing)
            .tag(SidebarItem.category(category))
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    var trailing: String?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, color: color, size: 24)
            Text(title).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).foregroundStyle(.secondary).monospacedDigit().fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

/// Chap panel pastidagi disk holati.
struct DiskFooter: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                Text(disk.name).fontWeight(.medium).lineLimit(1)
            }
            ProgressView(value: Double(disk.used), total: Double(max(disk.total, 1)))
                .tint(disk.free < disk.total / 10 ? .red : .accentColor)
            Text(L("\(disk.free.bytes) bo'sh · jami \(disk.total.bytes)", "\(disk.free.bytes) free of \(disk.total.bytes)", "Свободно \(disk.free.bytes) из \(disk.total.bytes)"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(14)
        // Tor oynada ro'yxat ostidan o'tib ketsa, matnlar ustma-ust tushmasin.
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Umumiy ko'rinish

struct OverviewView: View {
    @ObservedObject var store: Store
    @ObservedObject var apps: AppsStore
    @ObservedObject var largeFiles: LargeFilesStore
    @ObservedObject var startup: StartupStore
    let select: (SidebarItem) -> Void

    var body: some View {
        Form {
            Section { StorageHeader(store: store, apps: apps) }

            Section {
                AppsEntryRow(apps: apps) { select(.apps) }
                StartupEntryRow(store: startup) { select(.startup) }
                LargeFilesEntryRow(store: largeFiles) { select(.largeFiles) }
            } header: {
                Text(L("Ilovalar va fayllar", "Apps and files", "Приложения и файлы"))
            }

            Section {
                ForEach(Category.allCases) { category in
                    CategoryRow(category: category, store: store) { select(.category(category)) }
                }
            } header: {
                Text(L("Tozalanadigan fayllar", "Files to clean", "Файлы для очистки"))
            } footer: {
                Text(Remover.permanent
                     ? L("Kesh va loglar butunlay o'chiriladi — ilovalar ularni kerak bo'lganda qayta yaratadi. O'rnatish fayllari va qoldiqlar ham butunlay o'chiriladi («Sozlamalar» bo'limida o'zgartirish mumkin).", "Caches and logs are deleted for good — apps recreate them when needed. Installers and leftovers are deleted for good too (change this in Settings, ⌘,).", "Кэш и журналы удаляются навсегда — приложения создадут их заново. Установщики и остатки тоже удаляются навсегда (можно изменить в Настройках, ⌘,).")
                     : L("Kesh va loglar butunlay o'chiriladi — ilovalar ularni kerak bo'lganda qayta yaratadi. O'rnatish fayllari va qoldiqlar Savatga ko'chiriladi («Sozlamalar» bo'limida o'zgartirish mumkin).", "Caches and logs are deleted for good — apps recreate them when needed. Installers and leftovers go to the Trash (change this in Settings, ⌘,).", "Кэш и журналы удаляются навсегда — приложения создадут их заново. Установщики и остатки перемещаются в Корзину (можно изменить в Настройках, ⌘,)."))
            }

            if store.trashLocked {
                Section { TrashAccessRow() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Umumiy ko'rinish", "Overview", "Обзор"))
    }
}

// MARK: - Bo'lim qatori (iOS «Sozlamalar» uslubidagi rangli ikonka bilan)

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct CategoryRow: View {
    let category: Category
    @ObservedObject var store: Store
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: category.symbol, color: category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if store.scanning.contains(category) {
                    ProgressView().controlSize(.small)
                } else if store.selectedSize(category) > 0 {
                    Text(store.selectedSize(category).bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            Toggle("", isOn: Binding(
                get: { store.isOn(category) },
                set: { store.setAll(category, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(store.isBusy || (store.items[category] ?? []).isEmpty)

            Button(action: open) {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        let list = store.items[category] ?? []
        if store.scanning.contains(category) { return L("Skanerlanmoqda…", "Scanning…", "Сканирование…") }
        if category == .trash && store.trashLocked { return L("Ruxsat kerak", "Access needed", "Нужен доступ") }
        if list.isEmpty { return L("Toza", "Clean", "Чисто") }
        let picked = list.filter(\.selected).count
        let total = store.foundSize(category).bytes
        return L("\(list.count) ta topildi · \(picked) ta tanlangan · jami \(total)", "\(list.count) found · \(picked) selected · \(total) total", "Найдено: \(list.count) · выбрано: \(picked) · всего \(total)")
    }
}

struct TrashAccessRow: View {
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "lock.fill", color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Savatni ko'rish uchun ruxsat kerak", "Access is needed to see the Trash", "Для просмотра Корзины нужен доступ"))
                Text(L("Tizim sozlamalari → Maxfiylik → To'liq disk ruxsati → Farrosh'ni yoqing", "System Settings → Privacy & Security → Full Disk Access → turn on Farrosh", "Системные настройки → Конфиденциальность → Полный доступ к диску → включите Farrosh"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Ochish", "Open", "Открыть")) {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Bo'lim ichidagi ro'yxat

struct DetailView: View {
    let category: Category
    @ObservedObject var store: Store

    private var list: [CleanItem] { store.items[category] ?? [] }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: category.symbol, color: category.color, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title).font(.title3.weight(.semibold))
                        Text(category.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if store.scanning.contains(category) {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.green)
                        Text(category == .trash && store.trashLocked
                             ? L("Savatni o'qishga ruxsat yo'q", "No access to read the Trash", "Нет доступа к Корзине")
                             : L("Bu yer toza", "All clean here", "Здесь чисто"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(list) { item in
                        ItemRow(item: item) { store.toggle(item, in: category) }
                            .disabled(store.isBusy)
                    }
                }
            } header: {
                if !list.isEmpty {
                    Text(L("\(list.count) ta element · tanlangan \(store.selectedSize(category).bytes)", "\(list.count) items · \(store.selectedSize(category).bytes) selected", "Элементов: \(list.count) · выбрано \(store.selectedSize(category).bytes)"))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItem {
                let all = !list.isEmpty && list.allSatisfy(\.selected)
                Button(all ? L("Hech birini tanlamaslik", "Deselect all", "Снять выбор") : L("Hammasini tanlash", "Select all", "Выбрать все")) {
                    store.setAll(category, !all)
                }
                .disabled(list.isEmpty || store.isBusy)
            }
        }
    }
}

struct ItemRow: View {
    let item: CleanItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(item.selected ? Color.accentColor : Color.secondary)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.urls[0].path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.needsReview {
                // Rang yolg'iz ma'no tashimaydi: belgi + so'z, matn esa asosiy rangda o'qiladi.
                Label(L("Tekshiring", "Review", "Проверьте"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary, .yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.18), in: Capsule())
            }
            Text(item.size.bytes).monospacedDigit().foregroundStyle(.secondary)
            // Fayl turgan joyni Finder'da ochadi.
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(item.urls)
            } label: {
                // Belgi kichik, lekin bosish maydoni to'liq 28×28.
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder"))
            .help(L("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder"))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button(L("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting(item.urls) }
        }
    }
}

// MARK: - Natija

struct ResultView: View {
    let result: CleanResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            SuccessBadge()
                .padding(.top, 8)
            CountingBytes(bytes: result.freed) { size in
                L("\(size) bo'shatildi", "\(size) freed", "Освобождено \(size)")
            }
            .font(.title.weight(.bold))
            if result.movedToTrash > 0 {
                Text(L("\(result.movedToTrash.bytes) Savatga ko'chirildi. Savatni bo'shatsangiz, bu joy ham bo'shaydi.", "\(result.movedToTrash.bytes) moved to the Trash. Empty the Trash to free this space too.", "\(result.movedToTrash.bytes) перемещено в Корзину. Очистите Корзину, чтобы освободить и это место."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if result.failed > 0 {
                Text(L("\(result.failed) ta element to'liq o'chmadi — ular hozir ishlatilmoqda yoki himoyalangan.", "\(result.failed) items weren't fully removed — they are in use or protected.", "Не удалось полностью удалить элементов: \(result.failed) — они используются или защищены."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(L("Tayyor", "Done", "Готово")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 380)
    }
}

/// Guruhlangan Form kartalarining eng katta kengligi — pastki tugmalar ham shunga teng bo'ladi.
enum FormMetrics {
    static let contentWidth: CGFloat = 704
}

// MARK: - iOS uslubidagi asosiy tugma

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    /// false — kulrang fonli ikkinchi darajali tugma.
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color.white : (isEnabled ? tint : Color.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(
                    prominent
                        ? (isEnabled ? tint : Color.secondary.opacity(0.5))
                        : Color.secondary.opacity(0.18)
                )
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Sozlamalar (⌘,)

struct SettingsView: View {
    @AppStorage(Remover.permanentKey) private var permanent = false
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @AppStorage(AppLanguage.key) private var language = AppLanguage.uz.rawValue
    @AppStorage(Prefs.menuBar) private var showMenuBar = true
    @AppStorage(Prefs.lowSpaceGB) private var lowSpaceGB = 10
    @AppStorage(Prefs.reminder) private var reminder = Reminder.weekly.rawValue
    @AppStorage(Prefs.watchTrash) private var watchTrash = true
    @ObservedObject private var bg = Background.shared

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { LaunchAtLogin.isOn }, set: { on in
            _ = LaunchAtLogin.set(on)
            bg.objectWillChange.send()
        })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ForEach(Appearance.allCases) { item in
                        AppearanceTile(item: item, selected: appearance == item.rawValue) {
                            appearance = item.rawValue
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } header: {
                Text(L("Ko'rinish", "Appearance", "Оформление"))
            }

            Section {
                Picker(L("Ilova tili", "App language", "Язык приложения"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.name).tag($0.rawValue) }
                }
            } header: {
                Text(L("Til", "Language", "Язык"))
            } footer: {
                Text(L("Menyu satridagi tizim buyruqlari keyingi ochilishda o'zgaradi.",
                       "System menu commands switch on the next launch.",
                       "Системные команды в строке меню сменятся при следующем запуске."))
            }

            Section {
                Picker(L("O'chirilgan fayllar", "Removed files", "Удалённые файлы"), selection: $permanent) {
                    Text(L("Savatga ko'chirilsin", "Move to the Trash", "Перемещать в Корзину")).tag(false)
                    Text(L("Butunlay o'chirilsin", "Delete permanently", "Удалять навсегда")).tag(true)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(L("O'chirish", "Removal", "Удаление"))
            } footer: {
                Text(permanent
                     ? L("Ilovalar, qoldiqlar va o'rnatish fayllari darhol o'chadi — joy shu zahoti bo'shaydi, lekin ularni qaytarib bo'lmaydi.",
                         "Apps, leftovers and installers are deleted right away — space is freed at once, but they can't be recovered.",
                         "Приложения, остатки и установщики удаляются сразу — место освобождается мгновенно, но вернуть их нельзя.")
                     : L("Ilovalar, qoldiqlar va o'rnatish fayllari Savatga tushadi — xato o'chirilganini qaytarib olish mumkin. Joy Savat bo'shatilgach bo'shaydi.",
                         "Apps, leftovers and installers go to the Trash — anything removed by mistake can be restored. Space is freed once the Trash is emptied.",
                         "Приложения, остатки и установщики попадают в Корзину — удалённое по ошибке можно вернуть. Место освободится после очистки Корзины."))
            }

            Section {
                Toggle(L("Menyu satrida bo'sh joyni ko'rsatish", "Show free space in the menu bar", "Показывать свободное место в строке меню"), isOn: $showMenuBar)
                Picker(L("Joy kam qolganda ogohlantirish", "Warn when free space is below", "Предупреждать, когда свободно меньше"), selection: $lowSpaceGB) {
                    Text(L("O'chiq", "Off", "Выключено")).tag(0)
                    ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) }
                }
                Picker(L("Tozalash eslatmasi", "Cleanup reminder", "Напоминание об очистке"), selection: $reminder) {
                    ForEach(Reminder.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(L("Savatga tashlangan ilovalar qoldig'ini topish", "Find leftovers of apps moved to the Trash", "Искать остатки приложений, перемещённых в Корзину"), isOn: $watchTrash)
                    .onChange(of: watchTrash) { _ in bg.updateTrashWatcher() }
                Toggle(L("Mac yoqilganda Farrosh'ni ishga tushirish", "Open Farrosh at login", "Запускать Farrosh при входе"), isOn: launchAtLogin)
            } header: {
                Text(L("Fonda ishlash", "In the background", "В фоне"))
            } footer: {
                Text(watchTrash && !bg.trashWatching
                     ? L("Savatni kuzatish uchun Farrosh'ga «To'liq disk ruxsati» kerak: Tizim sozlamalari → Maxfiylik va xavfsizlik → To'liq disk ruxsati. Ruxsat berib, Farrosh'ni qayta oching.",
                         "Watching the Trash needs Full Disk Access: System Settings → Privacy & Security → Full Disk Access. Grant it, then reopen Farrosh.",
                         "Для слежения за Корзиной нужен полный доступ к диску: Системные настройки → Конфиденциальность и безопасность → Полный доступ к диску. Выдайте его и перезапустите Farrosh.")
                     : L("Menyu satri belgisi yoqilgan bo'lsa, oynani yopganda Farrosh fonda ishlashda davom etadi. Eslatma faqat 500 MB dan ko'p tozalanadigan narsa yig'ilsa keladi.",
                         "With the menu bar icon on, Farrosh keeps running after you close the window. Reminders only arrive when more than 500 MB can be cleaned.",
                         "Если значок в строке меню включён, Farrosh продолжает работать после закрытия окна. Напоминание приходит, только если можно очистить больше 500 МБ."))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Sozlamalar", "Settings", "Настройки"))
    }
}

/// macOS «Tizim sozlamalari»dagi kabi ko'rinish tanlash kartasi.
struct AppearanceTile: View {
    let item: Appearance
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 112, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: selected ? 3 : 1)
                    )
                Label(item.title, systemImage: item.symbol)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch item {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniWindow(dark: false)
                MiniWindow(dark: true)
            }
        }
    }
}

/// Ko'rinish kartasidagi kichik oyna rasmi.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let bg = dark ? Color(white: 0.16) : Color(white: 0.96)
        let panel = dark ? Color(white: 0.24) : Color(white: 0.86)
        let line = dark ? Color(white: 0.38) : Color(white: 0.75)
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(panel).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 30, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(height: 5)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 34, height: 5)
                Spacer(minLength: 0)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }
}
