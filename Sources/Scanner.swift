import AppKit

/// Diskni ko'rib chiqadi. Hech narsa o'chirmaydi — faqat ro'yxat va hajm qaytaradi.
enum Scanner {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser

    static func lib(_ path: String) -> URL {
        home.appendingPathComponent("Library").appendingPathComponent(path)
    }

    /// Qayta yaratiladigan dasturchi keshlari (foydali ma'lumotlar emas).
    static var devCacheDirs: [(path: String, title: String)] { [
        (".npm/_cacache", L("npm keshi", "npm cache", "Кэш npm")),
        (".cache/uv", L("uv (Python) keshi", "uv (Python) cache", "Кэш uv (Python)")),
        (".cache/pip", L("pip keshi", "pip cache", "Кэш pip")),
        (".yarn/berry/cache", L("Yarn keshi", "Yarn cache", "Кэш Yarn")),
        ("Library/pnpm/store", L("pnpm ombori", "pnpm store", "Хранилище pnpm")),
        (".gradle/caches", L("Gradle keshi", "Gradle cache", "Кэш Gradle")),
        (".cargo/registry/cache", L("Cargo keshi", "Cargo cache", "Кэш Cargo")),
        ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
        ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode iOS DeviceSupport"),
        ("Library/Developer/CoreSimulator/Caches", L("Simulator keshi", "Simulator cache", "Кэш симулятора")),
        (".gradle/wrapper/dists", L("Gradle eski versiyalari", "Old Gradle versions", "Старые версии Gradle")),
        (".android/cache", L("Android SDK keshi", "Android SDK cache", "Кэш Android SDK")),
        (".cargo/registry/src", L("Cargo manba nusxalari", "Cargo extracted sources", "Распакованные исходники Cargo")),
        (".rustup/downloads", L("Rustup yuklanmalari", "Rustup downloads", "Загрузки Rustup")),
        (".bun/install/cache", L("Bun keshi", "Bun cache", "Кэш Bun")),
        (".conda/pkgs", L("Conda paketlar keshi", "Conda package cache", "Кэш пакетов Conda")),
        ("miniconda3/pkgs", L("Miniconda paketlar keshi", "Miniconda package cache", "Кэш пакетов Miniconda")),
        ("anaconda3/pkgs", L("Anaconda paketlar keshi", "Anaconda package cache", "Кэш пакетов Anaconda")),
        (".cache/pre-commit", L("pre-commit keshi", "pre-commit cache", "Кэш pre-commit")),
        (".cache/node-gyp", L("node-gyp keshi", "node-gyp cache", "Кэш node-gyp")),
    ] }

    static func scan(_ category: Category) -> [CleanItem] {
        let items: [CleanItem]
        switch category {
        case .appCaches:
            items = children(of: lib("Caches")).map { item($0, name: appName(forBundleFolder: $0)) }
        case .logs:
            items = children(of: lib("Logs")).map { item($0, name: appName(forBundleFolder: $0)) }
        case .devCaches:
            items = devCacheDirs.compactMap { entry in
                let url = home.appendingPathComponent(entry.path)
                return fm.fileExists(atPath: url.path) ? item(url, name: entry.title) : nil
            } + homebrewLeftovers() + unavailableSimulators()
        case .installers:
            items = installerFiles()
        case .leftovers:
            items = Leftovers.find()
        case .trash:
            items = children(of: home.appendingPathComponent(".Trash")).map { item($0, selected: false) }
        }
        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    /// `brew cleanup` o'chiradigan eski versiyalar. ~/Library/Caches ichidagilar «Ilovalar keshi»da allaqachon bor.
    static func homebrewLeftovers() -> [CleanItem] {
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fm.isExecutableFile) else { return [] }
        let out = Shell.run(brew, ["cleanup", "-n"]).output
        let caches = lib("Caches").path
        return out.split(separator: "\n").compactMap { line -> CleanItem? in
            guard line.hasPrefix("Would remove: ") else { return nil }
            var path = String(line.dropFirst("Would remove: ".count))
            if let paren = path.range(of: " (", options: .backwards) { path = String(path[..<paren.lowerBound]) }
            guard path.hasPrefix("/"), !path.hasPrefix(caches), fm.fileExists(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = url.deletingLastPathComponent().lastPathComponent + " " + url.lastPathComponent
            return item(url, name: "Homebrew: " + name)
        }
    }

    /// Xcode endi qo'llamaydigan iOS versiyalari uchun qolgan simulyatorlar.
    static func unavailableSimulators() -> [CleanItem] {
        let devices = lib("Developer/CoreSimulator/Devices")
        guard fm.fileExists(atPath: devices.path) else { return [] }
        let out = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"]).output
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: [[String: Any]]]
        else { return [] }
        return byRuntime.values.joined().compactMap { device -> CleanItem? in
            guard let udid = device["udid"] as? String else { return nil }
            let url = devices.appendingPathComponent(udid)
            guard fm.fileExists(atPath: url.path) else { return nil }
            let name = device["name"] as? String ?? udid
            return item(url, name: L("Eski simulyator: ", "Old simulator: ", "Старый симулятор: ") + name)
        }
    }

    /// Foydalanuvchi papkalaridagi .dmg/.pkg fayllari. Ikki haftadan eskilari oldindan tanlanadi.
    static func installerFiles() -> [CleanItem] {
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        var found: [CleanItem] = []

        for dir in ["Downloads", "Desktop", "Documents"] {
            let walker = fm.enumerator(
                at: home.appendingPathComponent(dir),
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = walker?.nextObject() as? URL {
                if (walker?.level ?? 0) > 3 { walker?.skipDescendants(); continue }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                found.append(CleanItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    detail: tildePath(url.deletingLastPathComponent()) + " · " + ago(date),
                    urls: [url],
                    size: size(of: url),
                    selected: date < cutoff
                ))
            }
        }
        return found
    }

    /// "3 oy oldin" kabi nisbiy sana.
    static func ago(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Savatni o'qish uchun «To'liq disk ruxsati» kerak.
    static func trashAccessible() -> Bool {
        (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent(".Trash").path)) != nil
    }

    /// iCloud'da turgan, Mac'ga yuklanmagan fayl (Finder'da bulut belgisi bilan).
    /// Uni o'qish faylni yuklab olishni boshlab, o'qishni uzoq to'xtatib qo'yadi — Mac'da joy ham egallamaydi.
    static func isCloudOnly(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    static func children(of dir: URL) -> [URL] {
        let kids = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return kids.filter { $0.lastPathComponent != ".DS_Store" }
    }

    static func item(_ url: URL, name: String? = nil, selected: Bool = true) -> CleanItem {
        CleanItem(
            id: url.path,
            name: name ?? url.lastPathComponent,
            detail: tildePath(url),
            urls: [url],
            size: size(of: url),
            selected: selected
        )
    }

    /// "com.google.Chrome" papkasini "Google Chrome" deb ko'rsatadi.
    static func appName(forBundleFolder url: URL) -> String {
        let name = url.lastPathComponent
        guard name.contains("."),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
        else { return name }
        return app.deletingPathExtension().lastPathComponent
    }

    static func tildePath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.path, with: "~", options: .anchored)
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func fileSize(_ v: URLResourceValues) -> Int64 {
            Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isRegularFile == true { return fileSize(values) }

        var total: Int64 = 0
        let walker = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) { _, _ in true }
        while let file = walker?.nextObject() as? URL {
            if let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += fileSize(v)
            }
        }
        return total
    }

    static func size(of urls: [URL]) -> Int64 {
        urls.reduce(0) { $0 + size(of: $1) }
    }
}

/// O'rnatilgan ilovalar ro'yxatini tuzib, egasi topilmagan papka va sozlamalarni aniqlaydi.
enum Leftovers {
    private struct Installed {
        var ids: Set<String> = []
        var names: Set<String> = []
        var vendors: Set<String> = []

        mutating func addID(_ id: String) {
            let id = id.lowercased()
            ids.insert(id)
            let parts = id.split(separator: ".")
            if parts.count >= 2 { vendors.insert(parts.prefix(2).joined(separator: ".")) }
        }

        func hasName(_ n: String) -> Bool {
            names.contains { $0.contains(n) || ($0.count >= 4 && n.contains($0)) }
        }
    }

    private enum Verdict { case sure, review }

    private static let fm = FileManager.default
    private static let home = Scanner.home

    private static let scanDirs = [
        "Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit", "Cookies",
    ]

    private static let domains: Set<String> = [
        "com", "org", "net", "io", "de", "ru", "uz", "co", "app", "me", "dev", "us", "jp", "cn", "fr", "uk",
        "ch", "se", "nl", "eu", "info", "tv", "ai", "it", "pl", "kr", "at", "ca", "au", "in", "be", "dk", "fi",
        "no", "es", "br", "cz", "hu", "ua", "by", "kz", "tr",
    ]

    /// macOS'ning o'zi yaratadigan, ilovaga tegishli bo'lmagan nomlar.
    private static let systemNames: Set<String> = [
        "crashreporter", "syncservices", "animoji", "cef", "knowledge", "addressbook", "callhistorydb",
        "callhistorytransactions", "clouddocs", "differentialprivacy", "fileprovider", "mobilesync", "icloud",
        "accounts", "familycircle", "contextstoreagent", "mobilemeaccounts", "quicklook", "ubiquity",
        "spotlight", "keychains", "screentime", "cloudkit", "assistant", "diagnostics", "controlcenter",
        "notifications", "colorsync", "dictionary", "fontregistry", "audio", "preferencepanes", "geoservices",
        "passkit", "sharedimagecache", "defaultstore", "byhost", "farrosh",
    ]

    /// Tizim yoki ko'p ilovalar umumiy ishlatadigan kutubxonalar — ular hech qachon qoldiq emas.
    private static let sharedVendors = [
        "org.cups", "com.qtproject", "org.python", "org.sparkle-project", "org.chromium", "org.mozilla",
        "org.webkit", "com.google.keystone", "com.microsoft.autoupdate", "com.microsoft.shared",
    ]

    static func find() -> [CleanItem] {
        let installed = collectInstalled()
        var groups: [String: (name: String, urls: [URL], sure: Bool)] = [:]

        for dir in scanDirs {
            for url in Scanner.children(of: Scanner.lib(dir)) {
                guard let hit = classify(url.lastPathComponent, installed) else { continue }
                var group = groups[hit.key] ?? (hit.name, [], false)
                group.urls.append(url)
                group.sure = group.sure || hit.verdict == .sure
                if hit.isPlainName { group.name = hit.name }
                groups[hit.key] = group
            }
        }

        return groups.map { key, group in
            let places = Set(group.urls.map { $0.deletingLastPathComponent().lastPathComponent }).sorted()
            // Faqat bitta sozlama fayli ishonchli dalil emas — kamida ikki joyda iz qolgan bo'lishi kerak.
            let sure = group.sure && places.count >= 2
            let detail = group.urls.count == 1
                ? Scanner.tildePath(group.urls[0])
                : L("\(group.urls.count) ta joyda · ", "\(group.urls.count) places · ", "Мест: \(group.urls.count) · ") + places.joined(separator: ", ")
            return CleanItem(
                id: "leftover:" + key,
                name: group.name,
                detail: detail,
                urls: group.urls,
                size: Scanner.size(of: group.urls),
                selected: sure,
                needsReview: !sure
            )
        }
    }

    private static func classify(
        _ raw: String, _ inst: Installed
    ) -> (key: String, name: String, verdict: Verdict, isPlainName: Bool)? {
        var s = raw
        for ext in [".plist", ".savedState", ".binarycookies"] where s.hasSuffix(ext) {
            s.removeLast(ext.count)
        }
        if s.hasPrefix(".") { return nil }
        // "8DKG4XB37M.group.com.vendor.app" kabi nomlardan jamoa ID va "group." qismini olib tashlaydi.
        if let team = s.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { s.removeSubrange(team) }
        if s.hasPrefix("group.") { s.removeFirst(6) }

        let lower = s.lowercased()
        if lower.hasPrefix("com.apple") || lower.hasPrefix("apple") || lower.hasPrefix("uz.farrosh") { return nil }
        if sharedVendors.contains(where: { lower.hasPrefix($0) }) { return nil }
        if systemNames.contains(normalize(s)) { return nil }

        let parts = s.split(separator: ".").map(String.init)
        if parts.count >= 2, domains.contains(parts[0].lowercased()) {
            if inst.ids.contains(where: { lower.hasPrefix($0) || $0.hasPrefix(lower) }) { return nil }
            let products = parts.dropFirst(2).map(normalize).filter { $0.count >= 4 }
            if products.contains(where: inst.hasName) { return nil }

            let vendor = parts.prefix(2).joined(separator: ".").lowercased()
            if inst.vendors.contains(vendor) {
                // Bu ishlab chiqaruvchining boshqa ilovasi o'rnatilgan — ehtimol yordamchi xizmat.
                let product = parts.count >= 3 ? parts[2] : parts[1]
                return (normalize(product), product, .review, false)
            }
            return (normalize(parts[1]), parts[1].capitalized, .sure, false)
        }

        // Kichik harfli nomlar odatda tizim xizmatlari (masalan, "networkserviceproxy").
        guard s.rangeOfCharacter(from: .uppercaseLetters) != nil else { return nil }
        let n = normalize(s)
        guard n.count >= 3, !inst.hasName(n) else { return nil }
        if inst.ids.contains(where: { $0.split(separator: ".").map { normalize(String($0)) }.contains(n) }) {
            return nil
        }
        return (n, s, .review, true)
    }

    private static func collectInstalled() -> Installed {
        var inst = Installed()
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices", home.path + "/Applications"]
        for root in roots { collectApps(in: URL(fileURLWithPath: root), depth: 0, into: &inst) }

        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { inst.addID(id) }
            if let name = app.localizedName { inst.names.insert(normalize(name)) }
        }
        // Fon xizmatlari ham o'rnatilgan dastur borligini bildiradi.
        let agentDirs = [home.path + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
        for dir in agentDirs {
            for url in Scanner.children(of: URL(fileURLWithPath: dir)) where url.pathExtension == "plist" {
                inst.addID(url.deletingPathExtension().lastPathComponent)
            }
        }
        return inst
    }

    private static func collectApps(in dir: URL, depth: Int, into inst: inout Installed) {
        guard depth < 4,
              let kids = try? fm.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }

        for url in kids {
            if url.pathExtension == "app" {
                register(url, into: &inst)
                for sub in ["Contents/Library/LoginItems", "Contents/Applications", "Contents/Helpers"] {
                    collectApps(in: url.appendingPathComponent(sub), depth: depth + 1, into: &inst)
                }
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // "Adobe Illustrator 2026" kabi papkalar nomi ham hisobga olinadi.
                inst.names.insert(normalize(url.lastPathComponent))
                collectApps(in: url, depth: depth + 1, into: &inst)
            }
        }
    }

    private static func register(_ app: URL, into inst: inout Installed) {
        inst.names.insert(normalize(app.deletingPathExtension().lastPathComponent))
        guard let bundle = Bundle(url: app) else { return }
        if let id = bundle.bundleIdentifier { inst.addID(id) }
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String { inst.names.insert(normalize(value)) }
        }
    }

    private static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
