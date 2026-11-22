import SwiftUI

// MARK: - Tozalash animatsiyasi

/// Tozalash davomida oyna ustida ko'rinadigan karta: supurayotgan belgi, uchib ketayotgan chang
/// zarralari va aylanuvchi halqa. Holat saqlamaydi — hammasi vaqtdan hisoblanadi.
struct CleaningOverlay: View {
    var title = L("Tozalanmoqda…", "Cleaning…", "Очистка…")
    var subtitle: String?
    var color: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.22)).ignoresSafeArea()
            VStack(spacing: 18) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    scene(t)
                }
                .frame(width: 150, height: 150)
                VStack(spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 30)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .combine)
    }

    private func scene(_ t: Double) -> some View {
        ZStack {
            // Aylanuvchi halqa.
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 6)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(t * 220))

            // Chang zarralari: pastdan chiqib, yon tomonga uchib, so'nadi.
            ForEach(0..<10, id: \.self) { i in
                let period = 1.6
                let phase = ((t + Double(i) * period / 10).truncatingRemainder(dividingBy: period)) / period
                let side: Double = i.isMultiple(of: 2) ? 1 : -1
                let spread = 18 + Double(i % 5) * 7
                Circle()
                    .fill(color.opacity(0.75))
                    .frame(width: 4 + CGFloat(i % 3) * 2, height: 4 + CGFloat(i % 3) * 2)
                    .offset(x: side * (10 + phase * spread * 1.6),
                            y: 26 - phase * 62 + sin(phase * .pi * 2 + Double(i)) * 4)
                    .opacity(phase < 0.15 ? phase / 0.15 : (1 - phase))
                    .scaleEffect(1 - phase * 0.5)
            }

            // Supurayotgan belgi.
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .rotationEffect(.degrees(sin(t * 5) * 9), anchor: .bottom)
                .scaleEffect(1 + sin(t * 2.5) * 0.03)
                .shadow(color: color.opacity(0.35), radius: 10, y: 5)
        }
    }
}

// MARK: - Natija animatsiyasi

/// Bir marta "paydo bo'ldi" holatini saqlaydi (@State bu yerda ishlatilmaydi).
final class AppearFlag: ObservableObject {
    @Published var shown = false
}

/// Natija belgisi: yashil doira prujina bilan kattalashadi, atrofida to'lqin tarqaladi.
struct SuccessBadge: View {
    var success = true
    var size: CGFloat = 64
    @StateObject private var flag = AppearFlag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color: Color = success ? .green : .yellow
        ZStack {
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 3)
                .scaleEffect(flag.shown ? 1.7 : 0.8)
                .opacity(flag.shown ? 0 : 0.9)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.1), value: flag.shown)
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: size))
                .foregroundStyle(color)
                .scaleEffect(flag.shown ? 1 : 0.3)
                .rotationEffect(.degrees(flag.shown ? 0 : -30))
                .opacity(flag.shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55), value: flag.shown)
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .onAppear { flag.shown = true }
    }
}

/// Bo'shatilgan hajm noldan sanalib chiqadi.
struct CountingBytes: View {
    let bytes: Int64
    let format: (String) -> String
    @StateObject private var flag = AppearFlag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CountingBytesText(value: flag.shown || reduceMotion ? Double(bytes) : 0, format: format)
            .animation(.easeOut(duration: 0.9).delay(0.15), value: flag.shown)
            .onAppear { flag.shown = true }
    }
}

private struct CountingBytesText: View, Animatable {
    var value: Double
    let format: (String) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(Int64(value).bytes)).monospacedDigit()
    }
}

/// Tozalash juda tez tugasa ham animatsiya ko'z ilg'amay yo'qolib qolmasin.
enum AnimationPacing {
    static func holdUntilVisible(since start: Date, minimum: TimeInterval = 1.4) async {
        let left = minimum - Date().timeIntervalSince(start)
        if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
    }
}
