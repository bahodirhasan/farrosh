import SwiftUI

// MARK: - Disk taqsimoti: band joy nimalarga ketgan

/// Uy papkasidagi asosiy guruhlar va macOS tizim hajmi. Fonda hisoblanadi.
struct FolderUsage {
    var documents: Int64 = 0
    var media: Int64 = 0
    var library: Int64 = 0
    var system: Int64 = 0

    static let documentFolders = ["Documents", "Desktop", "Downloads"]
    static let mediaFolders = ["Movies", "Music", "Pictures"]

    static func measure() -> FolderUsage {
        func sum(_ names: [String]) -> Int64 {
            names.reduce(0) { $0 + Scanner.size(of: Scanner.home.appendingPathComponent($1)) }
        }
        // macOS: tizim bo'limi + Preboot, Recovery, VM. APFS'da ular bitta konteynerda,
        // shuning uchun «hamma band joy − ma'lumotlar bo'limi» deb hisoblanadi.
        func usedKB(_ path: String) -> Int64? {
            let df = Shell.run("/bin/df", ["-k", path]).output
            guard let line = df.split(separator: "\n").dropFirst().first else { return nil }
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            return cols.count > 2 ? Int64(cols[2]) : nil
        }
        var system: Int64 = 0
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacity,
           let data = usedKB("/System/Volumes/Data") {
            system = max(0, Int64(total - avail) - data * 1024)
        } else if let root = usedKB("/") {
            system = root * 1024
        }
        // Bulut papkalari (Google Drive, iCloud) ochilganda fayllarni yuklay boshlaydi va o'qishni
        // to'xtatib qo'yadi; boshqa ilovalar konteynerlari esa macOS ruxsat so'rashiga sabab bo'ladi.
        let skip: Set<String> = ["CloudStorage", "Mobile Documents", "Containers", "Group Containers", "Daemon Containers"]
        let library = Scanner.children(of: Scanner.home.appendingPathComponent("Library"))
            .filter { !skip.contains($0.lastPathComponent) }
            .reduce(Int64(0)) { $0 + Scanner.size(of: $1) }
        return FolderUsage(documents: sum(documentFolders), media: sum(mediaFolders), library: library, system: system)
    }
}

struct StorageSegment: Identifiable {
    let id: String
    let title: String
    let size: Int64
    let color: Color
    /// Hali hisoblanmoqda.
    var pending = false
}

struct StorageHeader: View {
    @ObservedObject var store: Store
    @ObservedObject var apps: AppsStore

    /// Band joy bo'laklari — yig'indisi «band» hajmiga teng.
    private var segments: [StorageSegment] {
        let disk = store.disk
        let folders = store.folders
        // O'rnatish fayllari odatda Yuklanmalar ichida — ikki marta sanamaslik uchun chiqarib tashlanadi.
        let junk = Category.allCases.filter { $0 != .installers }.reduce(0) { $0 + store.foundSize($1) }
        let appsSize = apps.totalSize
        // Keshlar, loglar va qoldiqlar ~/Library ichida — ilova ma'lumotlaridan ayirib ko'rsatiladi.
        let libraryJunk = [Category.appCaches, .logs, .leftovers].reduce(0) { $0 + store.foundSize($1) }
        let appData = max(0, (folders?.library ?? 0) - libraryJunk)
        let known = appsSize + (folders?.documents ?? 0) + (folders?.media ?? 0) + appData + junk + (folders?.system ?? 0)
        // Papkalar hali o'lchanmagan bo'lsa, «Boshqa» ham noma'lum — katta kulrang bo'lak ko'rsatilmaydi.
        let other = folders == nil ? 0 : max(0, disk.used - known)
        return [
            StorageSegment(id: "apps", title: L("Ilovalar", "Apps", "Приложения"), size: appsSize,
                           color: Color(hex: 0x3B82F6), pending: apps.loading),
            StorageSegment(id: "docs", title: L("Hujjatlar", "Documents", "Документы"), size: folders?.documents ?? 0,
                           color: Color(hex: 0x8B5CF6), pending: folders == nil),
            StorageSegment(id: "media", title: L("Media", "Media", "Медиа"), size: folders?.media ?? 0,
                           color: Color(hex: 0xEC4899), pending: folders == nil),
            StorageSegment(id: "appdata", title: L("Ilova ma'lumotlari", "App data", "Данные приложений"), size: appData,
                           color: Color(hex: 0x14B8A6), pending: folders == nil),
            StorageSegment(id: "junk", title: L("Keraksiz fayllar", "Junk files", "Ненужные файлы"), size: junk,
                           color: Color(hex: 0xF5B400), pending: !store.scanning.isEmpty),
            StorageSegment(id: "system", title: "macOS", size: folders?.system ?? 0,
                           color: Color(hex: 0x64748B), pending: folders == nil),
            StorageSegment(id: "other", title: L("Boshqa", "Other", "Другое"),
                           size: other, color: Color(hex: 0x94A3B8), pending: folders == nil),
        ]
    }

    var body: some View {
        let disk = store.disk
        let free = SplitSize(disk.free)
        VStack(alignment: .leading, spacing: 16) {
            // 1. Disk nomi va hajmi
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                Text(disk.name).font(.headline)
                Text(disk.total.bytes)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
            }

            // 2. Asosiy raqam: qancha bo'sh — va qancha tozalash mumkin
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(free.number)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(L("\(free.unit) bo'sh", "\(free.unit) free", "\(free.unit) свободно"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(L("\(disk.used.bytes) band · \(Int((disk.usedFraction * 100).rounded()))%",
                           "\(disk.used.bytes) used · \(Int((disk.usedFraction * 100).rounded()))%",
                           "Занято \(disk.used.bytes) · \(Int((disk.usedFraction * 100).rounded()))%"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                cleanableCard
            }

            // 3. Taqsimot chizig'i
            bar

            // 4. Izoh: har bir bo'lak nomi va hajmi
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14, alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(segments) { legend($0) }
                legend(StorageSegment(id: "free", title: L("Bo'sh", "Free", "Свободно"), size: disk.free,
                                      color: Color.secondary.opacity(0.22)))
            }

            if disk.purgeable > 500_000_000 {
                Label(L("Bo'sh joyning \(disk.purgeable.bytes) qismini hozir iCloud nusxalari va vaqtinchalik tizim fayllari egallab turibdi. Joy kerak bo'lganda macOS ularni o'zi bo'shatadi.",
                        "\(disk.purgeable.bytes) of the free space is held right now by iCloud copies and temporary system files. macOS frees it by itself when space is needed.",
                        "\(disk.purgeable.bytes) свободного места сейчас занято копиями iCloud и временными файлами. macOS освободит их сама, когда понадобится место."),
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .task(id: store.disk.used) { await store.measureFolders() }
    }

    private var cleanableCard: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(L("Tozalash mumkin", "Can be cleaned", "Можно очистить"), systemImage: "sparkles")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(store.totalSelected.bytes)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bar: some View {
        GeometryReader { geo in
            let total = max(Double(store.disk.total), 1)
            let visible = segments.filter { $0.size > 0 }
            // Bo'laklar orasida 2 pt oraliq; juda kichiklari ham ko'rinsin.
            let width = geo.size.width - CGFloat(max(0, visible.count)) * 2
            HStack(spacing: 2) {
                ForEach(visible) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(4, width * Double(segment.size) / total))
                        .help("\(segment.title): \(segment.size.bytes)")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.3), value: segments.map(\.size))
    }

    private func legend(_ segment: StorageSegment) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(segment.color)
                .frame(width: 12, height: 12)
            Text(segment.title).lineLimit(1)
            Spacer(minLength: 4)
            if segment.pending && segment.size == 0 {
                ProgressView().controlSize(.mini)
            } else {
                Text(segment.size.bytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// «36,69 GB» → katta raqam va kichik birlik.
struct SplitSize {
    let number: String
    let unit: String

    init(_ bytes: Int64) {
        let text = bytes.bytes
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        number = parts.first ?? text
        unit = parts.count > 1 ? parts[1] : ""
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
