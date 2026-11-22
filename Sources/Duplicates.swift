import SwiftUI
import CryptoKit

// MARK: - Dublikat fayllar

struct DuplicateFile: Identifiable, Hashable {
    let url: URL
    let date: Date?
    var id: String { url.path }
}

/// Mazmuni bir xil fayllar guruhi. Birinchisi — eng eskisi (asl nusxa deb hisoblanadi).
struct DuplicateGroup: Identifiable, Hashable {
    let id: String
    let size: Int64
    let files: [DuplicateFile]
    var wasted: Int64 { size * Int64(files.count - 1) }
}

enum DuplicateScanner {
    static let minSize: Int64 = 1_000_000

    static var roots: [URL] {
        ["Downloads", "Documents", "Desktop"].map { Scanner.home.appendingPathComponent($0) }
    }

    static func scan(progress: (String) -> Void) -> [DuplicateGroup] {
        // 1-qadam: hajmi bir xil fayllar — faqat ular dublikat bo'lishi mumkin.
        var bySize: [Int64: [DuplicateFile]] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey]
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in walker {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let size = Int64(v.fileSize ?? 0)
                guard size >= minSize, !Scanner.isCloudOnly(url) else { continue }
                bySize[size, default: []].append(DuplicateFile(url: url, date: v.creationDate))
            }
        }

        // 2-qadam: boshi va oxiri bo'yicha tez saralash, so'ng to'liq SHA-256.
        var groups: [DuplicateGroup] = []
        let candidates = bySize.filter { $0.value.count > 1 }
        var done = 0
        for (size, files) in candidates {
            done += 1
            if done % 20 == 0 { progress("\(done)/\(candidates.count)") }
            let quick = Dictionary(grouping: files) { hash($0.url, partial: true) ?? UUID().uuidString }
            for same in quick.values where same.count > 1 {
                let full = Dictionary(grouping: same) { hash($0.url, partial: false) ?? UUID().uuidString }
                for (digest, copies) in full where copies.count > 1 {
                    let sorted = copies.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                    groups.append(DuplicateGroup(id: digest, size: size, files: sorted))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    /// partial: faqat boshidagi va oxiridagi 64 KB — ko'p hollarda farqni shuning o'zi ko'rsatadi.
    private static func hash(_ url: URL, partial: Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 64 * 1024
        if partial {
            if let head = try? handle.read(upToCount: chunk) { hasher.update(data: head) }
            if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
                try? handle.seek(toOffset: end - UInt64(chunk))
                if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
            }
        } else {
            while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class DuplicatesStore: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progress = ""
    @Published var selected: Set<String> = []
    @Published var working = false
    @Published var confirming = false
    @Published var result: CleanResult?

    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    var selectedSize: Int64 {
        groups.reduce(0) { total, group in
            total + group.size * Int64(group.files.filter { selected.contains($0.id) }.count)
        }
    }

    var selectedCount: Int { selected.count }

    func scan() {
        guard !scanning else { return }
        scanning = true
        progress = ""
        Task.detached(priority: .userInitiated) {
            let found = DuplicateScanner.scan { text in
                Task { @MainActor in self.progress = text }
            }
            await MainActor.run {
                self.groups = found
                self.selected = self.selected.filter { id in found.contains { $0.files.contains { $0.id == id } } }
                self.scanning = false
                self.scanned = true
            }
        }
    }

    /// Bitta nusxa doim qoladi — guruhdagi oxirgi tanlanmagan faylni tanlab bo'lmaydi.
    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if selected.contains(file.id) {
            selected.remove(file.id)
        } else if group.files.filter({ !selected.contains($0.id) }).count > 1 {
            selected.insert(file.id)
        } else {
            NSSound.beep()
        }
    }

    /// Har guruhda eng eski nusxani qoldirib, qolganini tanlaydi.
    func selectAllButOldest() {
        selected = Set(groups.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func moveSelectedToTrash() {
        let targets = groups.flatMap(\.files).filter { selected.contains($0.id) }
        let sizes = Dictionary(uniqueKeysWithValues: groups.flatMap { g in g.files.map { ($0.id, g.size) } })
        guard !targets.isEmpty else { return }
        working = true
        Task.detached(priority: .userInitiated) {
            var moved: Int64 = 0, failed = 0
            var gone: Set<String> = []
            for file in targets {
                do {
                    try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                    moved += sizes[file.id] ?? 0
                    gone.insert(file.id)
                } catch {
                    failed += 1
                }
            }
            let removed = gone
            let summary = CleanResult(freed: 0, movedToTrash: moved, failed: failed)
            await MainActor.run {
                self.groups = self.groups.compactMap { group in
                    let left = group.files.filter { !removed.contains($0.id) }
                    return left.count > 1 ? DuplicateGroup(id: group.id, size: group.size, files: left) : nil
                }
                self.selected.subtract(removed)
                self.working = false
                self.result = summary
            }
        }
    }
}

// MARK: - Bo'lim

struct DuplicatesView: View {
    @ObservedObject var store: DuplicatesStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: DuplicatesView.symbol, color: DuplicatesView.color, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DuplicatesView.title).font(.title3.weight(.semibold))
                        Text(L("Yuklanmalar, Hujjatlar va Ish stolidagi mazmuni bir xil fayllar (1 MB dan katta). Har guruhda kamida bitta nusxa doim qoladi.",
                               "Files with identical content in Downloads, Documents and Desktop (over 1 MB). At least one copy in each group always stays.",
                               "Файлы с одинаковым содержимым в Загрузках, Документах и на Рабочем столе (больше 1 МБ). В каждой группе всегда остаётся хотя бы одна копия."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                if !store.groups.isEmpty {
                    HStack {
                        Text(L("Ortiqcha nusxalar: \(store.wasted.bytes)",
                               "Extra copies: \(store.wasted.bytes)",
                               "Лишние копии: \(store.wasted.bytes)"))
                            .fontWeight(.medium)
                        Spacer()
                        Button(L("Har guruhda eng eskisini qoldirib tanlash",
                                 "Select all but the oldest in each group",
                                 "Выбрать все, кроме самой старой копии")) {
                            store.selectAllButOldest()
                        }
                        .disabled(store.working)
                    }
                }
            }

            if store.scanning {
                Section {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L("Fayllar solishtirilmoqda… \(store.progress)",
                               "Comparing files… \(store.progress)",
                               "Сравнение файлов… \(store.progress)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else if store.groups.isEmpty && store.scanned {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.green)
                        Text(L("Dublikat fayllar topilmadi", "No duplicate files found", "Дубликаты не найдены"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                ForEach(store.groups) { group in
                    Section {
                        ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                            ItemRow(item: item(file, group: group, original: index == 0)) { store.toggle(file, in: group) }
                                .disabled(store.working)
                        }
                    } header: {
                        Text(L("\(group.files[0].url.lastPathComponent) · \(group.files.count) nusxa · har biri \(group.size.bytes)",
                               "\(group.files[0].url.lastPathComponent) · \(group.files.count) copies · \(group.size.bytes) each",
                               "\(group.files[0].url.lastPathComponent) · копий: \(group.files.count) · по \(group.size.bytes)"))
                            .lineLimit(1)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(DuplicatesView.title)
        .safeAreaInset(edge: .bottom) { bar }
        .alert(L("\(store.selectedCount) ta nusxa Savatga ko'chirilsinmi?", "Move \(store.selectedCount) copies to the Trash?", "Переместить копии (\(store.selectedCount)) в Корзину?"),
               isPresented: $store.confirming) {
            Button(L("Savatga ko'chirish", "Move to Trash", "В Корзину"), role: .destructive) { store.moveSelectedToTrash() }
            Button(L("Bekor qilish", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L("\(store.selectedCount) ta nusxa (\(store.selectedSize.bytes)) Savatga ko'chiriladi. Har guruhda kamida bitta nusxa qoladi.",
                   "\(store.selectedCount) copies (\(store.selectedSize.bytes)) will be moved to the Trash. At least one copy of each file stays.",
                   "Копий: \(store.selectedCount) (\(store.selectedSize.bytes)) будут перемещены в Корзину. Хотя бы одна копия каждого файла останется."))
        }
        .sheet(item: $store.result) { ResultView(result: $0) }
        .task { if !store.scanned { store.scan() } }
    }

    private func item(_ file: DuplicateFile, group: DuplicateGroup, original: Bool) -> CleanItem {
        var detail = Scanner.tildePath(file.url.deletingLastPathComponent())
        if let date = file.date { detail += " · " + Scanner.ago(date) }
        if original { detail = L("Eng eskisi · ", "Oldest · ", "Самая старая · ") + detail }
        return CleanItem(
            id: file.id, name: file.url.lastPathComponent, detail: detail, urls: [file.url],
            size: group.size, selected: store.selected.contains(file.id)
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

    static var title: String { L("Dublikatlar", "Duplicates", "Дубликаты") }
    static let symbol = "plus.square.on.square"
    static let color = Color.mint
}
