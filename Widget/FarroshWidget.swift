import SwiftUI
import WidgetKit

// Farrosh vidjetlari: Mac ish stoli va Bildirishnomalar markazi uchun uch uslub.
// Vidjet o'zi diskni o'lchaydi; bosilganda Farrosh ochiladi.

// MARK: - Ma'lumot

struct DiskEntry: TimelineEntry {
    let date: Date
    let name: String
    let total: Int64
    let free: Int64

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func now() -> DiskEntry {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
        return DiskEntry(
            date: Date(),
            name: v?.volumeLocalizedName ?? "Macintosh HD",
            total: Int64(v?.volumeTotalCapacity ?? 0),
            free: v?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    static let preview = DiskEntry(date: Date(), name: "Macintosh HD", total: 245_110_000_000, free: 43_890_000_000)
}

struct DiskProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiskEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (DiskEntry) -> Void) {
        completion(context.isPreview ? .preview : .now())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskEntry>) -> Void) {
        // Disk tez o'zgarmaydi: har 15 daqiqada yangilash yetarli.
        completion(Timeline(entries: [.now()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

// MARK: - Holat: rang hech qachon yolg'iz ma'no tashimaydi — doim belgi va so'z bilan

enum DiskStatus {
    case ok, low, critical

    init(free: Int64) {
        switch free {
        case ..<10_000_000_000: self = .critical
        case ..<20_000_000_000: self = .low
        default: self = .ok
        }
    }

    var title: String {
        switch self {
        case .ok: return "Joy yetarli"
        case .low: return "Joy kamaymoqda"
        case .critical: return "Joy kam qoldi"
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .low: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    /// Sof #00FF00 / #FF0000 emas: yorug' va qorong'i fonda o'qiladigan ohanglar.
    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .ok: return scheme == .dark ? Color(hex: 0x42BE65) : Color(hex: 0x198038)
        case .low: return scheme == .dark ? Color(hex: 0xF1C21B) : Color(hex: 0x8E6A00)
        case .critical: return scheme == .dark ? Color(hex: 0xFF8389) : Color(hex: 0xDA1E28)
        }
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

/// «43,9 GB» → raqam va birlik alohida: raqam katta, birlik kichikroq.
struct SizeText {
    let number: String
    let unit: String

    init(_ bytes: Int64) {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = bytes >= 1_000_000_000_000 ? [.useTB] : [.useGB]
        let text = f.string(fromByteCount: bytes)
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        number = parts.first ?? text
        unit = parts.count > 1 ? parts[1] : ""
    }

    var full: String { unit.isEmpty ? number : "\(number) \(unit)" }
}

// MARK: - 1. Halqa

struct RingWidgetView: View {
    let entry: DiskEntry
    /// Oldindan ko'rish rasmlari uchun: o'lchamni tashqaridan berish.
    var forcedFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let status = DiskStatus(free: entry.free)
        if family == .systemSmall {
            VStack(spacing: 8) {
                ring(status: status, size: 104, line: 11)
                Label(status.title, systemImage: status.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        } else {
            HStack(spacing: 18) {
                ring(status: status, size: 116, line: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Band: \(SizeText(entry.used).full)")
                        Text("Jami: \(SizeText(entry.total).full)")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Label(status.title, systemImage: status.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.color(scheme))
                }
                .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
        }
    }

    private func ring(status: DiskStatus, size: CGFloat, line: CGFloat) -> some View {
        let free = SizeText(entry.free)
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: line)
            Circle()
                .trim(from: 0, to: entry.usedFraction)
                .stroke(status == .ok ? Color.accentColor : status.color(scheme),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(free.number)
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(free.unit) bo'sh")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, line + 4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 2. Batafsil

struct DetailWidgetView: View {
    let entry: DiskEntry
    /// Oldindan ko'rish rasmlari uchun: o'lchamni tashqaridan berish.
    var forcedFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let status = DiskStatus(free: entry.free)
        let free = SizeText(entry.free)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.secondary)
                Text(entry.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text("Farrosh")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(free.number)
                    .font(.system(size: family == .systemSmall ? 34 : 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("\(free.unit) bo'sh")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            bar(status: status)

            Spacer(minLength: 8)

            if family == .systemSmall {
                Label(status.title, systemImage: status.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color(scheme))
                    .lineLimit(1)
            } else {
                HStack {
                    stat("Band", SizeText(entry.used).full)
                    Spacer()
                    stat("Jami", SizeText(entry.total).full)
                    Spacer()
                    Label(status.title, systemImage: status.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.color(scheme))
                }
            }
        }
    }

    private func bar(status: DiskStatus) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(status == .ok ? Color.accentColor : status.color(scheme))
                    .frame(width: max(8, geo.size.width * entry.usedFraction))
            }
        }
        .frame(height: 8)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - 3. Rangli

/// To'liq rangli fon. Gradient kulrangdan o'tmasligi uchun o'rtada haqiqiy rangli to'xtash bor.
struct ColorWidgetView: View {
    let entry: DiskEntry
    /// Oldindan ko'rish rasmlari uchun: o'lchamni tashqaridan berish.
    var forcedFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { forcedFamily ?? envFamily }

    /// Sof oq emas: rangli fonda ko'zni qamashtirmaydigan oqish.
    private let ink = Color.white.opacity(0.94)
    private let soft = Color.white.opacity(0.78)

    var body: some View {
        let status = DiskStatus(free: entry.free)
        let free = SizeText(entry.free)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Farrosh")
                Spacer(minLength: 0)
                if status != .ok {
                    Image(systemName: status.symbol)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(soft)

            Spacer(minLength: 4)

            Text(free.number)
                .font(.system(size: family == .systemSmall ? 44 : 52, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(family == .systemSmall ? "\(free.unit) bo'sh" : "\(free.unit) bo'sh · \(status.title.lowercased())")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(soft)
                .lineLimit(1)

            Spacer(minLength: 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(ink).frame(width: max(8, geo.size.width * entry.usedFraction))
                }
            }
            .frame(height: 6)
        }
    }

    static func background(free: Int64) -> LinearGradient {
        let colors: [Color]
        switch DiskStatus(free: free) {
        case .ok: colors = [Color(hex: 0x3D5AFE), Color(hex: 0x1E88E5), Color(hex: 0x0EBAAE)]
        case .low: colors = [Color(hex: 0xB45309), Color(hex: 0xC2410C), Color(hex: 0xBE123C)]
        case .critical: colors = [Color(hex: 0xBE123C), Color(hex: 0xA21CAF), Color(hex: 0x6D28D9)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Vidjetlar

extension View {
    /// macOS 14 dan boshlab vidjet foni containerBackground orqali beriladi.
    @ViewBuilder
    func widgetBackground<B: ShapeStyle>(_ style: B) -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(style, for: .widget)
        } else {
            padding().background(style)
        }
    }
}

struct RingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "uz.farrosh.widget.ring", provider: DiskProvider()) { entry in
            RingWidgetView(entry: entry).widgetBackground(.background)
        }
        .configurationDisplayName("Farrosh · Halqa")
        .description("Diskning qancha qismi bandligini halqa shaklida ko'rsatadi.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DetailWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "uz.farrosh.widget.detail", provider: DiskProvider()) { entry in
            DetailWidgetView(entry: entry).widgetBackground(.background)
        }
        .configurationDisplayName("Farrosh · Batafsil")
        .description("Bo'sh, band va jami joy — bir qarashda.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ColorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "uz.farrosh.widget.color", provider: DiskProvider()) { entry in
            ColorWidgetView(entry: entry).widgetBackground(ColorWidgetView.background(free: entry.free))
        }
        .configurationDisplayName("Farrosh · Rangli")
        .description("Bo'sh joy katta raqamda. Joy kamaysa, rangi o'zgaradi.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if !WIDGET_PREVIEW
@main
#endif
struct FarroshWidgets: WidgetBundle {
    var body: some Widget {
        RingWidget()
        DetailWidget()
        ColorWidget()
    }
}
