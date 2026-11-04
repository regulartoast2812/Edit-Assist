import SwiftUI
import WebKit

/// Penny, the numbers helper: a businessman, a platinum blob with side-parted hair, gold glasses and a charcoal suit with
/// a money-green tie, holding up a bar chart (a teal blob with a bun read as Perry the Platypus, 2026-11-03). Working:
/// the bars rise and fall and his glasses catch the light.
struct PixelPenny: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 205 / 255, green: 212 / 255, blue: 222 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
                       ".OGKGGGKGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
                       ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"]
    static let blink = ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
                        ".OGOGGGOGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
                        ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OGKGGGKGO.A....", ".OOGOOOGOO.A..Y.", ".OOOOOOOOO.A.PY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OgKGGgKGO.A.P..", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OGKGGGKGO.A..Y.", ".OOGOOOGOO.AY.Y.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OgKGGgKGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 205 / 255, green: 212 / 255, blue: 222 / 255), "D": Color(red: 95 / 255, green: 100 / 255, blue: 110 / 255),
                                "N": Color(red: 45 / 255, green: 40 / 255, blue: 40 / 255), "n": Color(red: 110 / 255, green: 100 / 255, blue: 95 / 255),
                                "G": Color(red: 205 / 255, green: 165 / 255, blue: 70 / 255), "g": Color(red: 1, green: 245 / 255, blue: 200 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "S": Color(red: 80 / 255, green: 86 / 255, blue: 100 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "T": Color(red: 60 / 255, green: 170 / 255, blue: 90 / 255),
                                "A": Color(red: 200 / 255, green: 200 / 255, blue: 205 / 255), "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255),
                                "P": Color(red: 240 / 255, green: 120 / 255, blue: 110 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Penny")
    }
}

/// Penny in the sidebar, at work while he reads Grafana.
struct PennyIcon: View {
    @ObservedObject var desk: PennyDesk
    var body: some View { PixelPenny(pixel: 1.25, busyUntil: desk.exploring ? .distantFuture : nil) }
}

/// Penny's page: signed in to the company's Grafana with your Google account, the dashboards you can see, and the three
/// you use read down to the queries behind their panels, to build your campaign, sales and revenue sheet from (2026-11-05).
struct PennyPage: View {
    @ObservedObject var desk: PennyDesk
    @State private var signingIn = false
    private let accent = PixelPenny.theme

    var body: some View {
        ThinScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelPenny(pixel: 4, busyUntil: desk.exploring || desk.state == .checking ? .distantFuture : nil, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your numbers helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Gets the numbers for the **products you run** from the company's **Grafana**",
                             "Shows how each product is doing, like an **accountant** and **analyst**",
                             "**Only reads**: never changes anything in Grafana"], size: 11)
                }
            }
            section(L("GRAFANA"), trailing: Grafana.base.host) { account }
            if case .signedIn = desk.state { section(L("WHAT PENNY CAN SEE")) { seen } }
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .onAppear { desk.open() }
        .sheet(isPresented: $signingIn) {
            GrafanaSignInSheet { session in
                signingIn = false
                if let session { desk.signedIn(session: session) }
            }
        }
    }

    @ViewBuilder var account: some View {
        switch desk.state {
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking with Grafana…")).font(.system(size: 12)) }
        case .signedIn(let user):
            status(true, L("Signed in as **%@**", user.name.isEmpty ? user.login : user.name) + (user.email.isEmpty ? "" : " · \(user.email)"))
            HStack(spacing: 8) {
                Button(L("Read again")) { desk.explore() }.disabled(desk.exploring)
                Button(L("Sign out"), role: .destructive) { desk.signOut() }
            }.controlSize(.small)
        case .failed(let reason):
            status(false, reason)
            HStack(spacing: 8) {
                Button(L("Try again")) { desk.check() }
                Button(L("Sign in again")) { signingIn = true }
            }.controlSize(.small)
        case .signedOut:
            Text(md: L("The company's Grafana only takes **Sign in with Google**. Sign in once here with your work account; Penny keeps the session in your Mac's **Keychain** and asks again when Grafana ends it."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(L("Sign in with Google")) { signingIn = true }
        }
    }

    @ViewBuilder var seen: some View {
        if desk.exploring {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Reading your dashboards…")).font(.system(size: 12)) }
        }
        if let failure = desk.failure { status(false, failure) }
        if !desk.dashboards.isEmpty {
            status(nil, L("**%@** dashboards you can see, **%@** starred", desk.dashboards.count, desk.dashboards.filter(\.starred).count))
        }
        ForEach(desk.boards) { board in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(board.title).font(.system(size: 13, weight: .semibold))
                    if !board.folder.isEmpty { Text(board.folder).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                    Text(L("%@ panels", board.panels.count)).font(.system(size: 10)).foregroundStyle(.secondary)
                    Button { NSWorkspace.shared.open(Grafana.base.appendingPathComponent("d/\(board.uid)")) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.borderless).help(L("Open in the browser"))
                }
                if !board.variables.isEmpty {
                    Text(L("Filters: %@", board.variables.joined(separator: ", "))).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ForEach(board.panels) { panel in
                    DisclosureGroup {
                        ForEach(Array(panel.queries.enumerated()), id: \.offset) { _, query in
                            Text(query).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 5))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(panel.title.isEmpty ? L("Untitled") : panel.title).font(.system(size: 11))
                            Text([panel.type, panel.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary)
                            Spacer()
                            if !panel.queries.isEmpty { Text(L("%@ queries", panel.queries.count)).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .padding(10).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
        if desk.explored != nil {
            HStack(spacing: 8) {
                Text(L("Saved on this Mac only, to build your sheet from")).font(.system(size: 10)).foregroundStyle(.secondary)
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([PennyDesk.folder]) }.controlSize(.small)
            }
        }
    }

    func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: good == nil ? "info.circle" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(md: text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Grafana's own Google sign-in in a window of its own, with nothing kept but the session it ends with: a private web
/// store, so no other site's cookies are read or left behind.
struct GrafanaSignInSheet: View {
    let done: (String?) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(md: L("Sign in to **Grafana** with your work Google account")).font(.system(size: 12))
                Spacer()
                Button(L("Cancel")) { done(nil) }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            GrafanaSignIn(done: done)
        }.frame(width: 560, height: 700)
    }
}

struct GrafanaSignIn: NSViewRepresentable {
    let done: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        // Google turns away sign-ins from pages it takes for an app's web view; Safari's own name gets the normal page.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: Grafana.base.appendingPathComponent("login/google")))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let done: (String?) -> Void
        private var finished = false
        init(done: @escaping (String?) -> Void) { self.done = done }

        /// Back on Grafana past its login pages: the session is in the cookies.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished, let url = webView.url, url.host == Grafana.base.host, !url.path.hasPrefix("/login") else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished,
                      let session = cookies.first(where: { $0.name == "grafana_session" && !$0.value.isEmpty && Grafana.base.host?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) == true })?.value
                else { return }
                self.finished = true
                DispatchQueue.main.async { self.done(session) }
            }
        }

        /// A link that would open a new window opens here.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(action.request)
            return nil
        }
    }
}
