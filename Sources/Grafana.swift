import Foundation
import Security

/// The company's Grafana (grafana.selless.com, Grafana 11.2): Google sign-in only, its login form is off. Penny keeps
/// the session your sign-in made (in the Keychain, never in UserDefaults or projects.json) and reads with it; Grafana
/// rotates that session every few minutes, so a refused request first asks for the new one (2026-11-05). Penny only
/// reads: he never saves, changes or deletes anything in Grafana.
enum Grafana {
    static let base = URL(string: "https://grafana.selless.com/")!
    private static let service = "Edit Assist Grafana"
    /// The dashboards your course notes link to: operations, the daily report and the campaign breakdown.
    static let known = ["H08d5_r4k", "de9g9h30i79xcb", "IiWe9FSIz"]

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
    static func request(_ path: String, body: Data? = nil, renewed: Bool = false) async throws -> Data {
        guard let session else { throw Failure.signedOut }
        var request = URLRequest(url: URL(string: path, relativeTo: base)!, timeoutInterval: 60)
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
            guard !renewed, try await renewal.renew(refused: session) else {
                if Self.session == session { Self.session = nil }
                throw Failure.signedOut
            }
            return try await self.request(path, body: body, renewed: true)
        }
        guard (200 ..< 300).contains(status) else { throw Failure.refused(status, message(in: data) ?? "HTTP \(status)") }
        return data
    }

    /// One renewal at a time: panels refused together wait for the same new session rather than each asking for one.
    private actor Renewal {
        private var running: Task<Bool, Error>?
        func renew(refused: String) async throws -> Bool {
            if let current = Grafana.session, current != refused { return true }
            if let running { return try await running.value }
            let task = Task { try await Grafana.rotate() }
            running = task
            defer { running = nil }
            return try await task.value
        }
    }
    private static let renewal = Renewal()

    /// Asks Grafana for the session that replaces this one (its token rotation); false when it is over.
    static func rotate() async throws -> Bool {
        guard let session else { return false }
        var request = URLRequest(url: base.appendingPathComponent("api/user/auth-tokens/rotate"), timeoutInterval: 30)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("grafana_session=\(session)", forHTTPHeaderField: "Cookie")
        request.setValue(String(base.absoluteString.dropLast()), forHTTPHeaderField: "Origin")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let renewed = sessionCookie(in: http) else { return false }
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
    private var sources: [Grafana.Source]
    private var opened = false

    static var folder: URL { Studio.folder.appendingPathComponent("penny", isDirectory: true) }

    init() {
        sources = (try? Data(contentsOf: Self.folder.appendingPathComponent("datasources.json"))).map(Grafana.sources(from:)) ?? []
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder.appendingPathComponent("dashboards"), includingPropertiesForKeys: nil)) ?? []
        boards = Self.ordered(files.filter { $0.pathExtension == "json" }.compactMap { (try? Data(contentsOf: $0)).flatMap(Grafana.dashboard(from:)) })
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

    func check() {
        guard Grafana.session != nil else { state = .signedOut; return }
        state = .checking
        Task {
            do {
                guard let user = Grafana.user(from: try await Grafana.request("api/user")) else { throw Grafana.Failure.refused(0, L("Grafana did not say who you are.")) }
                state = .signedIn(user)
                if let board { board.load() } else { show(UserDefaults.standard.string(forKey: "pennyBoard") ?? Grafana.known[0]) }
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
    }

    func signOut() {
        Grafana.session = nil
        state = .signedOut; dashboards = []; board = nil
    }

    /// Draws a dashboard on the page and reads its numbers; the one you pick is the one shown next time.
    func show(_ uid: String) {
        UserDefaults.standard.set(uid, forKey: "pennyBoard")
        guard let dashboard = boards.first(where: { $0.uid == uid }) ?? boards.first else { board = nil; return }
        let board = PennyBoard(dashboard: dashboard, sources: sources)
        board.onBusy = { [weak self] in self?.reading = $0 }
        board.onSignedOut = { [weak self] in self?.signOut() }
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
                if let board, let fresh = boards.first(where: { $0.uid == board.dashboard.uid }), fresh.version != board.dashboard.version { show(fresh.uid) }
                else if board == nil { show(UserDefaults.standard.string(forKey: "pennyBoard") ?? Grafana.known[0]) }
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
