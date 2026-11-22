import SwiftUI

/// Tozalash usuli: kesh va loglar butunlay o'chiriladi, qoldiqlar Savatga ko'chiriladi.
enum CleanMode {
    case delete
    case trash
}

/// Savatga ko'chirish yoki butunlay o'chirish — Sozlamalardagi tanlovga qarab.
enum Remover {
    static let permanentKey = "deletePermanently"
    static var permanent: Bool { UserDefaults.standard.bool(forKey: permanentKey) }

    static func discard(_ url: URL) throws {
        if permanent {
            try FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// "Savatga ko'chirildi" yoki "butunlay o'chirildi".
    static var doneVerb: String {
        permanent ? L("butunlay o'chirildi", "deleted permanently", "удалены навсегда")
                  : L("Savatga ko'chirildi", "moved to the Trash", "перемещены в Корзину")
    }
}

enum Category: String, CaseIterable, Identifiable, Hashable {
    case appCaches, logs, devCaches, installers, leftovers, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appCaches: return L("Ilovalar keshi", "App caches", "Кэш приложений")
        case .logs: return L("Loglar", "Logs", "Журналы")
        case .devCaches: return L("Dasturchi keshlari", "Developer caches", "Кэши разработчика")
        case .installers: return L("O'rnatish fayllari", "Installers", "Установщики")
        case .leftovers: return L("O'chirilgan ilovalar qoldig'i", "Leftovers of removed apps", "Остатки удалённых приложений")
        case .trash: return L("Savat", "Trash", "Корзина")
        }
    }

    /// Chap panel uchun qisqa nom.
    var shortTitle: String { self == .leftovers ? L("Ilova qoldiqlari", "App leftovers", "Остатки") : title }

    var subtitle: String {
        switch self {
        case .appCaches: return L("Ilovalar qayta yaratadigan vaqtinchalik fayllar", "Temporary files that apps recreate", "Временные файлы, которые приложения создают заново")
        case .logs: return L("Ilovalar va tizim yozgan jurnallar", "Logs written by apps and the system", "Журналы приложений и системы")
        case .devCaches: return L("npm, pip, Homebrew, Xcode, simulyatorlar va boshqalar", "npm, pip, Homebrew, Xcode, simulators and more", "npm, pip, Homebrew, Xcode, симуляторы и другие")
        case .installers: return L("Yuklab olingan .dmg va .pkg fayllari", "Downloaded .dmg and .pkg files", "Скачанные файлы .dmg и .pkg")
        case .leftovers: return L("Ilovasi Mac'da yo'q sozlama va ma'lumotlar", "Settings and data of apps no longer on this Mac", "Настройки и данные приложений, которых нет на Mac")
        case .trash: return L("Savatdagi fayllar butunlay o'chadi", "Files in the Trash are deleted for good", "Файлы в Корзине удаляются навсегда")
        }
    }

    var footnote: String {
        switch self {
        case .appCaches:
            return L("Kesh — ilovalar tezroq ishlashi uchun saqlaydigan nusxalar. O'chirilsa, ilova kerakli qismini qayta yuklab oladi.", "Caches are copies apps keep to work faster. If removed, an app simply downloads what it needs again.", "Кэш — копии, которые приложения хранят для быстрой работы. После удаления приложение заново загрузит нужное.")
        case .logs:
            return L("Loglar faqat xatolarni tekshirish uchun kerak. Ularni o'chirish ilovalar ishiga ta'sir qilmaydi.", "Logs are only needed for troubleshooting. Deleting them doesn't affect how apps work.", "Журналы нужны только для поиска ошибок. Их удаление не влияет на работу приложений.")
        case .devCaches:
            return L("Paket menejerlari va Xcode yig'ish keshlari. Keyingi o'rnatish yoki yig'ishda qayta yuklanadi.", "Package manager and Xcode build caches. They are rebuilt on the next install or build.", "Кэши пакетных менеджеров и сборки Xcode. Они появятся снова при следующей установке или сборке.")
        case .installers:
            return L("Ilova o'rnatilgach, uning .dmg yoki .pkg fayli kerak bo'lmaydi. Ikki haftadan eskilari avtomatik tanlanadi. Yuklanmalar, Ish stoli va Hujjatlar papkalari tekshiriladi.", "Once an app is installed, its .dmg or .pkg is no longer needed. Files older than two weeks are selected automatically. Downloads, Desktop and Documents are checked.", "После установки приложения его .dmg или .pkg больше не нужен. Файлы старше двух недель выбираются автоматически. Проверяются Загрузки, Рабочий стол и Документы.")
        case .leftovers:
            return L("«Tekshiring» belgisi bor elementlar taxminan topilgan — tanlashdan oldin ko'rib chiqing.", "Items marked «Review» were matched by guesswork — look them over before selecting.", "Элементы с пометкой «Проверьте» найдены приблизительно — просмотрите их перед выбором.")
        case .trash:
            return L("Savat bo'shatilgach fayllarni qaytarib bo'lmaydi.", "Once the Trash is emptied, files can't be recovered.", "После очистки Корзины файлы нельзя восстановить.")
        }
    }

    var symbol: String {
        switch self {
        case .appCaches: return "square.stack.3d.up.fill"
        case .logs: return "doc.text.fill"
        case .devCaches: return "hammer.fill"
        case .installers: return "shippingbox.fill"
        case .leftovers: return "app.dashed"
        case .trash: return "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .appCaches: return .blue
        case .logs: return .gray
        case .devCaches: return .indigo
        case .installers: return .orange
        case .leftovers: return .pink
        case .trash: return .red
        }
    }

    var mode: CleanMode { self == .leftovers || self == .installers ? .trash : .delete }
}

struct CleanItem: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let urls: [URL]
    let size: Int64
    var selected: Bool
    var needsReview = false
}

struct DiskInfo {
    var name = "Macintosh HD"
    var total: Int64 = 0
    var free: Int64 = 0
    /// Bo'sh joyning macOS kerak bo'lganda o'zi bo'shatadigan qismi (iCloud nusxalari, vaqtinchalik fayllar).
    var purgeable: Int64 = 0
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// «Bo'sh» — Finder va Tizim sozlamalaridagi bilan bir xil (o'zi bo'shaydigan joy ham ichida).
    static func current() -> DiskInfo {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return DiskInfo() }
        let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return DiskInfo(
            name: v.volumeLocalizedName ?? "Macintosh HD",
            total: Int64(v.volumeTotalCapacity ?? 0),
            free: free,
            purgeable: max(0, free - Int64(v.volumeAvailableCapacity ?? 0))
        )
    }
}

struct CleanResult: Identifiable {
    let id = UUID()
    let freed: Int64
    let movedToTrash: Int64
    let failed: Int
}

extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
