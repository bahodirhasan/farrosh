import AppKit
import SwiftUI

// Ko'zi ojiz va ko'rishi past foydalanuvchilar uchun: VoiceOver xabarlari va qatorlarni tugma qilib o'qitish.

/// VoiceOver'ga ovozli xabar (masalan, «Skanerlash tugadi»). VoiceOver o'chiq bo'lsa hech narsa bo'lmaydi.
@MainActor
func announce(_ message: String) {
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
    )
}

extension View {
    /// Bosiladigan (onTapGesture) qator VoiceOver uchun bitta tugma bo'lib o'qiladi:
    /// "Katta fayllar, 12 GB, tugma". VO + Probel bosilganda `action` bajariladi.
    func accessibleRow(_ label: String, value: String = "", hint: String = "", action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}

/// Aylanuvchi belgi o'qilganda "Skanerlanmoqda" deydi.
var scanningSpeech: String { L("Skanerlanmoqda", "Scanning", "Сканирование") }
