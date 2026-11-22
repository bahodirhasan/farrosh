import SwiftUI

// MARK: - Til

/// Ilova tili. Sozlamalarda tanlanadi va darhol qo'llanadi.
enum AppLanguage: String, CaseIterable, Identifiable {
    case uz, en, ru

    static let key = "language"

    var id: String { rawValue }

    /// Har bir til o'z nomi bilan ko'rsatiladi.
    var name: String {
        switch self {
        case .uz: return "O'zbekcha"
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    var locale: Locale {
        switch self {
        case .uz: return Locale(identifier: "uz_Latn_UZ")
        case .en: return Locale(identifier: "en_US")
        case .ru: return Locale(identifier: "ru_RU")
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .uz
    }
}

/// Matnni joriy tilda qaytaradi: L("O'zbekcha", "English", "Русский").
func L(_ uz: String, _ en: String, _ ru: String) -> String {
    switch AppLanguage.current {
    case .uz: return uz
    case .en: return en
    case .ru: return ru
    }
}

// MARK: - Kunduzgi / kechki ko'rinish

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("Avtomatik", "Automatic", "Автоматически")
        case .light: return L("Kunduzgi", "Light", "Светлое")
        case .dark: return L("Kechki", "Dark", "Тёмное")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// Butun ilovaga (asosiy oyna, sozlamalar, ogohlantirishlar) qo'llanadi.
    static func apply(_ value: Appearance = current) {
        switch value {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension AppLanguage {
    /// Menyu satridagi tizim buyruqlari (Edit, Window…) ham shu tilda bo'lishi uchun —
    /// macOS buni keyingi ishga tushirishda qo'llaydi.
    static func syncSystemMenus(_ raw: String) {
        UserDefaults.standard.set([raw], forKey: "AppleLanguages")
    }
}
