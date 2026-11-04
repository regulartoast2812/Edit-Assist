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
            guard !renewed, try await rotate() else { Self.session = nil; throw Failure.signedOut }
            return try await self.request(path, body: body, renewed: true)
        }
        guard (200 ..< 300).contains(status) else { throw Failure.refused(status, message(in: data) ?? "HTTP \(status)") }
        return data
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
              let renewed = sessionCookie(in: http) else { return false }
        Self.session = renewed
        return true
    }

    static func sessionCookie(in response: HTTPURLResponse) -> String? {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value } }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: base).first { $0.name == "grafana_session" && !$0.value.isEmpty }?.value
    }

    static func message(in data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
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

    /// A panel and the queries behind it.
    struct Panel: Identifiable, Equatable {
        var id: Int
        var title: String
        var type: String
        var source: String
        var queries: [String]
    }

    /// A dashboard's filters (template variables) and panels, rows opened up (a collapsed row keeps its panels inside it).
    struct Board: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var title: String
        var folder: String
        var variables: [String]
        var panels: [Panel]
    }

    static func board(from data: Data) -> Board? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dashboard = object["dashboard"] as? [String: Any], let uid = dashboard["uid"] as? String else { return nil }
        func source(_ value: Any?) -> String {
            if let name = value as? String { return name }
            if let object = value as? [String: Any] { return object["type"] as? String ?? object["uid"] as? String ?? "" }
            return ""
        }
        func panels(_ list: [[String: Any]]) -> [Panel] {
            list.flatMap { panel -> [Panel] in
                let inner = panels(panel["panels"] as? [[String: Any]] ?? [])
                guard panel["type"] as? String != "row" else { return inner }
                let targets = panel["targets"] as? [[String: Any]] ?? []
                let queries = targets.compactMap { target in
                    ["rawSql", "expr", "query", "sql", "rawQuery"].lazy.compactMap { target[$0] as? String }.first { !$0.isEmpty }
                }
                let from = source(panel["datasource"]).isEmpty ? targets.lazy.map { source($0["datasource"]) }.first { !$0.isEmpty } ?? "" : source(panel["datasource"])
                return [Panel(id: panel["id"] as? Int ?? 0, title: panel["title"] as? String ?? "", type: panel["type"] as? String ?? "",
                              source: from, queries: queries)] + inner
            }
        }
        let variables = ((dashboard["templating"] as? [String: Any])?["list"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let meta = object["meta"] as? [String: Any]
        return Board(uid: uid, title: dashboard["title"] as? String ?? uid, folder: meta?["folderTitle"] as? String ?? "",
                     variables: variables, panels: panels(dashboard["panels"] as? [[String: Any]] ?? []))
    }
}

/// Penny's side of Grafana: who you are signed in as, the dashboards you can see, and the three you use read down to
/// their panels' queries. What he reads is saved beside projects.json (penny/), on this Mac only.
@MainActor
final class PennyDesk: ObservableObject {
    enum State: Equatable { case signedOut, checking, signedIn(Grafana.User), failed(String) }
    @Published private(set) var state: State = Grafana.session == nil ? .signedOut : .checking
    @Published private(set) var dashboards: [Grafana.Found] = []
    @Published private(set) var boards: [Grafana.Board] = []
    @Published private(set) var exploring = false
    @Published private(set) var explored: Date?
    @Published private(set) var failure: String?
    private var opened = false

    static var folder: URL { Studio.folder.appendingPathComponent("penny", isDirectory: true) }

    func open() {
        guard !opened else { return }
        opened = true
        check()
    }

    func check() {
        guard Grafana.session != nil else { state = .signedOut; return }
        state = .checking
        Task {
            do {
                guard let user = Grafana.user(from: try await Grafana.request("api/user")) else { throw Grafana.Failure.refused(0, L("Grafana did not say who you are.")) }
                state = .signedIn(user)
                if boards.isEmpty { explore() }
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
        state = .signedOut; dashboards = []; boards = []; explored = nil
    }

    /// Reads which dashboards you can see and, for the ones you use and the ones you starred, their panels and queries.
    /// Each answer is saved as it came in penny/, to map the campaign and sales queries from.
    func explore() {
        guard !exploring else { return }
        exploring = true; failure = nil
        Task {
            do {
                let folder = Self.folder
                try FileManager.default.createDirectory(at: folder.appendingPathComponent("dashboards"), withIntermediateDirectories: true)
                for (path, file) in [("api/user", "user.json"), ("api/user/teams", "teams.json"), ("api/user/orgs", "orgs.json"), ("api/datasources", "datasources.json")] {
                    if let data = try? await Grafana.request(path) { try? data.write(to: folder.appendingPathComponent(file)) }
                }
                let search = try await Grafana.request("api/search?type=dash-db&limit=5000")
                try search.write(to: folder.appendingPathComponent("search.json"))
                dashboards = Grafana.found(from: search)
                var read: [Grafana.Board] = []
                let wanted = Grafana.known + dashboards.filter(\.starred).map(\.uid).filter { !Grafana.known.contains($0) }
                for uid in wanted {
                    guard let data = try? await Grafana.request("api/dashboards/uid/\(uid)") else { continue }
                    try? data.write(to: folder.appendingPathComponent("dashboards/\(uid).json"))
                    if let board = Grafana.board(from: data) { read.append(board) }
                }
                boards = read
                explored = Date()
            } catch Grafana.Failure.signedOut {
                state = .signedOut
            } catch {
                failure = Self.describe(error)
            }
            exploring = false
        }
    }

    static func describe(_ error: Error) -> String {
        if case Grafana.Failure.refused(let status, let reason) = error { return status == 0 ? reason : L("Grafana refused (%@): %@", status, reason) }
        return error.localizedDescription
    }
}
