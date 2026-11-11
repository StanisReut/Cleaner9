import SwiftUI
import CryptoKit

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
    var titleColor = CleanerStyle.ink
    var titleMinHeight: CGFloat = 24
    var messageMinHeight: CGFloat = 48
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecurityGlyph(name: symbol)
                Text(title).font(CleanerStyle.font(16, .semibold)).foregroundStyle(titleColor).frame(maxWidth: .infinity, minHeight: titleMinHeight, alignment: .leading)
            }
            Text(message).foregroundStyle(CleanerStyle.secondary).frame(minHeight: messageMinHeight, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct SecurityBadge: View {
    let value: String
    private var ink: Color { value == "OK" ? Color(hex: 0x1F6546) : value == "Issues found" ? Color(hex: 0x9D3740) : CleanerStyle.secondary }
    private var fill: Color { value == "OK" ? Color(hex: 0xE2F4E9) : value == "Issues found" ? Color(hex: 0xFBE9E8) : CleanerStyle.track }
    var body: some View { Text(value).font(CleanerStyle.font(16, .semibold)).foregroundStyle(ink).padding(.horizontal, 8).frame(minHeight: 24).background(fill, in: RoundedRectangle(cornerRadius: 8)) }
}
struct SecurityScreen: View {
    @AppStorage("security.email.status") private var emailStatus = "Not checked"
    @AppStorage("security.password.status") private var passwordStatus = "Not checked"
    @AppStorage("security.device.status") private var deviceStatus = "Not checked"
    var body: some View {
        CleanerPage(title: "Security Center") {
            HStack(spacing: 8) {
                Image("SecurityCenter").resizable().scaledToFit().frame(width: 64, height: 64)
                Text("Check your security").font(CleanerStyle.font(24, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).frame(minHeight: 104).background(Color(hex: 0xE6EFFB), in: RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 8) {
                NavigationLink { EmailCheckScreen() } label: { module("Email Leakage", "Check for reported breaches.", "envelope", FidelityPreview.active ? (securityFixture.contains("hubReviewed") ? "Issues found" : "Not checked") : emailStatus) }
                NavigationLink { PasswordCheckScreen() } label: { module("Password Check", "Check strength and known leaks.", "key.horizontal", FidelityPreview.active ? (securityFixture.contains("hubReviewed") ? "OK" : "Not checked") : passwordStatus) }
                NavigationLink { DeviceSecurityScreen() } label: { module("Device Security", "Review your iPhone settings.", "iphone", FidelityPreview.active ? "Not checked" : deviceStatus) }
            }
        }.buttonStyle(.plain)
    }
    private func module(_ title: String, _ message: String, _ symbol: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecurityGlyph(name: symbol)
                Text(title).font(CleanerStyle.font(16, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Disclosure()
            }
            Text(message).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24)
            SecurityBadge(value: status)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(CleanerStyle.ink)
    }
}

private struct EmailBreach: Identifiable {
    let id: String
    let date: String
    let fields: String
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
    @State private var email = ""
    @State private var phase = EmailCheckPhase.entry
    @State private var breaches: [EmailBreach] = []
    private var valid: Bool { email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    var body: some View {
        ToolsPage(title: "Email Leakage", centered: phase == .checking, footerVisible: phase != .checking) {
            switch phase {
            case .entry:
                SecurityFeatureCard(title: "Check an email address", message: "See whether this address appears in reported data breaches.", symbol: "envelope")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email address").font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                    TextField("", text: $email)
                        .overlay(alignment: .leading) { if email.isEmpty { Text(verbatim: "name@example.com").foregroundStyle(CleanerStyle.secondary).allowsHitTesting(false).accessibilityHidden(true) } }
                        .accessibilityLabel("Email address").textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).frame(minHeight: 56).background(!email.isEmpty && !valid ? Color(hex: 0xFFF0EF) : .white, in: RoundedRectangle(cornerRadius: 16))
                }
                if !email.isEmpty && !valid { Text("Enter a valid email address.").foregroundStyle(Color(hex: 0x9D3740)) }
            case .checking:
                VStack(spacing: 24) {
                    EmailCheckingArtwork()
                    VStack(spacing: 0) { Text("Checking email…").font(CleanerStyle.font(16, .semibold)); Text(email).foregroundStyle(CleanerStyle.secondary) }
                }.frame(maxWidth: .infinity)
            case .clear, .leaks:
                VStack(alignment: .leading, spacing: 8) {
                    Image(phase == .clear ? "SecurityClearIcon" : "SecurityIssueIcon").resizable().scaledToFit().frame(width: 40, height: 40)
                    Text(phase == .clear ? "No leaks found" : "\(breaches.count) leaks found").font(CleanerStyle.font(24, .semibold))
                    Text(email).foregroundStyle(CleanerStyle.secondary)
                    if phase == .clear { Text("This email did not appear in the records checked.").foregroundStyle(CleanerStyle.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                ForEach(breaches) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.id).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                        Text(item.date).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24)
                        Text(item.fields).frame(minHeight: 24)
                    }.foregroundStyle(CleanerStyle.ink).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            case .unavailable:
                SecurityFeatureCard(title: "Check unavailable", message: "Try again when the connection is available.", symbol: "envelope")
                if !FidelityPreview.active { Text("The email breach service is not available yet. Your address has not been sent or checked.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary) }
            }
        } footer: {
            switch phase {
            case .entry: PrimaryButton(title: "Check", disabled: !valid, disabledFill: Color(hex: 0xE0E7F0)) { phase = .unavailable }
            case .clear, .leaks: PrimaryButton(title: "Check another email") { email = ""; breaches = []; phase = .entry }
            case .unavailable: PrimaryButton(title: "Retry") { phase = .entry }
            case .checking: EmptyView()
            }
        }.onAppear(perform: loadFixture)
    }
    private func loadFixture() {
        guard FidelityPreview.active else { return }
        let name = securityFixture
        email = name.contains("Risk") || name.contains("checkingLeak") || name.hasSuffix("/ leaks") ? "maya@example.com" : "alex@example.com"
        if name.contains("emailEmpty") { email = "" }
        if name.contains("emailInvalid") { email = "alex@" }
        if name.contains("checking") { phase = .checking }
        if name.contains("noLeaks") { phase = .clear }
        if name.hasSuffix("/ leaks") { phase = .leaks; breaches = [.init(id: "Northline Forum", date: "Mar 18, 2024", fields: "Email address, username"), .init(id: "Juniper Club", date: "Sep 6, 2023", fields: "Email address, phone number")] }
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
    private var score: Int {
        if FidelityPreview.active { return securityFixture.contains("Weak") ? 0 : securityFixture.contains("Medium") ? 1 : 2 }
        let classes = [password.rangeOfCharacter(from: .lowercaseLetters) != nil, password.rangeOfCharacter(from: .uppercaseLetters) != nil, password.rangeOfCharacter(from: .decimalDigits) != nil, password.rangeOfCharacter(from: .symbols.union(.punctuationCharacters)) != nil].filter { $0 }.count
        return password.count >= 16 && classes >= 3 ? 2 : password.count >= 10 && classes >= 2 ? 1 : 0
    }
    private var strengthColor: Color { [Color(hex: 0xBA354A), Color(hex: 0xBF761B), Color(hex: 0x1CB450)][score] }
    var body: some View {
        ToolsPage(title: "Password Check", footerVisible: result != nil || !FidelityPreview.active) {
            SecurityFeatureCard(title: "Check a password", message: "Review its strength and whether it appears in known leaks.", symbol: "key.horizontal")
            VStack(alignment: .leading, spacing: 8) {
                Text("Password").font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                SecureField("", text: $password)
                    .overlay(alignment: .leading) { if password.isEmpty { Text(verbatim: "Enter a password").foregroundStyle(CleanerStyle.secondary).allowsHitTesting(false).accessibilityHidden(true) } }
                    .accessibilityLabel("Password").textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).frame(minHeight: 56).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Strength"); Spacer(); Text(password.isEmpty ? "—" : ["Weak", "Medium", "Strong"][score]).foregroundStyle(CleanerStyle.blue) }.font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                HStack(spacing: 8) { ForEach(0..<3) { index in Capsule().fill(!password.isEmpty && index <= score ? strengthColor : Color(hex: 0xDFE6F0)).frame(height: 8) } }
                Text(password.isEmpty ? "Enter a password to see its strength." : ["Use a longer phrase with several unrelated words.", "Make it longer and avoid predictable substitutions.", "Keep this password unique to one account."][score]).foregroundStyle(CleanerStyle.secondary).frame(minHeight: password.isEmpty ? 24 : 48, alignment: .topLeading)
            }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
            if let result {
                if leaked { SecurityFeatureCard(title: "Found in leaks", message: "Choose a new password before using this one.", symbol: "exclamationmark.shield", titleColor: Color(hex: 0x9D3740)) }
                else { Text(result).foregroundStyle(CleanerStyle.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
                if !FidelityPreview.active && !leaked { Text("A known-leak result does not guarantee that a password is safe.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary) }
            }
            if !FidelityPreview.active {
                Text("Known-leak check uses Have I Been Pwned. Only the first 5 characters of a SHA-1 hash are sent; the password stays on your device.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary)

            }
        } footer: {
            if result != nil { PrimaryButton(title: "Done") { dismiss() } }
            else if !FidelityPreview.active {
                PrimaryButton(title: checking ? "Checking…" : "Check known leaks", disabled: password.isEmpty || checking) {
                    let candidate = password; let id = UUID(); requestID = id
                    task = Task { await check(candidate, id: id) }
                }
            }
        }.onChange(of: password) { _, _ in if !FidelityPreview.active { requestID = UUID(); task?.cancel(); checking = false; result = nil; leaked = false } }
            .onDisappear { requestID = UUID(); task?.cancel(); password = "" }
            .onAppear {
                guard FidelityPreview.active else { return }
                password = securityFixture.contains("Empty") ? "" : String(repeating: "x", count: securityFixture.contains("Weak") ? 4 : securityFixture.contains("Medium") ? 8 : 12)
                if !password.isEmpty { result = "No match in checked leaks"; leaked = securityFixture.contains("pwdLeaks") }
            }
    }
    private func check(_ candidate: String, id: UUID) async {
        checking = true; result = nil; leaked = false
        defer { if id == requestID { checking = false } }
        let digest = Insecure.SHA1.hash(data: Data(candidate.utf8)).map { String(format: "%02X", $0) }.joined()
        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(digest.prefix(5))") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        do {
            let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request); try Task.checkCancellation()
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
                Text(paths[guide]).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                if !FidelityPreview.active { Button("Open Settings", action: openCleanerSettings).frame(minHeight: 44) }
            } else if review {
                SecurityFeatureCard(title: "Review your settings", message: "Choose the result after checking the recommendations on your iPhone.", symbol: "iphone")
                PrimaryButton(title: "Everything is set") { record("OK") }
                PrimaryButton(title: "Needs attention") { record("Issues found") }
            } else {
                ForEach(0..<3) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(titles[index]).font(CleanerStyle.font(16, .semibold))
                        SecurityBadge(value: (fixtureStatuses ?? [updates, passcode, twoFactor])[index])
                        Text(paths[index]).foregroundStyle(CleanerStyle.secondary)
                        Button("Open Settings") { guide = index }.font(CleanerStyle.font(16, .semibold)).foregroundStyle(CleanerStyle.blue).frame(minHeight: 32)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                if !FidelityPreview.active { Text("This checklist records your own review. Cleaner cannot read these system settings.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary) }
            }
        } footer: {
            if guide != nil { PrimaryButton(title: "Back to checklist") { guide = nil } }
            else if !review {
                PrimaryButton(title: (fixtureStatuses ?? [updates, passcode, twoFactor]).allSatisfy { $0 == "Not checked" } ? "Review checklist" : "Done") { if (fixtureStatuses ?? [updates, passcode, twoFactor]).allSatisfy({ $0 == "Not checked" }) { review = true } else { dismiss() } }
            }
        }.onAppear {
            guard FidelityPreview.active else { return }
            if securityFixture.contains("deviceMixed") { fixtureStatuses = ["Issues found", "OK", "Not checked"] }
            else { fixtureStatuses = Array(repeating: securityFixture.contains("deviceOK") ? "OK" : "Not checked", count: 3) }
            review = securityFixture.hasSuffix("/ review")
            for index in 0..<3 where securityFixture.contains("guide\(index)") { guide = index }
        }
    }
    private func record(_ value: String) { if FidelityPreview.active { fixtureStatuses = Array(repeating: value, count: 3) } else { updates = value; passcode = value; twoFactor = value; hubStatus = value }; review = false }
}

/// Routes fidelity arguments to the same views used by real navigation.
struct ToolsFidelityScreen: View {
    var body: some View {
        let name = FidelityPreview.name
        if name == "Overlay · Access off" { Color.white.overlay { CleanerModal(title: "Photos access is off", message: "Allow Cleaner to add photos in Settings to save your image.", asset: "", primaryTitle: "Back to editor", onPrimary: {}) } }
        else if name == "Overlay · Photo saved" { Color.white.overlay { CleanerModal(title: "Photo saved", message: "Added to your photo library.", asset: "PhotoSaved", onPrimary: {}) } }
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
            CleanerHeader(title: title)
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16, content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: centered ? max(0, geometry.size.height - 32) : nil, alignment: centered ? .center : .topLeading)
                        .padding(16)
                }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) { if footerVisible { footer().padding(16).background(dynamicType.isAccessibilitySize ? CleanerStyle.bg : .clear) } }
            .background(LinearGradient(stops: [.init(color: CleanerStyle.bg, location: 0.78), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.ink).toolbar(.hidden, for: .navigationBar)
    }
}
