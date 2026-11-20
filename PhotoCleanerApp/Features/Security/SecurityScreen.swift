import SwiftUI
import CryptoKit
import LocalAuthentication

/// Fixture selection is inert in release because FidelityPreview.active is DEBUG-only.
private var securityFixture: String { FidelityPreview.active ? FidelityPreview.name : "" }

private struct SecurityGlyph: View {
    let name: String
    var body: some View {
        if let asset = ["envelope": "SecurityEmailIcon", "key.horizontal": "SecurityPasswordIcon", "iphone": "SecurityDeviceIcon", "exclamationmark.shield": "SecurityIssueIcon"][name] {
            Image(asset).resizable().scaledToFit().frame(width: 40, height: 40)
        } else {
            Image(systemName: name).font(.system(size: 24)).foregroundStyle(Color(hex: 0x4777AF)).frame(width: 40, height: 40).background(Color(hex: 0xECF2FA), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct SecurityFeatureCard: View {
    let title: String
    let message: String
    let symbol: String
    var titleColor = Palette.ink
    var titleMinHeight: CGFloat = 24
    var messageMinHeight: CGFloat = 48
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecurityGlyph(name: symbol)
                Text(title).font(Palette.font(16, .semibold)).foregroundStyle(titleColor).frame(maxWidth: .infinity, minHeight: titleMinHeight, alignment: .leading)
            }
            Text(message).cleanerBodyLineHeight().foregroundStyle(Palette.secondary).frame(minHeight: messageMinHeight, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct SecurityBadge: View {
    let value: String
    private var ink: Color { value == "OK" ? Color(hex: 0x1F6546) : value == "Issues found" ? Color(hex: 0x9D3740) : Palette.secondary }
    private var fill: Color { value == "OK" ? Color(hex: 0xE2F4E9) : value == "Issues found" ? Color(hex: 0xFBE9E8) : Palette.track }
    var body: some View { Text(value).font(Palette.font(16, .semibold)).foregroundStyle(ink).padding(.horizontal, 8).frame(minHeight: 24).background(fill, in: RoundedRectangle(cornerRadius: 8)) }
}
struct SecurityScreen: View {
    @AppStorage("security.email.status") private var emailStatus = "Not checked"
    @AppStorage("security.password.status") private var passwordStatus = "Not checked"
    @AppStorage("security.device.status") private var deviceStatus = "Not checked"
    var body: some View {
        PageShell(title: "Security Center") {
            HStack(spacing: 8) {
                Image("SecurityCenter").resizable().scaledToFit().frame(width: 64, height: 64)
                Text("Check your security").font(Palette.font(24, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).frame(minHeight: 104).background(Color(hex: 0xE6EFFB), in: RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 8) {
                ForEach(RemoteConfiguration.shared.value.securityModules, id: \.self) { item in
                    switch item {
                    case .emailLeakage:
                        NavigationLink { EmailCheckScreen() } label: { module("Email Leakage", "Check for reported breaches.", "envelope", FidelityPreview.active ? (securityFixture.contains("hubReviewed") ? "Issues found" : "Not checked") : emailStatus) }
                    case .passwordCheck:
                        NavigationLink { PasswordCheckScreen() } label: { module("Password Check", "Check strength and known leaks.", "key.horizontal", FidelityPreview.active ? (securityFixture.contains("hubReviewed") ? "OK" : "Not checked") : passwordStatus) }
                    case .deviceSecurity:
                        NavigationLink { DeviceSecurityScreen() } label: { module("Device Security", "Review your iPhone settings.", "iphone", FidelityPreview.active ? "Not checked" : deviceStatus) }
                    }
                }
            }
        }.buttonStyle(.plain)
    }
    private func module(_ title: String, _ message: String, _ symbol: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecurityGlyph(name: symbol)
                Text(title).font(Palette.font(16, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Disclosure()
            }
            Text(message).foregroundStyle(Palette.secondary).frame(minHeight: 24)
            SecurityBadge(value: status)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Palette.ink)
    }
}

private enum EmailCheckPhase { case entry, checking, clear, leaks, unavailable }
private struct EmailCheckingArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    private var angle: Double { FidelityPreview.active ? (FidelityPreview.frameID?.hasPrefix("152:") == true ? 160 : 0) : (rotating ? 360 : 0) }
    var body: some View {
        ZStack {
            Image("EmailChecking").resizable().scaledToFit().frame(width: 328, height: 344)
            Circle().stroke(.white, lineWidth: 20).frame(width: 176, height: 176).offset(y: 4)
            Image("EmailSpinner").resizable().scaledToFit().frame(width: 200, height: 200).rotationEffect(.degrees(angle))
                .animation(FidelityPreview.active || reduceMotion ? nil : .linear(duration: 1.2).repeatForever(autoreverses: false), value: rotating).offset(y: 4)
        }.frame(width: 328, height: 344).onAppear { if !FidelityPreview.active && !reduceMotion { rotating = true } }
    }
}
struct EmailCheckScreen: View {
    @AppStorage("security.email.status") private var hubStatus = "Not checked"
    @State private var email = ""
    @State private var phase = EmailCheckPhase.entry
    @State private var breaches: [EmailBreach] = []
    @State private var checkTask: Task<Void, Never>?
    private var valid: Bool { email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    var body: some View {
        ToolsPage(title: "Email Leakage", centered: phase == .checking, footerVisible: phase != .checking) {
            switch phase {
            case .entry:
                SecurityFeatureCard(title: "Check an email address", message: "See whether this address appears in reported data breaches.", symbol: "envelope")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email address").font(Palette.font(16, .semibold)).frame(minHeight: 24)
                    TextField("", text: $email)
                        .overlay(alignment: .leading) { if email.isEmpty { Text(verbatim: "name@example.com").foregroundStyle(Palette.secondary).allowsHitTesting(false).accessibilityHidden(true) } }
                        .accessibilityLabel("Email address").textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).frame(minHeight: 56).background(!email.isEmpty && !valid ? Color(hex: 0xFFF0EF) : .white, in: RoundedRectangle(cornerRadius: 16))
                }
                if !email.isEmpty && !valid { Text("Enter a valid email address.").foregroundStyle(Color(hex: 0x9D3740)) }
            case .checking:
                VStack(spacing: 24) {
                    EmailCheckingArtwork()
                    VStack(spacing: 0) { Text("Checking email…").font(Palette.font(16, .semibold)); Text(email).foregroundStyle(Palette.secondary) }
                }.frame(maxWidth: .infinity)
            case .clear, .leaks:
                VStack(alignment: .leading, spacing: 8) {
                    Image(phase == .clear ? "SecurityClearIcon" : "SecurityIssueIcon").resizable().scaledToFit().frame(width: 40, height: 40)
                    Text(phase == .clear ? "No leaks found" : "\(breaches.count) leaks found").font(Palette.font(24, .semibold)).frame(minHeight: 32)
                    Text(email).foregroundStyle(Palette.secondary).frame(minHeight: 24)
                    if phase == .clear { Text("This email did not appear in the records checked.").cleanerBodyLineHeight().foregroundStyle(Palette.secondary).frame(minHeight: 48).fixedSize(horizontal: false, vertical: true) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                ForEach(breaches) { item in
                    HStack(alignment: .top, spacing: 12) {
                        if let logoUrl = item.logo_url, !logoUrl.isEmpty {
                            RemoteImage(urlString: logoUrl, cornerRadius: 8, contentMode: .fit)
                                .frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.displayTitle).font(Palette.font(16, .semibold))
                                Spacer()
                                if let risk = item.risk {
                                    Text(risk.uppercased())
                                        .font(Palette.font(11, .semibold))
                                        .foregroundStyle(risk == "high" ? Color(hex: 0x9D3740) : Color(hex: 0xBF761B))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(risk == "high" ? Color(hex: 0xFBE9E8) : Color(hex: 0xFEF3E6), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            if !item.displayDate.isEmpty {
                                Text(item.displayDate).font(Palette.font(13)).foregroundStyle(Palette.secondary)
                            }
                            if !item.displayFields.isEmpty {
                                Text(item.displayFields).font(Palette.font(13)).foregroundStyle(Palette.ink.opacity(0.8))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            case .unavailable:
                SecurityFeatureCard(title: "Check unavailable", message: "Try again when the connection is available.", symbol: "envelope")
            }
        } footer: {
            switch phase {
            case .entry: PrimaryButton(title: "Check", disabled: !valid, disabledFill: Color(hex: 0xE0E7F0)) { startCheck() }
            case .clear, .leaks: PrimaryButton(title: "Check another email") { email = ""; breaches = []; phase = .entry }
            case .unavailable: PrimaryButton(title: "Retry") { phase = .entry }
            case .checking: EmptyView()
            }
        }.onChange(of: phase) { _, newPhase in
            guard !FidelityPreview.active else { return }
            if newPhase == .clear { hubStatus = "OK" }
            if newPhase == .leaks { hubStatus = "Issues found" }
        }.onAppear(perform: loadFixture).onDisappear { checkTask?.cancel() }
    }
    private func startCheck() {
        guard valid, !FidelityPreview.active else { return }
        let candidate = email
        phase = .checking
        checkTask?.cancel()
        checkTask = Task {
            do {
                let result = try await Courier.shared.checkEmail(candidate)
                guard !Task.isCancelled else { return }
                breaches = result.breaches
                phase = breaches.isEmpty ? .clear : .leaks
            } catch {
                guard !Task.isCancelled else { return }
                phase = .unavailable
            }
        }
    }
    private func loadFixture() {
        guard FidelityPreview.active else { return }
        let name = securityFixture
        email = name.contains("Risk") || name.contains("checkingLeak") || name.hasSuffix("/ leaks") ? "maya@example.com" : "alex@example.com"
        if name.contains("emailEmpty") { email = "" }
        if name.contains("emailInvalid") { email = "alex@" }
        if name.contains("checking") { phase = .checking }
        if name.contains("noLeaks") { phase = .clear }
        if name.hasSuffix("/ leaks") {
            phase = .leaks
            breaches = [
                EmailBreach(name: "Northline Forum", title: "Northline Forum", domain: nil, breach_date: "2024-03-18", added_date: nil, modified_date: nil, pwn_count: nil, description_html: nil, logo_url: nil, data_classes: ["Email address, username"], data_class_keys: nil, is_verified: true, is_sensitive: false, risk: "high", source: "hibp"),
                EmailBreach(name: "Juniper Club", title: "Juniper Club", domain: nil, breach_date: "2023-09-06", added_date: nil, modified_date: nil, pwn_count: nil, description_html: nil, logo_url: nil, data_classes: ["Email address, phone number"], data_class_keys: nil, is_verified: true, is_sensitive: false, risk: "medium", source: "hibp")
            ]
        }
        if name.contains("emailUnavailable") { phase = .unavailable }
    }
}

struct PasswordCheckScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("security.password.status") private var hubStatus = "Not checked"
    @State private var password = ""
    @State private var checking = false
    @State private var result: String?
    @State private var leaked = false
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @FocusState private var passwordFocused: Bool
    private var score: Int {
        if FidelityPreview.active { return securityFixture.contains("Weak") ? 0 : securityFixture.contains("Medium") ? 1 : 2 }
        let classes = [password.rangeOfCharacter(from: .lowercaseLetters) != nil, password.rangeOfCharacter(from: .uppercaseLetters) != nil, password.rangeOfCharacter(from: .decimalDigits) != nil, password.rangeOfCharacter(from: .symbols.union(.punctuationCharacters)) != nil].filter { $0 }.count
        return password.count >= 16 && classes >= 3 ? 2 : password.count >= 10 && classes >= 2 ? 1 : 0
    }
    private var strengthColor: Color { [Color(hex: 0xBA354A), Color(hex: 0xBF761B), Color(hex: 0x1CB450)][score] }
    var body: some View {
        ToolsPage(title: "Password Check", footerVisible: result != nil) {
            SecurityFeatureCard(title: "Check a password", message: "Review its strength and whether it appears in known leaks.", symbol: "key.horizontal")
            VStack(alignment: .leading, spacing: 8) {
                Text("Password").font(Palette.font(16, .semibold)).frame(minHeight: 24)
                SecureField("", text: $password)
                    .overlay(alignment: .leading) { if password.isEmpty { Text(verbatim: "Enter a password").foregroundStyle(Palette.secondary).allowsHitTesting(false).accessibilityHidden(true) } }
                    .accessibilityLabel("Password")
                    .accessibilityHint("Submit to check known leaks with Have I Been Pwned. Only the first 5 characters of a SHA-1 hash are sent; the password stays on your device.")
                    .focused($passwordFocused).submitLabel(.search).onSubmit(startCheck)
                    .textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).frame(minHeight: 56).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Strength"); Spacer(); Text(password.isEmpty ? "—" : ["Weak", "Medium", "Strong"][score]).foregroundStyle(Palette.blue) }.font(Palette.font(16, .semibold)).frame(minHeight: 24)
                HStack(spacing: 8) { ForEach(0..<3) { index in Capsule().fill(!password.isEmpty && index <= score ? strengthColor : Color(hex: 0xDFE6F0)).frame(height: 8) } }
                Text(password.isEmpty ? "Enter a password to see its strength." : ["Use a longer phrase with several unrelated words.", "Make it longer and avoid predictable substitutions.", "Keep this password unique to one account."][score]).cleanerBodyLineHeight().foregroundStyle(Palette.secondary).frame(minHeight: password.isEmpty ? 24 : 48, alignment: .topLeading)
            }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
            if let result {
                if leaked { SecurityFeatureCard(title: "Found in leaks", message: "Choose a new password before using this one.", symbol: "exclamationmark.shield", titleColor: Color(hex: 0x9D3740)) }
                else { Text(result).foregroundStyle(Palette.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
            }
            if checking { ProgressView("Checking…") }
        } footer: {
            if result != nil { PrimaryButton(title: "Done") { dismiss() } }
        }.onChange(of: password) { _, newPassword in
            if !FidelityPreview.active {
                requestID = UUID()
                task?.cancel()
                checking = false
                result = nil
                leaked = false
                guard !newPassword.isEmpty else { return }
                let id = UUID()
                requestID = id
                task = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, id == requestID else { return }
                    await check(newPassword, id: id)
                }
            }
        }
            .onDisappear { requestID = UUID(); task?.cancel(); password = "" }
            .onAppear {
                guard FidelityPreview.active else { return }
                password = securityFixture.contains("Empty") ? "" : String(repeating: "x", count: securityFixture.contains("Weak") ? 4 : securityFixture.contains("Medium") ? 8 : 12)
                if !password.isEmpty { result = "No match in checked leaks"; leaked = securityFixture.contains("pwdLeaks") }
            }
    }
    private func startCheck() {
        guard !password.isEmpty, !checking, !FidelityPreview.active else { return }
        passwordFocused = false
        checking = true
        let candidate = password
        let id = UUID(); requestID = id
        task = Task { await check(candidate, id: id) }
    }
    private func check(_ candidate: String, id: UUID) async {
        checking = true; result = nil; leaked = false
        defer { if id == requestID { checking = false } }
        let digest = Insecure.SHA1.hash(data: Data(candidate.utf8)).map { String(format: "%02X", $0) }.joined()
        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(digest.prefix(5))") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        do {
            let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { try await session.data(for: request) }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let body = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
            let suffix = String(digest.dropFirst(5)); var matches = 0; var validLines = 0
            for line in body.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":")
                guard parts.count == 2, parts[0].count == 35, let count = Int(parts[1]) else { continue }
                validLines += 1; if parts[0] == suffix { matches = count }
            }
            guard validLines > 0 else { throw URLError(.cannotParseResponse) }
            guard id == requestID, candidate == password else { return }
            leaked = matches > 0; hubStatus = matches > 0 ? "Issues found" : "OK"
            result = matches > 0 ? "Found in known leaks \(matches) times." : "No match in checked leaks"
        } catch is CancellationError { } catch { if !Task.isCancelled && id == requestID { result = "Check unavailable. Try again when you have a connection." } }
    }
}

struct DeviceSecurityScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("security.device.status") private var hubStatus = "Not checked"
    @AppStorage("security.review.updates") private var updates = "Not checked"
    @AppStorage("security.review.passcode") private var passcode = "Not checked"
    @AppStorage("security.review.2fa") private var twoFactor = "Not checked"
    @State private var guide: Int?
    @State private var review = false
    @State private var fixtureStatuses: [String]?
    private let titles = ["Keep iOS up to date", "Turn on a device passcode", "Enable Apple ID two-factor authentication"]
    private let paths = ["General → Software Update", "Face ID & Passcode", "Apple Account → Sign-In & Security"]
    var body: some View {
        ToolsPage(title: "Device Security", footerVisible: !review) {
            if let guide {
                SecurityFeatureCard(title: ["iOS updates", "Device passcode", "Apple ID two-factor authentication"][guide], message: "In iPhone Settings, open:", symbol: "iphone", titleMinHeight: guide == 2 ? 48 : 24, messageMinHeight: 24)
                Text(paths[guide]).font(Palette.font(16, .semibold)).frame(minHeight: 24).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
            } else if review {
                SecurityFeatureCard(title: "Review your settings", message: "Choose the result after checking the recommendations on your iPhone.", symbol: "iphone")
                PrimaryButton(title: "Everything is set") { record("OK") }
                PrimaryButton(title: "Needs attention") { record("Issues found") }
            } else {
                ForEach(0..<3) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(titles[index]).font(Palette.font(16, .semibold))
                        SecurityBadge(value: (fixtureStatuses ?? [updates, passcode, twoFactor])[index])
                        Text(paths[index]).foregroundStyle(Palette.secondary)
                        Button("Open Settings") { guide = index }.font(Palette.font(16, .semibold)).foregroundStyle(Palette.blue).frame(minHeight: 32)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        } footer: {
            if guide != nil { PrimaryButton(title: "Back to checklist") { guide = nil } }
            else if !review {
                let needsReview: Bool = {
                    if FidelityPreview.active {
                        return (fixtureStatuses ?? [updates, passcode, twoFactor]).allSatisfy { $0 == "Not checked" } || securityFixture.contains("deviceStart")
                    }
                    return twoFactor == "Not checked" || hubStatus == "Not checked"
                }()
                PrimaryButton(title: needsReview ? "Review checklist" : "Done") {
                    if needsReview { review = true } else { dismiss() }
                }
            }
        }.onAppear {
            if FidelityPreview.active {
                if securityFixture.contains("deviceMixed") { fixtureStatuses = ["Issues found", "OK", "Not checked"] }
                else { fixtureStatuses = Array(repeating: securityFixture.contains("deviceOK") ? "OK" : "Not checked", count: 3) }
                review = securityFixture.hasSuffix("/ review")
                for index in 0..<3 where securityFixture.contains("guide\(index)") { guide = index }
            } else {
                let current = ProcessInfo.processInfo.operatingSystemVersion
                let currentVersion = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
                let minimum = UserDefaults.standard.string(forKey: "security.minimumIOSVersion") ?? RemoteConfiguration.shared.value.latestIOSVersion
                updates = compareVersion(currentVersion, minimum) >= 0 ? "OK" : "Issues found"
                let context = LAContext(); var error: NSError?
                passcode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) ? "OK" : "Issues found"
            }
        }
    }
    private func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) { let a = index < left.count ? left[index] : 0; let b = index < right.count ? right[index] : 0; if a != b { return a < b ? -1 : 1 } }
        return 0
    }
    private func record(_ value: String) {
        if FidelityPreview.active {
            fixtureStatuses = Array(repeating: value, count: 3)
        } else {
            twoFactor = value
            if value == "Issues found" {
                hubStatus = "Issues found"
            } else {
                hubStatus = (updates == "OK" && passcode == "OK") ? "OK" : "Issues found"
            }
        }
        review = false
    }
}

/// Routes fidelity arguments to the same views used by real navigation.
struct ToolsFidelityScreen: View {
    var body: some View {
        let name = FidelityPreview.name
        if name == "Overlay · Access off" { Color.white.overlay { NoticeView(title: "Photos access is off", message: "Allow Cleaner to add photos in Settings to save your image.", asset: "", primaryTitle: "Back to editor", onPrimary: {}) } }
        else if name == "Overlay · Photo saved" { Color.white.overlay { NoticeView(title: "Photo saved", message: "Added to your photo library.", asset: "PhotoSaved", onPrimary: {}) } }
        else if name.contains("Splash") { SplashScreen() }
        else if name.contains("My subscription") { SubscriptionScreen() }
        else if FidelityPreview.section == "Settings" { SettingsScreen() }
        else if FidelityPreview.section == "Security Center" {
            if name.contains("/ hub") { SecurityScreen() }
            else if name.contains("/ pwd") { PasswordCheckScreen() }
            else if name.contains("device") || name.contains("guide") || name.hasSuffix("/ review") { DeviceSecurityScreen() }
            else { EmailCheckScreen() }
        } else { BackgroundRemoverScreen() }
    }
}

/// Fixed navigation and bottom action; scroll body grows naturally for long text.
/// Centered processing uses available viewport height, never device-specific offsets.
struct ToolsPage<Content: View, Footer: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    var centered = false
    var footerVisible = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: title)
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16, content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: centered ? max(0, geometry.size.height - 32) : nil, alignment: centered ? .center : .topLeading)
                        .padding(16)
                }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) { if footerVisible { footer().padding(16).background(dynamicType.isAccessibilitySize ? Palette.bg : .clear) } }
            .background(LinearGradient(stops: [.init(color: Palette.bg, location: 0.78), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .font(Palette.font(16)).foregroundStyle(Palette.ink).toolbar(.hidden, for: .navigationBar)
    }
}
