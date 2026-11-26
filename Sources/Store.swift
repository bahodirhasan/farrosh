import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var items: [Category: [CleanItem]] = [:]
    @Published var scanning: Set<Category> = []
    @Published var cleaning = false
    @Published var result: CleanResult?
    @Published var disk = DiskInfo.current()
    @Published var trashLocked = false
    /// Hujjatlar, media va macOS hajmi — bir marta, fonda hisoblanadi.
    @Published var folders: FolderUsage?
    private var measuring = false
    private var measuredAt: Date?

    func measureFolders() async {
        // Papkalarni aylanib chiqish og'ir: daqiqasiga bir martadan ko'p emas.
        if measuring { return }
        if let at = measuredAt, Date().timeIntervalSince(at) < 60 { return }
        measuring = true
        let usage = await Task.detached(priority: .utility) { FolderUsage.measure() }.value
        folders = usage
        measuredAt = Date()
        measuring = false
    }

    var isBusy: Bool { cleaning || !scanning.isEmpty }

    func scan() {
        disk = .current()
        trashLocked = !Scanner.trashAccessible()
        for category in Category.allCases {
            scanning.insert(category)
            Task.detached(priority: .userInitiated) {
                let found = Scanner.scan(category)
                await MainActor.run {
                    self.items[category] = found
                    self.scanning.remove(category)
                    if self.scanning.isEmpty {
                        let total = self.totalSelected
                        announce(total > 0
                            ? L("Skanerlash tugadi. Tozalash mumkin: \(total.bytes).", "Scan finished. Ready to clean: \(total.bytes).", "Сканирование завершено. Можно очистить: \(total.bytes).")
                            : L("Skanerlash tugadi. Mac toza.", "Scan finished. Your Mac is clean.", "Сканирование завершено. Mac чист."))
                    }
                }
            }
        }
    }

    private var watchers: [FolderWatcher] = []

    /// Yangi .dmg/.pkg yuklansa, Savatga fayl tushsa yoki ilova o'chirilsa — tegishli toifa o'zi yangilanadi.
    func startWatching() {
        guard watchers.isEmpty else { return }
        let home = Scanner.home
        let spots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0).path }
        if let w = FolderWatcher(paths: spots, latency: 3, onChange: { [weak self] _ in self?.rescan([.installers]) }) { watchers.append(w) }
        if let w = FolderWatcher(paths: [home.appendingPathComponent(".Trash").path], latency: 3, onChange: { [weak self] _ in self?.rescan([.trash]) }) { watchers.append(w) }
        let apps = ["/Applications", home.appendingPathComponent("Applications").path]
        if let w = FolderWatcher(paths: apps, latency: 5, onChange: { [weak self] _ in self?.rescan([.leftovers]) }) { watchers.append(w) }
    }

    /// Toifani qayta skanerlaydi, foydalanuvchi qo'lda qilgan tanlovni saqlab.
    func rescan(_ categories: [Category]) {
        guard !cleaning else { return }
        disk = .current()
        for category in categories where !scanning.contains(category) && items[category] != nil {
            let before = Dictionary((items[category] ?? []).map { ($0.id, $0.selected) }, uniquingKeysWith: { a, _ in a })
            scanning.insert(category)
            Task.detached(priority: .utility) {
                var found = Scanner.scan(category)
                for i in found.indices { if let was = before[found[i].id] { found[i].selected = was } }
                let result = found
                await MainActor.run {
                    self.items[category] = result
                    self.scanning.remove(category)
                }
            }
        }
    }

    func selectedSize(_ category: Category) -> Int64 {
        (items[category] ?? []).filter(\.selected).reduce(0) { $0 + $1.size }
    }

    func foundSize(_ category: Category) -> Int64 {
        (items[category] ?? []).reduce(0) { $0 + $1.size }
    }

    func selectedSize(of scope: [Category]) -> Int64 { scope.reduce(0) { $0 + selectedSize($1) } }

    var totalSelected: Int64 { selectedSize(of: Category.allCases) }

    func isOn(_ category: Category) -> Bool {
        (items[category] ?? []).contains(where: \.selected)
    }

    func setAll(_ category: Category, _ on: Bool) {
        guard var list = items[category] else { return }
        for i in list.indices { list[i].selected = on }
        items[category] = list
    }

    func toggle(_ item: CleanItem, in category: Category) {
        guard let i = items[category]?.firstIndex(where: { $0.id == item.id }) else { return }
        items[category]?[i].selected.toggle()
    }

    func clean(_ scope: [Category] = Category.allCases) {
        let jobs = scope.flatMap { category in
            (items[category] ?? []).filter(\.selected).map { (category.mode, $0) }
        }
        guard !jobs.isEmpty else { return }
        cleaning = true
        let started = Date()

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let permanent = Remover.permanent
            var freed: Int64 = 0, moved: Int64 = 0, failed = 0

            for (mode, item) in jobs {
                for url in item.urls {
                    do {
                        if mode == .trash {
                            try Remover.discard(url)
                        } else {
                            try fm.removeItem(at: url)
                        }
                    } catch where mode == .delete {
                        // Ishlatilayotgan yoki himoyalangan fayllar qoladi, qolganini birma-bir o'chiramiz.
                        for child in Scanner.children(of: url) { try? fm.removeItem(at: child) }
                    } catch {
                        // Savatga ko'chmagan qoldiq joyida qoladi va «o'chmadi» deb sanaladi.
                    }
                }
                let left = Scanner.size(of: item.urls)
                if left > 0 { failed += 1 }
                if mode == .trash && !permanent { moved += item.size - left } else { freed += item.size - left }
            }

            let summary = CleanResult(freed: max(0, freed), movedToTrash: max(0, moved), failed: failed)
            await AnimationPacing.holdUntilVisible(since: started)
            await MainActor.run {
                self.cleaning = false
                self.result = summary
                self.scan()
            }
        }
    }
}
