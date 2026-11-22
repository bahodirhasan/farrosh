import SwiftUI
import CoreServices

// MARK: - Katta va eski fayllar

/// Uy papkasidagi katta fayl. Bular foydalanuvchining shaxsiy fayllari — hech qachon o'zi tanlanmaydi.
struct LargeFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    /// Spotlight yozgan "oxirgi ochilgan" sana, bo'lmasa o'zgartirilgan sana.
    let date: Date?
    var id: String { url.path }
}

enum AgeFilter: String, CaseIterable, Identifiable {
    case all, months3, year1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("Hammasi", "All", "Все")
        case .months3: return L("3 oydan eski", "Older than 3 months", "Старше 3 месяцев")
        case .year1: return L("1 yildan eski", "Older than a year", "Старше года")
        }
    }

    var cutoff: Date? {
        switch self {
        case .all: return nil
        case .months3: return Date().addingTimeInterval(-90 * 86_400)
        case .year1: return Date().addingTimeInterval(-365 * 86_400)
        }
    }
}

enum LargeFileScanner {
    /// Eng kichik chegara — filtr undan katta qiymatlarda qayta skanerlashsiz ishlaydi.
    static let floor: Int64 = 50_000_000

    /// Kutubxona va virtual muhit papkalari — minglab mayda fayl, foydalanuvchining o'z fayli emas.
    private static let skipNames: Set<String> = [
        "node_modules", "venv", ".venv", "site-packages", "__pycache__", "DerivedData", "Pods", "vendor",
    ]

    /// `progress` har bir necha ming fayldan keyin shu paytgacha topilganlarini beradi.
    static func scan(progress: ([LargeFile]) -> Void = { _ in }) -> [LargeFile] {
        let home = Scanner.home
        // Library — ilovalar ma'lumotlari (kesh, pochta, xabarlar); ular boshqa bo'limlarda ko'rsatiladi.
        let skip: Set<String> = [home.appendingPathComponent("Library").path]
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]

        guard let walker = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys,
            // Paketlar (.app, Rasmlar kutubxonasi) bir butun — ichiga kirilmaydi.
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [LargeFile] = []
        var seen = 0
        for case let url as URL in walker {
            if skip.contains(url.path) || skipNames.contains(url.lastPathComponent) {
                walker.skipDescendants(); continue
            }
            seen += 1
            if seen % 3000 == 0 { progress(found.sorted { $0.size > $1.size }) }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            guard size >= floor, !Scanner.isCloudOnly(url) else { continue }
            found.append(LargeFile(url: url, size: size, date: lastUsed(url) ?? v.contentModificationDate))
        }
        return found.sorted { $0.size > $1.size }
    }

    private static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

@MainActor
final class LargeFilesStore: ObservableObject {
    static let sizeKey = "largeFilesMinMB"
    static let sizeOptions = [50, 100, 500, 1000]

    @Published var files: [LargeFile] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var selected: Set<String> = []
    @Published var age = AgeFilter.all
    @Published var minMB: Int {
        didSet { UserDefaults.standard.set(minMB, forKey: Self.sizeKey) }
    }
    @Published var working = false
    @Published var confirming = false
    @Published var result: CleanResult?

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.sizeKey)
        minMB = Self.sizeOptions.contains(saved) ? saved : 100
    }

    var visible: [LargeFile] {
        let minSize = Int64(minMB) * 1_000_000
        let cutoff = age.cutoff
        return files.filter { file in
            guard file.size >= minSize else { return false }
            guard let cutoff else { return true }
            return (file.date ?? .distantPast) < cutoff
        }
    }

    var visibleSize: Int64 { visible.reduce(0) { $0 + $1.size } }
    var selectedFiles: [LargeFile] { files.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .userInitiated) {
            let found = LargeFileScanner.scan { partial in
                // Natijalar qidiruv davomida ko'rinib boradi.
                Task { @MainActor in if self.scanning { self.files = partial } }
            }
            await MainActor.run {
                self.files = found
                self.selected = self.selected.filter { id in found.contains { $0.id == id } }
                self.scanning = false
                self.scanned = true
            }
        }
    }

    func toggle(_ file: LargeFile) {
        if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
    }

    func setAllVisible(_ on: Bool) {
        let ids = Set(visible.map(\.id))
        if on { selected.formUnion(ids) } else { selected.subtract(ids) }
    }

    /// Shaxsiy fayllar sozlamadan qat'i nazar har doim Savatga tushadi — xato bo'lsa qaytarib olinadi.
    func moveSelectedToTrash() {
        let targets = selectedFiles
        guard !targets.isEmpty else { return }
        working = true
        Task.detached(priority: .userInitiated) {
            var moved: Int64 = 0, failed = 0
            var gone: Set<String> = []
            for file in targets {
                do {
                    try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                    moved += file.size
                    gone.insert(file.id)
                } catch {
                    failed += 1
                }
            }
            let removed = gone
            let summary = CleanResult(freed: 0, movedToTrash: moved, failed: failed)
            await MainActor.run {
                self.files.removeAll { removed.contains($0.id) }
                self.selected.subtract(removed)
                self.working = false
                self.result = summary
            }
        }
    }
}

// MARK: - Bo'lim

struct LargeFilesView: View {
    @ObservedObject var store: LargeFilesStore

    var body: some View {
        let list = store.visible
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: LargeFilesView.symbol, color: LargeFilesView.color, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LargeFilesView.title).font(.title3.weight(.semibold))
                        Text(L("Uy papkangizdagi eng katta fayllar. Hech biri o'zi tanlanmaydi — keraksizini o'zingiz belgilang, ular Savatga ko'chiriladi.",
                               "The biggest files in your home folder. Nothing is selected for you — mark what you don't need and it goes to the Trash.",
                               "Самые большие файлы в вашей папке пользователя. Ничего не выбирается автоматически — отметьте ненужное, и оно попадёт в Корзину."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                Picker(L("Hajmi kamida", "At least", "Размер от"), selection: $store.minMB) {
                    ForEach(LargeFilesStore.sizeOptions, id: \.self) { mb in
                        Text((Int64(mb) * 1_000_000).bytes).tag(mb)
                    }
                }
                Picker(L("Oxirgi ochilgan", "Last opened", "Последнее открытие"), selection: $store.age) {
                    ForEach(AgeFilter.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                if store.scanning && store.files.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L("Fayllar qidirilmoqda… Bu bir daqiqa olishi mumkin.",
                               "Searching files… This may take a minute.",
                               "Поиск файлов… Это может занять минуту."))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.green)
                        Text(L("Bu shartlarga mos fayl yo'q", "No files match these filters", "Нет файлов по этим условиям"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(list) { file in
                        ItemRow(item: item(file)) { store.toggle(file) }
                            .disabled(store.working)
                    }
                }
            } header: {
                if store.scanning && !store.files.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(L("Qidirilmoqda… \(list.count) ta topildi", "Searching… \(list.count) found", "Поиск… найдено: \(list.count)"))
                    }
                } else if !list.isEmpty {
                    Text(L("\(list.count) ta fayl · jami \(store.visibleSize.bytes)",
                           "\(list.count) files · \(store.visibleSize.bytes) total",
                           "Файлов: \(list.count) · всего \(store.visibleSize.bytes)"))
                }
            } footer: {
                Text(L("Library papkasi, yashirin fayllar va ilovalar bu ro'yxatga kirmaydi. Fayl turgan joyni ochish uchun uning yonidagi → tugmasini bosing.",
                       "The Library folder, hidden files and apps aren't included. Click → next to a file to open its location in Finder.",
                       "Папка Library, скрытые файлы и приложения не учитываются. Нажмите → рядом с файлом, чтобы открыть его папку в Finder."))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(LargeFilesView.title)
        .toolbar {
            ToolbarItem {
                let all = !list.isEmpty && list.allSatisfy { store.selected.contains($0.id) }
                Button(all ? L("Hech birini tanlamaslik", "Deselect all", "Снять выбор")
                           : L("Hammasini tanlash", "Select all", "Выбрать все")) {
                    store.setAllVisible(!all)
                }
                .disabled(list.isEmpty || store.working)
            }
        }
        .safeAreaInset(edge: .bottom) { bar }
        .alert(L("\(store.selectedFiles.count) ta fayl Savatga ko'chirilsinmi?", "Move \(store.selectedFiles.count) files to the Trash?", "Переместить файлы (\(store.selectedFiles.count)) в Корзину?"),
               isPresented: $store.confirming) {
            Button(L("Savatga ko'chirish", "Move to Trash", "В Корзину"), role: .destructive) { store.moveSelectedToTrash() }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L("\(store.selectedFiles.count) ta fayl (\(store.selectedSize.bytes)) Savatga ko'chiriladi. Savatni bo'shatmaguningizcha ularni qaytarib olish mumkin.",
                   "\(store.selectedFiles.count) files (\(store.selectedSize.bytes)) will be moved to the Trash. You can restore them until you empty it.",
                   "Файлов: \(store.selectedFiles.count) (\(store.selectedSize.bytes)) будут перемещены в Корзину. Их можно вернуть, пока Корзина не очищена."))
        }
        .sheet(item: $store.result) { ResultView(result: $0) }
        .task { if !store.scanned { store.scan() } }
    }

    private func item(_ file: LargeFile) -> CleanItem {
        var detail = Scanner.tildePath(file.url.deletingLastPathComponent())
        if let date = file.date { detail += " · " + L("ochilgan: ", "opened ", "открыто ") + Scanner.ago(date) }
        return CleanItem(
            id: file.id, name: file.url.lastPathComponent, detail: detail, urls: [file.url],
            size: file.size, selected: store.selected.contains(file.id)
        )
    }

    private var bar: some View {
        let size = store.selectedSize
        return VStack(spacing: 0) {
            Divider()
            Button { store.confirming = true } label: {
                HStack(spacing: 8) {
                    if store.working { ProgressView().controlSize(.small).tint(.white) }
                    Text(store.working ? L("Ko'chirilmoqda…", "Moving…", "Перемещение…")
                         : size == 0 ? L("Savatga ko'chirish", "Move to Trash", "В Корзину")
                         : L("Savatga ko'chirish", "Move to Trash", "В Корзину") + " · \(size.bytes)")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: .red))
            .disabled(store.working || size == 0)
            .frame(maxWidth: FormMetrics.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }

    static var title: String { L("Katta fayllar", "Large files", "Большие файлы") }
    static let symbol = "doc.on.doc.fill"
    static let color = Color.brown
}

/// Umumiy ko'rinishdagi «Katta fayllar» qatori.
struct LargeFilesEntryRow: View {
    @ObservedObject var store: LargeFilesStore
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: LargeFilesView.symbol, color: LargeFilesView.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(LargeFilesView.title)
                Text(L("Uzoq vaqt ochilmagan videolar, arxivlar va boshqa katta fayllar",
                       "Videos, archives and other big files you haven't opened in a while",
                       "Видео, архивы и другие большие файлы, которые давно не открывались"))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if store.scanning {
                ProgressView().controlSize(.small)
            } else if store.scanned {
                Text(store.visibleSize.bytes).monospacedDigit().foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
