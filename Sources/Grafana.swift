import Foundation
import Security
import WebKit

/// The company's Grafana (grafana.selless.com, Grafana 11.2): Google sign-in only, its login form is off. Penny keeps
/// the session your sign-in made (in the Keychain, never in UserDefaults or projects.json) and reads with it; Grafana
/// rotates that session every few minutes, so a refused request first asks for the new one (2026-11-05). When Grafana
/// won't renew it, Penny signs in again by himself with the Google account his sign-in window remembers (`signInAgain`,
/// 2026-11-08, first in the Windows app: you were asked to sign in too often), and only asks you when Google does.
/// Penny only reads: he never saves, changes or deletes anything in Grafana.
enum Grafana {
    static let base = URL(string: "https://grafana.selless.com/")!
    private static let service = "Edit Assist Grafana"
    /// The dashboards Penny reads besides your starred ones. Retail Operations V3.5 first, the one you read: it gathers
    /// every team's sales and ads (Facebook, Google, Pinterest…). Then the Facebook campaigns (each campaign's sales and
    /// spend, and by hour), PMKT's operations and daily report and the Facebook campaign breakdown.
    static let known = ["NCvK5_rVz", "aevqvkupwlkowe", "H08d5_r4k", "de9g9h30i79xcb", "IiWe9FSIz"]

    /// The grafana_session cookie's value in the login Keychain; nil removes it.
    static var session: String? {
        get {
            var result: AnyObject?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: "session", kSecReturnData as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: "session"]
            SecItemDelete(query as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    enum Failure: Error { case signedOut, refused(Int, String) }

    /// A read (GET), or a query (POST to /api/ds/query), with the session; a session past its rotation is renewed once.
    static func request(_ path: String, body: Data? = nil, renewed: Bool = false, again: Bool = false) async throws -> Data {
        guard let session else { throw Failure.signedOut }
        // "" is Grafana's own page, which URL(string:) can't make.
        guard let url = path.isEmpty ? base : URL(string: path, relativeTo: base) else { throw Failure.refused(0, L("Penny asked Grafana for a page that can't exist: %@", path)) }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpShouldHandleCookies = false
        request.setValue("grafana_session=\(session)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(base.absoluteString.dropLast()), forHTTPHeaderField: "Origin")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            // Renewed (Grafana's rotation), or failing that signed in again with the remembered Google account.
            if !renewed {
                if try await renewal.renew(refused: session) { return try await self.request(path, body: body, renewed: true) }
            }
            // Renewal failed, or the renewed session was refused at once (2026-11-10, after the Mac slept): sign in
            // again with the remembered Google account, once, before giving up.
            if !again, await renewal.again(refused: session) { return try await self.request(path, body: body, renewed: true, again: true) }
            if Self.session == session {
                Self.session = nil
                note("Signed out: Grafana refused the session on \(url.path)\(renewed ? " just after it was renewed" : "")")
            }
            throw Failure.signedOut
        }
        guard (200 ..< 300).contains(status) else { throw Failure.refused(status, message(in: data) ?? "HTTP \(status)") }
        return data
    }

    /// One renewal at a time: panels refused together wait for the same new session rather than each asking for one.
    /// One sign-in again at a time, for the same reason.
    private actor Renewal {
        private var running: Task<Bool, Error>?
        private var signingIn: Task<Bool, Never>?
        func renew(refused: String) async throws -> Bool {
            if let current = Grafana.session, current != refused { return true }
            if let running { return try await running.value }
            let task = Task { try await Grafana.rotate() }
            running = task
            defer { running = nil }
            return try await task.value
        }

        /// Signs in again by himself (`signInAgain`) when Grafana won't renew the session; false when he can't.
        func again(refused: String) async -> Bool {
            if let current = Grafana.session, current != refused { return true }
            guard let again = Grafana.signInAgain else { return false }
            if let signingIn { return await signingIn.value }
            let task = Task { () -> Bool in
                if let session = await again() {
                    Grafana.session = session
                    Grafana.note("Signed in again by himself with the remembered Google account")
                    return true
                }
                Grafana.note("Couldn't sign in again by himself: Google wanted you")
                return false
            }
            signingIn = task
            defer { signingIn = nil }
            return await task.value
        }
    }
    private static let renewal = Renewal()

    /// Signs in again without asking: the sign-in window, out of sight, with the Google account it remembers; the
    /// session it ends with, or nil when Google wants you to choose or confirm. Set by Penny's desk; nil in the checks.
    static var signInAgain: (@MainActor () async -> String?)?
    /// Forgets the Google account the sign-in window remembers (Sign out). Set by Penny's desk.
    static var forget: (@MainActor () -> Void)?

    /// penny/sign-ins.log beside projects.json.
    static var signIns: URL { Studio.folder.appendingPathComponent("penny/sign-ins.log") }

    /// A line in penny/sign-ins.log: when a session ended and why, and when Penny signed in again by himself, so a
    /// session that keeps ending can be looked into. Never the session itself. Cut to its last 200 lines past 64 KB.
    static func note(_ what: String, in file: URL = signIns) {
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 64 * 1024,
           let text = try? String(contentsOf: file, encoding: .utf8) {
            let kept = text.split(separator: "\n").suffix(200)
            try? (kept.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = Data("\(stamp.string(from: Date()))  \(what)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile(); handle.write(line); try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }

    /// Asks Grafana for the session that replaces this one (its token rotation); false when it is over.
    static func rotate() async throws -> Bool {
        guard let session else { return false }
        var request = URLRequest(url: base.appendingPathComponent("api/user/auth-tokens/rotate"), timeoutInterval: 30)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("grafana_session=\(session)", forHTTPHeaderField: "Cookie")
        request.setValue(String(base.absoluteString.dropLast()), forHTTPHeaderField: "Origin")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let renewed = sessionCookie(in: http) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            note("Grafana wouldn't renew the session: HTTP \(status)\((200 ..< 300).contains(status) ? ", no new session in its reply" : "")")
            return false
        }
        Self.session = renewed
        return true
    }

    static func sessionCookie(in response: HTTPURLResponse) -> String? {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value } }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: base).first { $0.name == "grafana_session" && !$0.value.isEmpty }?.value
    }

    /// Grafana's reason for refusing: its message, or a query's error (a SQL error comes back this way).
    static func message(in data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let message = object["message"] as? String { return message }
        return (object["results"] as? [String: Any] ?? [:]).values.lazy.compactMap { ($0 as? [String: Any])?["error"] as? String }.first
    }

    // MARK: What Penny reads

    /// The timezone in the data Grafana's page starts with (window.grafanaBootData): the user's, worked out by Grafana
    /// from your preferences, your team's, the company's and the server's default.
    static func pageZone(from data: Data) -> String? {
        guard let page = String(data: data, encoding: .utf8), let start = page.range(of: "grafanaBootData"),
              let open = page[start.upperBound...].firstIndex(of: "{") else { return nil }
        // The object runs to its matching brace; braces inside strings don't count.
        var depth = 0, inString = false, escaped = false, end: String.Index?
        for index in page[open...].indices {
            let character = page[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" { depth -= 1; if depth == 0 { end = index; break } }
        }
        guard let end, let boot = (try? JSONSerialization.jsonObject(with: Data(page[open ... end].utf8))) as? [String: Any] else { return nil }
        return ((boot["user"] as? [String: Any])?["timezone"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The server's default timezone, from Grafana's frontend settings.
    static func serverZone(from data: Data) -> String? {
        let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((settings?["dateFormats"] as? [String: Any])?["defaultTimezone"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    struct User: Equatable { var name: String; var email: String; var login: String }

    static func user(from data: Data) -> User? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let login = object["login"] as? String else { return nil }
        return User(name: object["name"] as? String ?? "", email: object["email"] as? String ?? "", login: login)
    }

    /// A dashboard in the search: what it is called, its folder, and where it opens.
    struct Found: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var title: String
        var folder: String
        var url: String
        var starred: Bool
    }

    static func found(from data: Data) -> [Found] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []).compactMap { item in
            guard item["type"] as? String == "dash-db", let uid = item["uid"] as? String else { return nil }
            return Found(uid: uid, title: item["title"] as? String ?? uid, folder: item["folderTitle"] as? String ?? "",
                         url: item["url"] as? String ?? "", starred: item["isStarred"] as? Bool ?? false)
        }
    }
}

/// Penny's side of Grafana: who you are signed in as, the dashboards you can see, and the three you use (and any you
/// starred) read and saved beside projects.json (penny/), on this Mac only. The one you picked is drawn on his page as
/// Grafana draws it, straight from what is saved while Grafana is asked for anything newer.
@MainActor
final class PennyDesk: ObservableObject {
    enum State: Equatable { case signedOut, checking, signedIn(Grafana.User), failed(String) }
    @Published private(set) var state: State = Grafana.session == nil ? .signedOut : .checking
    @Published private(set) var dashboards: [Grafana.Found] = []
    @Published private(set) var boards: [Grafana.Dashboard]
    @Published private(set) var board: PennyBoard?
    @Published private(set) var exploring = false
    @Published private(set) var reading = false
    @Published private(set) var failure: String?
    /// Signing in again out of sight with the remembered Google account, when the page opens signed out.
    @Published private(set) var signingInAgain = false
    /// Penny's own copy of the ads' numbers by product, kept up to date while you are signed in.
    let ledger = PennyLedger()
    private var sources: [Grafana.Source]
    /// Your, your team's and the company's timezone in Grafana, in that order (nil when not set).
    private var zones: [String?]
    private var opened = false

    static var folder: URL { Studio.folder.appendingPathComponent("penny", isDirectory: true) }

    init() {
        sources = (try? Data(contentsOf: Self.folder.appendingPathComponent("datasources.json"))).map(Grafana.sources(from:)) ?? []
        zones = Self.zones(in: Self.folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder.appendingPathComponent("dashboards"), includingPropertiesForKeys: nil)) ?? []
        boards = Self.ordered(files.filter { $0.pathExtension == "json" }.compactMap { (try? Data(contentsOf: $0)).flatMap(Grafana.dashboard(from:)) })
        // The copy, or a board, found the session over (and Penny couldn't sign in again): signed out, the account kept.
        ledger.onSignedOut = { [weak self] in self?.ended() }
        Grafana.signInAgain = { await GrafanaWeb.silently() }
        Grafana.forget = { GrafanaWeb.forget() }
        if Grafana.session != nil { ledger.start() }
    }

    /// The timezone Grafana settled on for you first (what its own page starts with), then yours, your team's, the
    /// company's and the server's default, each as a {"timezone": …} file.
    static func zones(in folder: URL) -> [String?] {
        ["timezone-page.json", "preferences-user.json", "preferences-team.json", "preferences-org.json", "timezone-server.json"].map {
            (try? Data(contentsOf: folder.appendingPathComponent($0))).flatMap(Grafana.preferredZone(from:))
        }
    }

    /// The three you use first, in their order, then the ones you starred by name.
    static func ordered(_ boards: [Grafana.Dashboard]) -> [Grafana.Dashboard] {
        boards.sorted { a, b in
            let first = Grafana.known.firstIndex(of: a.uid) ?? Int.max, second = Grafana.known.firstIndex(of: b.uid) ?? Int.max
            return first != second ? first < second : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// The page opened: the first time, who you are; later, the numbers again when they are more than five minutes old.
    func open() {
        guard opened else { opened = true; check(); return }
        if case .signedIn = state, let board, !board.busy, (board.updated ?? .distantPast) < Date().addingTimeInterval(-300) { board.load() }
    }

    private var triedAgain = false

    func check() {
        state = .checking
        Task {
            // Signed out when the page opens (the session ended while the app was closed): once, sign in again by himself.
            if Grafana.session == nil, !triedAgain, let again = Grafana.signInAgain {
                triedAgain = true
                signingInAgain = true
                let session = await again()
                signingInAgain = false
                if let session {
                    Grafana.session = session
                    Grafana.note("Signed in again by himself when Penny opened")
                    ledger.start()
                } else {
                    Grafana.note("Couldn't sign in again by himself when Penny opened: Google wanted you, or no account is remembered")
                }
            }
            guard Grafana.session != nil else { state = .signedOut; return }
            do {
                guard let user = Grafana.user(from: try await Grafana.request("api/user")) else { throw Grafana.Failure.refused(0, L("Grafana did not say who you are.")) }
                state = .signedIn(user)
                if let board { board.load() } else { show(chosen) }
                explore()
            } catch Grafana.Failure.signedOut {
                state = .signedOut
            } catch {
                state = .failed(Self.describe(error))
            }
        }
    }

    /// The sign-in window found the session.
    func signedIn(session: String) {
        Grafana.session = session
        check()
        ledger.start()
    }

    /// Sign out: the session ends and the Google account the sign-in window remembers is forgotten.
    func signOut() {
        Grafana.forget?()
        Grafana.note("Signed out by you; the Google account forgotten")
        ended()
    }

    /// The session is over; the remembered Google account stays, for the next sign-in.
    func ended() {
        Grafana.session = nil
        ledger.stop()
        state = .signedOut; dashboards = []; board = nil
    }

    /// The dashboard you last picked from Penny's menu, or Retail Operations.
    private var chosen: String { UserDefaults.standard.string(forKey: "pennyDashboard") ?? Grafana.known[0] }

    /// A dashboard picked from Penny's menu: shown now and next time.
    func pick(_ uid: String) {
        UserDefaults.standard.set(uid, forKey: "pennyDashboard")
        show(uid)
    }

    /// Draws a dashboard on the page and reads its numbers.
    func show(_ uid: String) {
        guard let dashboard = boards.first(where: { $0.uid == uid }) ?? boards.first else { board = nil; return }
        Grafana.zone = Grafana.zone([dashboard.timezone] + zones, fallback: dashboard.clock.flatMap(TimeZone.init(identifier:)) ?? .current)
        let board = PennyBoard(dashboard: dashboard, sources: sources)
        board.onBusy = { [weak self] in self?.reading = $0 }
        board.onSignedOut = { [weak self] in self?.ended() }
        self.board = board
        if case .signedIn = state { board.load() }
    }

    /// Reads which dashboards you can see and, for the ones you use and the ones you starred, the dashboards themselves,
    /// each answer saved as it came in penny/. A dashboard changed in Grafana since is drawn again.
    func explore() {
        guard !exploring else { return }
        exploring = true; failure = nil
        Task {
            do {
                let folder = Self.folder
                try FileManager.default.createDirectory(at: folder.appendingPathComponent("dashboards"), withIntermediateDirectories: true)
                for (path, file) in [("api/user", "user.json"), ("api/user/teams", "teams.json"), ("api/user/orgs", "orgs.json"), ("api/datasources", "datasources.json")] {
                    guard let data = try? await Grafana.request(path) else { continue }
                    try? data.write(to: folder.appendingPathComponent(file))
                    if file == "datasources.json" { sources = Grafana.sources(from: data) }
                }
                // The timezone Grafana counts your days in: yours, your team's, the company's.
                let teams = (try? Data(contentsOf: folder.appendingPathComponent("teams.json"))).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] } ?? []
                var preferences = [("api/user/preferences", "preferences-user.json"), ("api/org/preferences", "preferences-org.json")]
                if let team = (teams.first?["id"] as? NSNumber)?.intValue { preferences.append(("api/teams/\(team)/preferences", "preferences-team.json")) }
                for (path, file) in preferences {
                    if let data = try? await Grafana.request(path) { try? data.write(to: folder.appendingPathComponent(file)) }
                }
                // The company's setting may not be yours to read (it was refused, 2026-11-05); Grafana's own page carries
                // the timezone it worked out for you, and its settings the server's default.
                for (path, file, zone) in [("", "timezone-page.json", Grafana.pageZone(from:)), ("api/frontend/settings", "timezone-server.json", Grafana.serverZone(from:))] {
                    guard let data = try? await Grafana.request(path), let found = zone(data),
                          let written = try? JSONSerialization.data(withJSONObject: ["timezone": found]) else { continue }
                    try? written.write(to: folder.appendingPathComponent(file))
                }
                let zonesChanged = Self.zones(in: folder) != zones
                zones = Self.zones(in: folder)
                let search = try await Grafana.request("api/search?type=dash-db&limit=5000")
                try search.write(to: folder.appendingPathComponent("search.json"))
                dashboards = Grafana.found(from: search)
                var read: [Grafana.Dashboard] = []
                let wanted = Grafana.known + dashboards.filter(\.starred).map(\.uid).filter { !Grafana.known.contains($0) }
                for uid in wanted {
                    guard let data = try? await Grafana.request("api/dashboards/uid/\(uid)") else { continue }
                    try? data.write(to: folder.appendingPathComponent("dashboards/\(uid).json"))
                    if let dashboard = Grafana.dashboard(from: data) { read.append(dashboard) }
                }
                if !read.isEmpty { boards = Self.ordered(read) }
                // The one you want may only now be here (read for the first time), or changed in Grafana since.
                if board?.dashboard.uid != chosen, boards.contains(where: { $0.uid == chosen }) { show(chosen) }
                else if let board, let fresh = boards.first(where: { $0.uid == board.dashboard.uid }), fresh.version != board.dashboard.version { show(fresh.uid) }
                else if board == nil { show(chosen) }
                else if zonesChanged, let board { show(board.dashboard.uid) }
            } catch Grafana.Failure.signedOut {
                state = .signedOut
            } catch {
                failure = Self.describe(error)
            }
            exploring = false
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        if case Grafana.Failure.refused(let status, let reason) = error { return status == 0 ? reason : L("Grafana refused (%@): %@", status, reason) }
        return error.localizedDescription
    }
}

/// The sign-in window's web data store, Penny's own (2026-11-08, first in the Windows app): nothing from Safari or your
/// browsers is read, and nothing is kept there but Google's sign-in. It used to be a new empty store each time, so Google
/// asked for your email whenever Grafana ended a session; now it remembers your account, as a browser does, and Penny can
/// sign in again out of sight (`silently`). Your password is never seen or kept by Penny. Grafana's own cookies are
/// removed from the store once the session is taken, so it never holds (or renews) the session Penny reads with: that
/// lives only in the Keychain. Sign out removes the store.
@MainActor
enum GrafanaWeb {
    /// The store's name, fixed so the same one is found again (WKWebsiteDataStore(forIdentifier:), macOS 14).
    static let storeID = UUID(uuidString: "5E1D7A43-2C9B-4F0E-9A6D-7B3C1E8F4A20")!
    /// How long signing in again out of sight may take before Google is taken to want you.
    static let patience: TimeInterval = 25

    static func webView(_ coordinator: GrafanaSignInCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 700), configuration: configuration)
        // Google turns away sign-ins from pages it takes for an app's web view; Safari's own name gets the normal page.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.load(URLRequest(url: Grafana.base.appendingPathComponent("login/google")))
        return view
    }

    /// Whether a Google account is remembered: a sign-in through the store has taken a session and Sign out hasn't
    /// forgotten it since. Kept as Penny's own flag: asking WebKit (`fetchAllDataStoreIdentifiers`) crashed the app at
    /// launch, before any web view had started WebKit's run loop (2026-11-09).
    static let rememberedKey = "pennyGoogleRemembered"
    static func remembered() async -> Bool { UserDefaults.standard.bool(forKey: rememberedKey) }

    /// Signs in again out of sight with the remembered account: the session, or nil when Google wants you (or nothing
    /// is remembered). The page loads in a window off every screen, see-through, that never takes the focus.
    static func silently() async -> String? {
        guard await remembered() else { return nil }
        return await withCheckedContinuation { continuation in
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 560, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
            let coordinator = GrafanaSignInCoordinator { session in
                (window.contentView as? WKWebView)?.stopLoading()
                window.contentView = nil
                window.close()
                continuation.resume(returning: session)
            }
            window.contentView = webView(coordinator)
            window.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + patience) { coordinator.finish(nil) }
        }
    }

    /// Forgets the remembered Google account: the store is removed (once no web view holds it).
    static func forget() {
        UserDefaults.standard.set(false, forKey: rememberedKey)
        Task { @MainActor in
            for _ in 0 ..< 10 {
                if (try? await WKWebsiteDataStore.remove(forIdentifier: storeID)) != nil { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

/// The sign-in page's delegate, seen or out of sight: back on Grafana past its login pages, it takes the session from
/// the cookies, removes Grafana's cookies from the store and finishes, once.
@MainActor
final class GrafanaSignInCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let done: (String?) -> Void
    private var finished = false
    init(done: @escaping (String?) -> Void) { self.done = done }

    func finish(_ session: String?) {
        guard !finished else { return }
        finished = true
        done(session)
    }

    /// Back on Grafana past its login pages: the session is in the cookies.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !finished, let url = webView.url, url.host == Grafana.base.host, !url.path.hasPrefix("/login") else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self, weak webView] cookies in
            let host = Grafana.base.host ?? ""
            let grafana = cookies.filter { host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
            guard let self, !self.finished, let session = grafana.first(where: { $0.name == "grafana_session" && !$0.value.isEmpty })?.value else { return }
            // Grafana's cookies leave the store: only Google's sign-in stays, and nothing here renews Penny's session.
            webView?.stopLoading()
            let group = DispatchGroup()
            for cookie in grafana { group.enter(); store.delete(cookie) { group.leave() } }
            group.notify(queue: .main) {
                UserDefaults.standard.set(true, forKey: GrafanaWeb.rememberedKey)
                self.finish(session)
            }
        }
    }

    /// A link that would open a new window opens here.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(action.request)
        return nil
    }
}
