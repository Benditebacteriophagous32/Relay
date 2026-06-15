import SwiftUI
import WebKit
import Security

// MARK: - Cookie vault (Keychain)

/// The Facebook session lives in the macOS Keychain now — not a plaintext file on
/// the Desktop that can be deleted by accident. Legacy cookie files are migrated in
/// once, then ignored.
enum CookieVault {
    private static let service = "com.hatim.relay.session"
    private static let account = "facebook-cookies"

    static func save(_ cookies: String) {
        let data = Data(cookies.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    /// Best available session: Keychain first, then migrate in a legacy Desktop export
    /// or self-healing backup. Returns nil only if there's genuinely no session anywhere.
    static func resolve() -> String? {
        if let s = load() { return s }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacy = [
            home.appendingPathComponent("Desktop/relay-cookies.txt"),
            home.appendingPathComponent("Library/Application Support/Relay/session-cookies.backup.txt"),
        ]
        for url in legacy {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { save(s); return s }   // migrate into the Keychain
            }
        }
        return nil
    }
}

// MARK: - In-app Facebook login

/// Full-window onboarding shown when there's no valid session. First a one-time welcome +
/// risk/consent screen, then the Facebook sign-in web view (password, 2FA, checkpoints all
/// handled). Once the session cookies appear we capture them into the Keychain.
struct LoginView: View {
    @EnvironmentObject var store: RelayStore
    @AppStorage("didAcceptRisks") private var accepted = false
    @State private var showSignIn = false
    @State private var capturing = false

    var body: some View {
        Group {
            if accepted || showSignIn { signIn } else { welcome }
        }
        .frame(minWidth: 560, minHeight: 680)
    }

    // MARK: welcome / consent
    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 18) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 6) {
                    Text("Welcome to Relay").font(.system(size: 26, weight: .bold))
                    Text("A native Mac client for Messenger.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    consentRow("hand.raised.fill", "Unofficial client",
                               "Relay isn't made by Meta. Using a third-party client can get your account rate-limited or banned. Don't use an account you can't afford to lose.")
                    consentRow("lock.fill", "Your session stays on this Mac",
                               "Your Facebook login is stored only in the macOS Keychain and sent only to Meta — exactly like a browser. Relay has no servers and collects nothing.")
                    consentRow("info.circle.fill", "It can break",
                               "Meta changes its protocol without notice. Things may stop working until Relay is updated.")
                }
                .padding(18)
                .frame(maxWidth: 460, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

                Button {
                    accepted = true
                    withAnimation(.smooth(duration: 0.25)) { showSignIn = true }
                } label: {
                    Text("I understand — continue to sign in")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                Text("By continuing you accept these risks. Relay is free, open-source software provided without warranty.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .transition(.opacity)
    }

    private func consentRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: sign-in
    private var signIn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sign in to Messenger").font(.headline)
                    Text("Log into Facebook to connect Relay. Your session stays in the macOS Keychain.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if capturing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Connecting…").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial)
            Divider()
            LoginWebView { cookies in
                capturing = true
                store.completeLogin(cookies)
            }
        }
        .transition(.opacity)
    }
}

/// WKWebView wrapper that watches the cookie store and fires `onCookies` once a
/// real Facebook session (c_user + xs) is present. Shows a loading state and a
/// retry affordance, and uses a desktop user-agent so Facebook serves the full
/// login page.
struct LoginWebView: View {
    let onCookies: (String) -> Void
    @State private var loading = true
    @State private var failed = false
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            LoginWebViewRepresentable(onCookies: onCookies, loading: $loading, failed: $failed, reloadToken: reloadToken)
            if loading && !failed {
                ProgressView("Loading Facebook…").controlSize(.small)
                    .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if failed {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Couldn't reach Facebook").font(.headline)
                    Text("Check your connection and try again.").font(.callout).foregroundStyle(.secondary)
                    Button("Retry") { failed = false; loading = true; reloadToken += 1 }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct LoginWebViewRepresentable: NSViewRepresentable {
    let onCookies: (String) -> Void
    @Binding var loading: Bool
    @Binding var failed: Bool
    let reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // persistent: keeps the web session signed in
        let web = WKWebView(frame: .zero, configuration: cfg)
        // A desktop Safari UA so Facebook serves the full desktop login (not a stripped m.facebook page).
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: URL(string: "https://www.facebook.com/login")!))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastReload != reloadToken {
            context.coordinator.lastReload = reloadToken
            web.load(URLRequest(url: URL(string: "https://www.facebook.com/login")!))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LoginWebViewRepresentable
        var lastReload = 0
        private var done = false
        init(_ parent: LoginWebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.loading = false }
            capture(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.loading = false; self.parent.failed = true }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.loading = false; self.parent.failed = true }
        }

        private func capture(_ webView: WKWebView) {
            guard !done else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let fb = cookies.filter { $0.domain.hasSuffix("facebook.com") }
                guard fb.contains(where: { $0.name == "c_user" }),
                      fb.contains(where: { $0.name == "xs" }) else { return }
                var byName: [String: String] = [:]
                for c in fb { byName[c.name] = c.value }   // de-dup, last wins
                let str = byName.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
                self.done = true
                DispatchQueue.main.async { self.parent.onCookies(str) }
            }
        }
    }
}
