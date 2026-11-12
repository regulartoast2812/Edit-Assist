import AVFoundation
import CryptoKit
import Foundation
import Security

/// Remy, the publisher (2026-11-12, you asked): one video, posted to Facebook (your Page), Instagram (its linked
/// professional account), TikTok and YouTube in one go, through each platform's own API with developer apps you
/// register; then each post's numbers. This file is the platforms; `RemyDesk` keeps the accounts and posts.
enum RemyPlatform: String, CaseIterable, Codable, Identifiable {
    case facebook, instagram, tiktok, youtube
    var id: String { rawValue }
    var name: String {
        switch self { case .facebook: "Facebook"; case .instagram: "Instagram"; case .tiktok: "TikTok"; case .youtube: "YouTube" }
    }
    /// The developer app it signs in with: Facebook and Instagram share Meta's.
    var app: RemyApp {
        switch self { case .facebook, .instagram: .meta; case .tiktok: .tiktok; case .youtube: .google }
    }
    /// How long its text may be (YouTube's is the description; its title is 100).
    var limit: Int {
        switch self { case .facebook: 63_206; case .instagram, .tiktok: 2_200; case .youtube: 5_000 }
    }
}

/// A developer app you register once: Meta's (Facebook and Instagram), TikTok's, Google's (YouTube).
enum RemyApp: String, CaseIterable, Codable, Identifiable {
    case meta, tiktok, google
    var id: String { rawValue }
    var name: String {
        switch self { case .meta: "Meta"; case .tiktok: "TikTok"; case .google: "Google" }
    }
    var platforms: [RemyPlatform] { RemyPlatform.allCases.filter { $0.app == self } }
    /// Where the sign-in comes back to. Nothing is served there: Remy's sign-in window stops at it and takes the code.
    /// Google's desktop clients take any address on this Mac (127.0.0.1) without it being added.
    var redirect: String {
        switch self { case .meta, .tiktok: "https://localhost/remy/"; case .google: "http://127.0.0.1:8765/" }
    }
    var console: URL {
        switch self {
        case .meta: URL(string: "https://developers.facebook.com/apps/")!
        case .tiktok: URL(string: "https://developers.tiktok.com/apps/")!
        case .google: URL(string: "https://console.cloud.google.com/apis/credentials")!
        }
    }
}

/// Your developer app's ID and secret, and the redirect you registered with it.
struct RemyCredentials: Codable, Equatable {
    var id = ""
    var secret = ""
    var redirect = ""
    var ready: Bool { !id.trimmed.isEmpty && !secret.trimmed.isEmpty && URL(string: redirect.trimmed)?.host != nil }
}

/// The account a platform posts to: the Page, the Instagram account, the TikTok account, the YouTube channel.
struct RemyAccount: Codable, Equatable {
    var id: String
    var name: String
    var token: String
    var refresh: String? = nil
    var expires: Date? = nil
    var stale: Bool { expires.map { $0 < Date().addingTimeInterval(300) } ?? false }
}

struct RemyError: LocalizedError {
    let message: String
    /// The platform's own code for it, when it gave one (TikTok's unaudited apps, say).
    var code: String? = nil
    init(_ message: String, code: String? = nil) { self.message = message; self.code = code }
    var errorDescription: String? { message }
}

/// What a post's upload says as it goes.
enum RemyStep { case uploading(Double), processing }

/// A post that went up: its id on the platform, its link, and a note (posted as private, say).
struct RemyPublished { var id: String; var url: String?; var kind: String? = nil; var note: String? = nil }

/// A post's numbers on one platform; nil where the platform didn't give it.
struct RemyStats: Codable, Equatable {
    var views: Int?
    var likes: Int?
    var comments: Int?
    var shares: Int?
    var url: String?
    var fetched: Date
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The ID, secret and sign-ins, in the login Keychain only (never in UserDefaults or a file).
enum RemyKeychain {
    static let service = "Edit Assist Remy"
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    static func read<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        var query = query(key)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func write<T: Encodable>(_ key: String, _ value: T?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        var item = query(key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The video posted: its size, length and shape, read from the file.
struct RemyVideo: Equatable {
    var url: URL
    var bytes: Int64
    var seconds: Double
    var width: Double
    var height: Double
    var vertical: Bool { height > width }
    var mime: String {
        switch url.pathExtension.lowercased() { case "mov": "video/quicktime"; case "webm": "video/webm"; case "m4v": "video/x-m4v"; default: "video/mp4" }
    }

    static func read(_ url: URL) async throws -> RemyVideo {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
            throw RemyError(L("The video isn't at %@ any more", url.path))
        }
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RemyError(L("%@ has no picture to post", url.lastPathComponent)) }
        let (size, turn) = try await track.load(.naturalSize, .preferredTransform)
        let shown = CGRect(origin: .zero, size: size).applying(turn)
        return RemyVideo(url: url, bytes: bytes.int64Value, seconds: seconds.isFinite ? seconds : 0, width: abs(shown.width), height: abs(shown.height))
    }
}

/// What each platform will make of the video, said before posting: a Reel or a regular video, a Short, too long.
enum Remy {
    /// YouTube's title when you don't write one: the caption's first line, without hashtags, at most 100 characters.
    static func title(from caption: String) -> String {
        let line = caption.split(whereSeparator: \.isNewline).map { String($0).trimmed }.first { !$0.isEmpty } ?? ""
        let words = line.split(separator: " ").filter { !$0.hasPrefix("#") }.joined(separator: " ")
        return String(cleanTitle(words.isEmpty ? line : words).prefix(100))
    }

    /// YouTube refuses < and > in a title.
    static func cleanTitle(_ title: String) -> String { title.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "").trimmed }

    static func notes(_ video: RemyVideo, _ platforms: [RemyPlatform]) -> [String] {
        platforms.compactMap { platform in
            switch platform {
            case .facebook: return reel(video) ? L("Facebook: a Reel") : L("Facebook: a video on your Page (a Reel is upright and 3–90 s)")
            case .instagram:
                if video.seconds < 3 { return L("Instagram: too short, a Reel is at least 3 s") }
                if video.seconds > 15 * 60 { return L("Instagram: too long, a Reel is at most 15 min") }
                return L("Instagram: a Reel")
            case .tiktok: return video.seconds > 10 * 60 ? L("TikTok: longer than most accounts may post (10 min)") : nil
            case .youtube: return short(video) ? L("YouTube: a Short") : L("YouTube: a regular video (a Short is upright and at most 3 min)")
            }
        }
    }

    /// Facebook takes an upright video of 3 to 90 seconds as a Reel; anything else goes up as a Page video.
    static func reel(_ video: RemyVideo) -> Bool { video.vertical && video.seconds >= 3 && video.seconds <= 90 }
    static func short(_ video: RemyVideo) -> Bool { video.vertical && video.seconds <= 180 }
    /// Text longer than the platform takes.
    static func over(_ text: String, _ platform: RemyPlatform) -> Bool { text.count > platform.limit }
}

// MARK: - Requests

enum RemyHTTP {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value }
    static func form(_ items: [String: String]) -> String { items.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&") }
    static func url(_ base: String, _ query: [String: String] = [:]) -> URL {
        URL(string: query.isEmpty ? base : base + (base.contains("?") ? "&" : "?") + form(query))!
    }

    /// Sends a request (with a body, or a file streamed from disk) and reads its JSON; a platform's error as it said it.
    @discardableResult
    static func send(_ request: URLRequest, data: Data? = nil, file: URL? = nil, progress: ((Double) -> Void)? = nil) async throws -> (json: [String: Any], response: HTTPURLResponse) {
        let delegate = progress.map(RemyProgress.init)
        let (body, response): (Data, URLResponse)
        if let file {
            (body, response) = try await URLSession.shared.upload(for: request, fromFile: file, delegate: delegate)
        } else if let data {
            (body, response) = try await URLSession.shared.upload(for: request, from: data, delegate: delegate)
        } else {
            (body, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        }
        let http = response as? HTTPURLResponse ?? HTTPURLResponse()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if let failure = failure(json, body, status: http.statusCode) { throw failure }
        return (json, http)
    }

    /// Meta's, Google's and TikTok's ways of saying no. TikTok answers every call with an `error` whose code is "ok".
    static func failure(_ json: [String: Any], _ body: Data, status: Int) -> RemyError? {
        if let error = json["error"] as? [String: Any] {
            let code = (error["code"] as? String) ?? (error["code"] as? NSNumber)?.stringValue
            if code == "ok" { return nil }
            let message = (error["error_user_msg"] as? String) ?? (error["message"] as? String) ?? (error["status"] as? String) ?? code ?? "?"
            return RemyError(message.isEmpty ? (code ?? "?") : message, code: code)
        }
        if let error = json["error"] as? String {
            return RemyError((json["error_description"] as? String) ?? error, code: error)
        }
        guard !(200 ..< 300).contains(status) else { return nil }
        let text = String(data: body.prefix(300), encoding: .utf8)?.trimmed ?? ""
        return RemyError(L("The platform answered %@: %@", String(status), text.isEmpty ? "–" : text))
    }

    static func get(_ url: URL, bearer: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 60)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await send(request).json
    }

    static func post(_ url: URL, form items: [String: String], bearer: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await send(request, data: Data(form(items).utf8)).json
    }

    static func post(_ url: URL, json: [String: Any], bearer: String?, headers: [String: String] = [:]) async throws -> (json: [String: Any], response: HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return try await send(request, data: try JSONSerialization.data(withJSONObject: json))
    }

    /// A number as JSON gives it: a number or a string of digits.
    static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue ?? (value as? String).flatMap { Int($0) } }
    static func string(_ value: Any?) -> String? { (value as? String) ?? (value as? NSNumber).map { "\($0.int64Value)" } }
}

/// An upload's progress, sent as it goes.
final class RemyProgress: NSObject, URLSessionTaskDelegate {
    let report: (Double) -> Void
    init(_ report: @escaping (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

// MARK: - Signing in

/// One sign-in: the platform's page, where it comes back, and what proves it's this one.
struct RemySignIn: Identifiable, Equatable {
    let id = UUID()
    let app: RemyApp
    let url: URL
    let redirect: String
    let state: String
    let verifier: String
}

enum RemyAuth {
    static let metaScopes = ["pages_show_list", "pages_read_engagement", "pages_manage_posts", "read_insights", "business_management",
                             "instagram_basic", "instagram_content_publish", "instagram_manage_insights"]
    static let tiktokScopes = ["user.info.basic", "video.publish", "video.upload", "video.list"]
    static let googleScopes = ["https://www.googleapis.com/auth/youtube.upload", "https://www.googleapis.com/auth/youtube.readonly"]

    static func start(_ app: RemyApp, _ credentials: RemyCredentials) -> RemySignIn {
        let state = random(16), verifier = random(48)
        let redirect = credentials.redirect.trimmed, id = credentials.id.trimmed
        let url: URL
        switch app {
        case .meta:
            url = RemyHTTP.url("https://www.facebook.com/\(RemyMeta.version)/dialog/oauth",
                               ["client_id": id, "redirect_uri": redirect, "state": state, "response_type": "code", "scope": metaScopes.joined(separator: ",")])
        case .tiktok:
            url = RemyHTTP.url("https://www.tiktok.com/v2/auth/authorize/",
                               ["client_key": id, "redirect_uri": redirect, "state": state, "response_type": "code", "scope": tiktokScopes.joined(separator: ",")])
        case .google:
            url = RemyHTTP.url("https://accounts.google.com/o/oauth2/v2/auth",
                               ["client_id": id, "redirect_uri": redirect, "state": state, "response_type": "code", "scope": googleScopes.joined(separator: " "),
                                "access_type": "offline", "prompt": "consent", "code_challenge": challenge(verifier), "code_challenge_method": "S256"])
        }
        return RemySignIn(app: app, url: url, redirect: redirect, state: state, verifier: verifier)
    }

    /// Whether a page the sign-in window is about to open is the redirect (scheme, host, port and path).
    static func isRedirect(_ url: URL, _ redirect: String) -> Bool {
        guard let target = URL(string: redirect) else { return false }
        let path = { (url: URL) in url.path.isEmpty ? "/" : url.path }
        return url.scheme?.lowercased() == target.scheme?.lowercased() && url.host?.lowercased() == target.host?.lowercased()
            && url.port == target.port && path(url).hasPrefix(path(target))
    }

    /// The code the redirect carries, or why there's none; nil when the URL isn't the redirect.
    static func answer(_ url: URL, _ signIn: RemySignIn) -> Result<String, RemyError>? {
        guard isRedirect(url, signIn.redirect) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") ?? value("error_code") {
            return .failure(RemyError(value("error_description") ?? value("error_message") ?? value("error_reason") ?? error, code: error))
        }
        guard value("state") == signIn.state else { return .failure(RemyError(L("The sign-in came back for another request; try again"))) }
        guard let code = value("code"), !code.isEmpty else { return .failure(RemyError(L("The sign-in came back without a code; try again"))) }
        return .success(code)
    }

    static func random(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64url(data)
    }
    static func challenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Meta: Facebook Page and Instagram

enum RemyMeta {
    static let version = "v23.0"
    static let graph = "https://graph.facebook.com/\(version)/"

    /// A Page you manage, its token, and the Instagram professional account linked to it.
    struct Page: Identifiable, Equatable {
        var id: String
        var name: String
        var token: String
        var instagramID: String?
        var instagramName: String?
    }

    /// The sign-in's code, made a long-lived token, then the Pages it manages, each with a token that doesn't expire.
    static func pages(code: String, _ credentials: RemyCredentials) async throws -> [Page] {
        let app = ["client_id": credentials.id.trimmed, "client_secret": credentials.secret.trimmed]
        let short = try await RemyHTTP.get(RemyHTTP.url(graph + "oauth/access_token", app.merging(["redirect_uri": credentials.redirect.trimmed, "code": code]) { $1 }))
        guard let shortToken = short["access_token"] as? String else { throw RemyError(L("Facebook gave no sign-in token")) }
        let long = try await RemyHTTP.get(RemyHTTP.url(graph + "oauth/access_token", app.merging(["grant_type": "fb_exchange_token", "fb_exchange_token": shortToken]) { $1 }))
        let token = long["access_token"] as? String ?? shortToken
        let found = try await RemyHTTP.get(RemyHTTP.url(graph + "me/accounts", ["fields": "id,name,access_token,instagram_business_account{id,username}", "limit": "100", "access_token": token]))
        let pages = (found["data"] as? [[String: Any]] ?? []).compactMap { page -> Page? in
            guard let id = RemyHTTP.string(page["id"]), let token = page["access_token"] as? String else { return nil }
            let instagram = page["instagram_business_account"] as? [String: Any]
            return Page(id: id, name: page["name"] as? String ?? id, token: token,
                        instagramID: RemyHTTP.string(instagram?["id"]), instagramName: instagram?["username"] as? String)
        }
        guard !pages.isEmpty else { throw RemyError(L("This Facebook account manages no Page Remy was allowed to see; sign in again and tick your Page")) }
        return pages
    }

    /// Facebook's own upload host, which takes the file in one request.
    private static func rupload(_ url: URL, _ video: RemyVideo, token: String, _ step: @escaping (RemyStep) -> Void) async throws {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "offset")
        request.setValue(String(video.bytes), forHTTPHeaderField: "file_size")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        try await RemyHTTP.send(request, file: video.url) { step(.uploading($0)) }
    }

    /// To your Page: an upright video of 3–90 s as a Reel, anything else as a Page video.
    static func postToPage(_ video: RemyVideo, text: String, page: RemyAccount, step: @escaping (RemyStep) -> Void) async throws -> RemyPublished {
        if Remy.reel(video) {
            let start = try await RemyHTTP.post(RemyHTTP.url(graph + "\(page.id)/video_reels"), form: ["upload_phase": "start", "access_token": page.token])
            guard let id = RemyHTTP.string(start["video_id"]) else { throw RemyError(L("Facebook didn't start the upload")) }
            let upload = (start["upload_url"] as? String).flatMap(URL.init) ?? URL(string: "https://rupload.facebook.com/video-upload/\(version)/\(id)")!
            try await rupload(upload, video, token: page.token, step)
            step(.processing)
            _ = try await RemyHTTP.post(RemyHTTP.url(graph + "\(page.id)/video_reels"),
                                        form: ["upload_phase": "finish", "video_id": id, "video_state": "PUBLISHED", "description": text, "access_token": page.token])
            return RemyPublished(id: id, url: "https://www.facebook.com/reel/\(id)", kind: "reel")
        }
        // A Page video: the file in a form, written to a temporary file first so it is streamed, not held in memory.
        let boundary = "Remy-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("remy-\(UUID().uuidString).body")
        defer { try? FileManager.default.removeItem(at: body) }
        FileManager.default.createFile(atPath: body.path, contents: nil)
        do {
            let out = try FileHandle(forWritingTo: body)
            defer { try? out.close() }
            for (name, value) in [("access_token", page.token), ("description", text)] {
                out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"source\"; filename=\"video.\(video.url.pathExtension.lowercased())\"\r\nContent-Type: \(video.mime)\r\n\r\n".utf8))
            let input = try FileHandle(forReadingFrom: video.url)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty { out.write(chunk) }
            out.write(Data("\r\n--\(boundary)--\r\n".utf8))
        }
        var request = URLRequest(url: URL(string: "https://graph-video.facebook.com/\(version)/\(page.id)/videos")!, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let json = try await RemyHTTP.send(request, file: body) { step(.uploading($0)) }.json
        guard let id = RemyHTTP.string(json["id"]) else { throw RemyError(L("Facebook took the video but gave no id")) }
        return RemyPublished(id: id, url: "https://www.facebook.com/\(page.id)/videos/\(id)", kind: "video")
    }

    /// To Instagram as a Reel: a container, the file, Instagram's processing (up to 15 minutes), then published.
    static func postToInstagram(_ video: RemyVideo, text: String, account: RemyAccount, step: @escaping (RemyStep) -> Void) async throws -> RemyPublished {
        let made = try await RemyHTTP.post(RemyHTTP.url(graph + "\(account.id)/media"),
                                           form: ["media_type": "REELS", "upload_type": "resumable", "caption": text, "share_to_feed": "true", "access_token": account.token])
        guard let container = RemyHTTP.string(made["id"]) else { throw RemyError(L("Instagram didn't start the upload")) }
        let upload = (made["uri"] as? String).flatMap(URL.init) ?? URL(string: "https://rupload.facebook.com/ig-api-upload/\(version)/\(container)")!
        try await rupload(upload, video, token: account.token, step)
        step(.processing)
        let deadline = Date().addingTimeInterval(15 * 60)
        while true {
            let state = try await RemyHTTP.get(RemyHTTP.url(graph + container, ["fields": "status_code,status", "access_token": account.token]))
            switch state["status_code"] as? String {
            case "FINISHED": break
            case "ERROR", "EXPIRED": throw RemyError(L("Instagram couldn't take the video: %@", state["status"] as? String ?? "–"))
            default:
                guard Date() < deadline else { throw RemyError(L("Instagram was still working on the video after 15 minutes")) }
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            break
        }
        let published = try await RemyHTTP.post(RemyHTTP.url(graph + "\(account.id)/media_publish"), form: ["creation_id": container, "access_token": account.token])
        guard let media = RemyHTTP.string(published["id"]) else { throw RemyError(L("Instagram published nothing")) }
        let link = try? await RemyHTTP.get(RemyHTTP.url(graph + media, ["fields": "permalink", "access_token": account.token]))["permalink"] as? String
        return RemyPublished(id: media, url: link, kind: "reel")
    }

    /// A metric from Meta's insights, in either of the shapes it answers with.
    static func insight(_ json: [String: Any], _ name: String) -> Int? {
        guard let entry = (json["data"] as? [[String: Any]] ?? []).first(where: { $0["name"] as? String == name }) else { return nil }
        if let values = entry["values"] as? [[String: Any]], let value = RemyHTTP.int(values.first?["value"]) { return value }
        return RemyHTTP.int((entry["total_value"] as? [String: Any])?["value"])
    }

    static func pageStats(_ id: String, kind: String?, token: String) async -> RemyStats {
        var stats = RemyStats(fetched: Date())
        if let video = try? await RemyHTTP.get(RemyHTTP.url(graph + id, ["fields": "likes.summary(true).limit(0),comments.summary(true).limit(0),permalink_url", "access_token": token])) {
            stats.likes = RemyHTTP.int(((video["likes"] as? [String: Any])?["summary"] as? [String: Any])?["total_count"])
            stats.comments = RemyHTTP.int(((video["comments"] as? [String: Any])?["summary"] as? [String: Any])?["total_count"])
            stats.url = (video["permalink_url"] as? String).map { $0.hasPrefix("/") ? "https://www.facebook.com" + $0 : $0 }
        }
        let metric = kind == "reel" ? "blue_reels_play_count" : "total_video_views"
        if let insights = try? await RemyHTTP.get(RemyHTTP.url(graph + "\(id)/video_insights", ["metric": metric, "access_token": token])) {
            stats.views = insight(insights, metric)
        }
        return stats
    }

    static func instagramStats(_ id: String, token: String) async -> RemyStats {
        var stats = RemyStats(fetched: Date())
        if let media = try? await RemyHTTP.get(RemyHTTP.url(graph + id, ["fields": "like_count,comments_count,permalink", "access_token": token])) {
            stats.likes = RemyHTTP.int(media["like_count"])
            stats.comments = RemyHTTP.int(media["comments_count"])
            stats.url = media["permalink"] as? String
        }
        if let insights = try? await RemyHTTP.get(RemyHTTP.url(graph + "\(id)/insights", ["metric": "views,shares", "access_token": token])) {
            stats.views = insight(insights, "views")
            stats.shares = insight(insights, "shares")
        }
        return stats
    }
}

// MARK: - TikTok

enum RemyTikTok {
    static let api = "https://open.tiktokapis.com/v2/"

    static func account(code: String, _ credentials: RemyCredentials) async throws -> RemyAccount {
        let json = try await RemyHTTP.post(RemyHTTP.url(api + "oauth/token/"),
                                           form: ["client_key": credentials.id.trimmed, "client_secret": credentials.secret.trimmed, "code": code,
                                                  "grant_type": "authorization_code", "redirect_uri": credentials.redirect.trimmed])
        var account = try tokens(json, previous: nil)
        let user = try? await RemyHTTP.get(RemyHTTP.url(api + "user/info/", ["fields": "open_id,display_name"]), bearer: account.token)
        account.name = ((user?["data"] as? [String: Any])?["user"] as? [String: Any])?["display_name"] as? String ?? account.name
        return account
    }

    /// The access token lasts a day; the refresh token a year.
    static func refreshed(_ account: RemyAccount, _ credentials: RemyCredentials) async throws -> RemyAccount {
        guard let refresh = account.refresh else { throw RemyError(L("Sign in to %@ again under Accounts", "TikTok")) }
        let json = try await RemyHTTP.post(RemyHTTP.url(api + "oauth/token/"),
                                           form: ["client_key": credentials.id.trimmed, "client_secret": credentials.secret.trimmed,
                                                  "grant_type": "refresh_token", "refresh_token": refresh])
        return try tokens(json, previous: account)
    }

    private static func tokens(_ json: [String: Any], previous: RemyAccount?) throws -> RemyAccount {
        guard let token = json["access_token"] as? String else { throw RemyError(L("TikTok gave no sign-in token")) }
        let id = RemyHTTP.string(json["open_id"]) ?? previous?.id ?? ""
        return RemyAccount(id: id, name: previous?.name ?? "TikTok", token: token, refresh: json["refresh_token"] as? String ?? previous?.refresh,
                           expires: Date().addingTimeInterval(Double(RemyHTTP.int(json["expires_in"]) ?? 86_400)))
    }

    /// TikTok's chunks: the whole file when it's at most 64 MB, else 10 MB chunks, the last one taking the rest.
    static func chunks(_ size: Int64) -> (size: Int64, count: Int) {
        guard size > 64_000_000 else { return (size, 1) }
        let chunk: Int64 = 10_000_000
        return (chunk, Int(size / chunk))
    }

    /// Posted publicly when TikTok lets the app; an app TikTok hasn't audited yet may only post privately, so it's
    /// posted again as private (only you see it, and you can make it public in TikTok).
    static func post(_ video: RemyVideo, text: String, account: RemyAccount, step: @escaping (RemyStep) -> Void) async throws -> RemyPublished {
        let info = try await RemyHTTP.post(RemyHTTP.url(api + "post/publish/creator_info/query/"), json: [:], bearer: account.token).json
        let options = (info["data"] as? [String: Any])?["privacy_level_options"] as? [String] ?? []
        let wanted = options.contains("PUBLIC_TO_EVERYONE") || options.isEmpty ? "PUBLIC_TO_EVERYONE" : options[0]
        do {
            return try await post(video, text, account, privacy: wanted, step)
        } catch let error as RemyError where (error.code ?? "").contains("unaudited") && wanted != "SELF_ONLY" {
            var published = try await post(video, text, account, privacy: "SELF_ONLY", step)
            published.note = L("Private: TikTok lets an app it hasn't audited post only as private. Make it public in TikTok.")
            return published
        }
    }

    private static func post(_ video: RemyVideo, _ text: String, _ account: RemyAccount, privacy: String, _ step: @escaping (RemyStep) -> Void) async throws -> RemyPublished {
        let plan = chunks(video.bytes)
        let started = try await RemyHTTP.post(RemyHTTP.url(api + "post/publish/video/init/"), json: [
            "post_info": ["title": text, "privacy_level": privacy, "disable_duet": false, "disable_comment": false, "disable_stitch": false, "video_cover_timestamp_ms": 1000],
            "source_info": ["source": "FILE_UPLOAD", "video_size": video.bytes, "chunk_size": plan.size, "total_chunk_count": plan.count],
        ], bearer: account.token).json
        let data = started["data"] as? [String: Any] ?? [:]
        guard let publish = RemyHTTP.string(data["publish_id"]), let upload = (data["upload_url"] as? String).flatMap(URL.init) else {
            throw RemyError(L("TikTok didn't start the upload"))
        }
        let input = try FileHandle(forReadingFrom: video.url)
        defer { try? input.close() }
        for index in 0 ..< plan.count {
            let first = Int64(index) * plan.size
            let last = index == plan.count - 1 ? video.bytes - 1 : first + plan.size - 1
            try input.seek(toOffset: UInt64(first))
            let chunk = try input.read(upToCount: Int(last - first + 1)) ?? Data()
            var request = URLRequest(url: upload, timeoutInterval: 300)
            request.httpMethod = "PUT"
            request.setValue(video.mime, forHTTPHeaderField: "Content-Type")
            request.setValue("bytes \(first)-\(last)/\(video.bytes)", forHTTPHeaderField: "Content-Range")
            let total = Double(video.bytes), done = Double(first), size = Double(chunk.count)
            try await RemyHTTP.send(request, data: chunk) { step(.uploading((done + $0 * size) / total)) }
        }
        step(.processing)
        let deadline = Date().addingTimeInterval(15 * 60)
        while true {
            let json = try await RemyHTTP.post(RemyHTTP.url(api + "post/publish/status/fetch/"), json: ["publish_id": publish], bearer: account.token).json
            let state = json["data"] as? [String: Any] ?? [:]
            switch state["status"] as? String {
            case "PUBLISH_COMPLETE":
                // TikTok's own spelling.
                let id = (state["publicaly_available_post_id"] as? [Any])?.first.flatMap(RemyHTTP.string)
                return RemyPublished(id: id ?? publish, url: nil, kind: id == nil ? "private" : "video")
            case "FAILED":
                throw RemyError(L("TikTok couldn't post it: %@", state["fail_reason"] as? String ?? "–"))
            default:
                guard Date() < deadline else { throw RemyError(L("TikTok was still working on the video after 15 minutes")) }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    static func stats(_ ids: [String], account: RemyAccount) async throws -> [String: RemyStats] {
        var found: [String: RemyStats] = [:]
        for start in stride(from: 0, to: ids.count, by: 20) {
            let json = try await RemyHTTP.post(RemyHTTP.url(api + "video/query/", ["fields": "id,view_count,like_count,comment_count,share_count,share_url"]),
                                               json: ["filters": ["video_ids": Array(ids[start ..< min(start + 20, ids.count)])]], bearer: account.token).json
            for video in (json["data"] as? [String: Any])?["videos"] as? [[String: Any]] ?? [] {
                guard let id = RemyHTTP.string(video["id"]) else { continue }
                found[id] = RemyStats(views: RemyHTTP.int(video["view_count"]), likes: RemyHTTP.int(video["like_count"]), comments: RemyHTTP.int(video["comment_count"]),
                                      shares: RemyHTTP.int(video["share_count"]), url: video["share_url"] as? String, fetched: Date())
            }
        }
        return found
    }
}

// MARK: - YouTube

enum RemyYouTube {
    static func account(code: String, verifier: String, _ credentials: RemyCredentials) async throws -> RemyAccount {
        let json = try await RemyHTTP.post(RemyHTTP.url("https://oauth2.googleapis.com/token"),
                                           form: ["client_id": credentials.id.trimmed, "client_secret": credentials.secret.trimmed, "code": code, "code_verifier": verifier,
                                                  "grant_type": "authorization_code", "redirect_uri": credentials.redirect.trimmed])
        guard let token = json["access_token"] as? String else { throw RemyError(L("Google gave no sign-in token")) }
        let channels = try await RemyHTTP.get(RemyHTTP.url("https://www.googleapis.com/youtube/v3/channels", ["part": "snippet", "mine": "true"]), bearer: token)
        guard let channel = (channels["items"] as? [[String: Any]])?.first, let id = channel["id"] as? String else {
            throw RemyError(L("This Google account has no YouTube channel; make one on YouTube, then sign in again"))
        }
        return RemyAccount(id: id, name: (channel["snippet"] as? [String: Any])?["title"] as? String ?? id, token: token, refresh: json["refresh_token"] as? String,
                           expires: Date().addingTimeInterval(Double(RemyHTTP.int(json["expires_in"]) ?? 3600)))
    }

    static func refreshed(_ account: RemyAccount, _ credentials: RemyCredentials) async throws -> RemyAccount {
        guard let refresh = account.refresh else { throw RemyError(L("Sign in to %@ again under Accounts", "YouTube")) }
        let json = try await RemyHTTP.post(RemyHTTP.url("https://oauth2.googleapis.com/token"),
                                           form: ["client_id": credentials.id.trimmed, "client_secret": credentials.secret.trimmed, "grant_type": "refresh_token", "refresh_token": refresh])
        guard let token = json["access_token"] as? String else { throw RemyError(L("Google gave no sign-in token")) }
        var account = account
        account.token = token
        account.expires = Date().addingTimeInterval(Double(RemyHTTP.int(json["expires_in"]) ?? 3600))
        return account
    }

    /// A resumable upload: the details first, then the file to the address YouTube gives.
    static func post(_ video: RemyVideo, title: String, text: String, account: RemyAccount, step: @escaping (RemyStep) -> Void) async throws -> RemyPublished {
        let started = try await RemyHTTP.post(RemyHTTP.url("https://www.googleapis.com/upload/youtube/v3/videos", ["uploadType": "resumable", "part": "snippet,status"]), json: [
            "snippet": ["title": String(Remy.cleanTitle(title).prefix(100)), "description": text, "categoryId": "22"],
            "status": ["privacyStatus": "public", "selfDeclaredMadeForKids": false],
        ], bearer: account.token, headers: ["X-Upload-Content-Length": String(video.bytes), "X-Upload-Content-Type": video.mime])
        guard let location = started.response.value(forHTTPHeaderField: "Location").flatMap(URL.init) else { throw RemyError(L("YouTube didn't start the upload")) }
        var request = URLRequest(url: location, timeoutInterval: 300)
        request.httpMethod = "PUT"
        request.setValue(video.mime, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        let json = try await RemyHTTP.send(request, file: video.url) { step(.uploading($0)) }.json
        guard let id = json["id"] as? String else { throw RemyError(L("YouTube took the video but gave no id")) }
        let privacy = (json["status"] as? [String: Any])?["privacyStatus"] as? String
        return RemyPublished(id: id, url: Remy.short(video) ? "https://youtube.com/shorts/\(id)" : "https://youtu.be/\(id)", kind: "video",
                             note: privacy == "private" ? L("Private: YouTube keeps uploads from an app Google hasn't audited private") : nil)
    }

    static func stats(_ ids: [String], account: RemyAccount) async throws -> [String: RemyStats] {
        var found: [String: RemyStats] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let json = try await RemyHTTP.get(RemyHTTP.url("https://www.googleapis.com/youtube/v3/videos",
                                                           ["part": "statistics", "id": ids[start ..< min(start + 50, ids.count)].joined(separator: ",")]), bearer: account.token)
            for video in json["items"] as? [[String: Any]] ?? [] {
                guard let id = video["id"] as? String, let numbers = video["statistics"] as? [String: Any] else { continue }
                found[id] = RemyStats(views: RemyHTTP.int(numbers["viewCount"]), likes: RemyHTTP.int(numbers["likeCount"]), comments: RemyHTTP.int(numbers["commentCount"]),
                                      shares: nil, url: nil, fetched: Date())
            }
        }
        return found
    }
}
