import Foundation

/// One video posted to the platforms you ticked: the caption, each platform's own text and how each went.
struct RemyPost: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var video: String
    var caption: String
    var title: String
    var targets: [RemyTarget]
    var name: String { URL(fileURLWithPath: video).lastPathComponent }
}

/// A post on one platform.
struct RemyTarget: Codable, Identifiable, Equatable {
    enum State: String, Codable { case waiting, uploading, processing, posted, failed }
    var platform: RemyPlatform
    var id: RemyPlatform { platform }
    var text: String
    var state = State.waiting
    var progress = 0.0
    var remoteID: String?
    var url: String?
    var kind: String?
    var note: String?
    var error: String?
    var stats: RemyStats?
    var busy: Bool { state == .waiting || state == .uploading || state == .processing }
}

/// What you're about to post: one caption, which each platform can take as it is or in its own words, and YouTube's title.
struct RemyDraft: Equatable {
    var video: RemyVideo?
    var caption = ""
    var own: [RemyPlatform: String] = [:]
    var title = ""
    var platforms: Set<RemyPlatform> = Set(RemyPlatform.allCases)

    func text(_ platform: RemyPlatform) -> String { (own[platform] ?? caption).trimmed }
    /// The title YouTube gets: yours, or the caption's first line.
    var youTubeTitle: String { title.trimmed.isEmpty ? Remy.title(from: caption) : Remy.cleanTitle(title) }
    /// Why it can't be posted yet, or nil.
    func problem(_ connected: Set<RemyPlatform>) -> String? {
        guard video != nil else { return L("Add a video") }
        let chosen = RemyPlatform.allCases.filter(platforms.contains)
        guard !chosen.isEmpty else { return L("Tick a platform") }
        if let missing = chosen.first(where: { !connected.contains($0) }) { return L("Connect %@ under Accounts, or untick it", missing.name) }
        if let long = chosen.first(where: { Remy.over(text($0), $0) }) { return L("The %@ text is longer than %@ characters", long.name, String(long.limit)) }
        if platforms.contains(.youtube) {
            if youTubeTitle.isEmpty { return L("Give the YouTube video a title") }
            if youTubeTitle.count > 100 { return L("The YouTube title is longer than 100 characters") }
        }
        return nil
    }
}

/// Remy's desk: your developer apps and accounts (in the Keychain), the post you're making, and the posts made, kept
/// in `Studio.folder/remy/posts.json` with each one's numbers.
@MainActor
final class RemyDesk: ObservableObject {
    @Published var credentials: [RemyApp: RemyCredentials] = [:]
    @Published var accounts: [RemyPlatform: RemyAccount] = [:]
    /// The Pages a Meta sign-in found, while you pick the one to post to.
    @Published var pages: [RemyMeta.Page] = []
    @Published var draft = RemyDraft()
    @Published var posts: [RemyPost] = []
    @Published var signIn: RemySignIn?
    @Published var signingIn: RemyApp?
    @Published var failure: [RemyApp: String] = [:]
    @Published var refreshing = false
    @Published var refreshed: Date?
    @Published var reading = false
    private var loaded = false

    nonisolated static var folder: URL { Studio.folder.appendingPathComponent("remy", isDirectory: true) }
    nonisolated static var file: URL { folder.appendingPathComponent("posts.json") }

    var connected: Set<RemyPlatform> { Set(accounts.keys) }
    var busy: Bool { posts.contains { $0.targets.contains(where: \.busy) } }

    func open() {
        guard !loaded else { return }
        loaded = true
        for app in RemyApp.allCases {
            credentials[app] = RemyKeychain.read("app.\(app.rawValue)", as: RemyCredentials.self) ?? RemyCredentials(redirect: app.redirect)
        }
        for platform in RemyPlatform.allCases {
            accounts[platform] = RemyKeychain.read("account.\(platform.rawValue)", as: RemyAccount.self)
        }
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([RemyPost].self, from: data) {
            // A post the app closed on stopped where it was.
            posts = saved.map { post in
                var post = post
                for index in post.targets.indices where post.targets[index].busy {
                    post.targets[index].state = .failed
                    post.targets[index].error = L("Stopped when Edit Assist closed; check the platform before posting again")
                }
                return post
            }
        }
        refreshed = posts.flatMap(\.targets).compactMap { $0.stats?.fetched }.max()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(posts) { try? data.write(to: Self.file, options: .atomic) }
    }

    // MARK: Accounts

    func setCredentials(_ app: RemyApp, _ value: RemyCredentials) {
        credentials[app] = value
        RemyKeychain.write("app.\(app.rawValue)", value)
    }

    func startSignIn(_ app: RemyApp) {
        guard let credentials = credentials[app], credentials.ready else { return }
        failure[app] = nil
        signIn = RemyAuth.start(app, credentials)
    }

    /// The sign-in window's answer: the code made the account's tokens.
    func finishSignIn(_ request: RemySignIn, _ answer: Result<String, RemyError>?) {
        signIn = nil
        guard let answer else { return }
        let app = request.app
        guard case .success(let code) = answer else {
            if case .failure(let error) = answer { failure[app] = error.message }
            return
        }
        guard let credentials = credentials[app] else { return }
        signingIn = app
        Task {
            defer { signingIn = nil }
            do {
                switch app {
                case .meta:
                    let found = try await RemyMeta.pages(code: code, credentials)
                    if found.count == 1 { usePage(found[0]) } else { pages = found }
                case .tiktok: keep(.tiktok, try await RemyTikTok.account(code: code, credentials))
                case .google: keep(.youtube, try await RemyYouTube.account(code: code, verifier: request.verifier, credentials))
                }
            } catch {
                failure[app] = error.localizedDescription
            }
        }
    }

    /// The Page Remy posts to, and its Instagram account when one is linked.
    func usePage(_ page: RemyMeta.Page) {
        pages = []
        keep(.facebook, RemyAccount(id: page.id, name: page.name, token: page.token))
        if let id = page.instagramID {
            keep(.instagram, RemyAccount(id: id, name: page.instagramName.map { "@" + $0 } ?? id, token: page.token))
        } else {
            keep(.instagram, nil)
            failure[.meta] = L("%@ has no Instagram professional account linked; link one in the Page's settings, then sign in again", page.name)
        }
    }

    private func keep(_ platform: RemyPlatform, _ account: RemyAccount?) {
        accounts[platform] = account
        RemyKeychain.write("account.\(platform.rawValue)", account)
    }

    func signOut(_ app: RemyApp) {
        for platform in app.platforms { keep(platform, nil) }
        failure[app] = nil
        if app == .meta { pages = [] }
    }

    /// The account with a token that still works: TikTok's and YouTube's are renewed when they're about to run out.
    private func ready(_ platform: RemyPlatform) async throws -> RemyAccount {
        guard let account = accounts[platform] else { throw RemyError(L("Connect %@ under Accounts", platform.name)) }
        guard account.stale, let credentials = credentials[platform.app] else { return account }
        let renewed = platform == .tiktok ? try await RemyTikTok.refreshed(account, credentials) : try await RemyYouTube.refreshed(account, credentials)
        keep(platform, renewed)
        return renewed
    }

    // MARK: The video

    @Published var videoProblem: String?

    func useVideo(_ url: URL) {
        reading = true
        videoProblem = nil
        Task {
            defer { reading = false }
            do {
                draft.video = try await RemyVideo.read(url)
            } catch {
                draft.video = nil
                videoProblem = error.localizedDescription
            }
        }
    }

    // MARK: Posting

    /// Posts the draft to every platform ticked, side by side; the draft is cleared for the next one.
    @discardableResult
    func post() -> Bool {
        guard draft.problem(connected) == nil, let video = draft.video else { return false }
        let chosen = RemyPlatform.allCases.filter(draft.platforms.contains)
        let post = RemyPost(video: video.url.path, caption: draft.caption, title: draft.youTubeTitle,
                            targets: chosen.map { RemyTarget(platform: $0, text: draft.text($0)) })
        posts.insert(post, at: 0)
        save()
        draft = RemyDraft(platforms: draft.platforms)
        for platform in chosen { send(post.id, platform, video) }
        return true
    }

    /// Posts it again where it failed.
    func retry(_ id: UUID, _ platform: RemyPlatform) {
        guard let post = posts.first(where: { $0.id == id }) else { return }
        Task {
            do {
                send(id, platform, try await RemyVideo.read(URL(fileURLWithPath: post.video)))
            } catch {
                change(id, platform) { $0.error = error.localizedDescription }
            }
        }
    }

    private func send(_ id: UUID, _ platform: RemyPlatform, _ video: RemyVideo) {
        change(id, platform) { $0.state = .uploading; $0.progress = 0; $0.error = nil; $0.note = nil }
        guard let post = posts.first(where: { $0.id == id }), let target = post.targets.first(where: { $0.platform == platform }) else { return }
        var shown = -1
        let step: (RemyStep) -> Void = { [weak self] step in
            Task { @MainActor in
                switch step {
                case .uploading(let part):
                    // A change a percent at a time: the page isn't redrawn for every packet.
                    let percent = Int(part * 100)
                    guard percent != shown else { return }
                    shown = percent
                    self?.change(id, platform) { $0.state = .uploading; $0.progress = part }
                case .processing: self?.change(id, platform) { $0.state = .processing; $0.progress = 1 }
                }
            }
        }
        Task {
            do {
                let account = try await ready(platform)
                let published: RemyPublished
                switch platform {
                case .facebook: published = try await RemyMeta.postToPage(video, text: target.text, page: account, step: step)
                case .instagram: published = try await RemyMeta.postToInstagram(video, text: target.text, account: account, step: step)
                case .tiktok: published = try await RemyTikTok.post(video, text: target.text, account: account, step: step)
                case .youtube: published = try await RemyYouTube.post(video, title: post.title, text: target.text, account: account, step: step)
                }
                change(id, platform) {
                    $0.state = .posted
                    $0.remoteID = published.id
                    $0.url = published.url
                    $0.kind = published.kind
                    $0.note = published.note
                }
            } catch {
                change(id, platform) { $0.state = .failed; $0.error = error.localizedDescription }
            }
            save()
        }
    }

    private func change(_ id: UUID, _ platform: RemyPlatform, _ edit: (inout RemyTarget) -> Void) {
        guard let post = posts.firstIndex(where: { $0.id == id }), let target = posts[post].targets.firstIndex(where: { $0.platform == platform }) else { return }
        edit(&posts[post].targets[target])
    }

    /// Forgets a post here; it stays on the platforms.
    func forget(_ id: UUID) {
        posts.removeAll { $0.id == id }
        save()
    }

    // MARK: Numbers

    /// Each posted video's numbers, fetched again; a platform that won't say leaves the last ones.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false; refreshed = Date(); save() }
            var found: [RemyPlatform: [String: RemyStats]] = [:]
            for platform in RemyPlatform.allCases {
                let posted = posts.flatMap(\.targets).filter { $0.platform == platform && $0.state == .posted && $0.kind != "private" }
                let ids = posted.compactMap(\.remoteID)
                guard !ids.isEmpty, let account = try? await ready(platform) else { continue }
                switch platform {
                case .facebook:
                    for target in posted { if let id = target.remoteID { found[platform, default: [:]][id] = await RemyMeta.pageStats(id, kind: target.kind, token: account.token) } }
                case .instagram:
                    for id in ids { found[platform, default: [:]][id] = await RemyMeta.instagramStats(id, token: account.token) }
                case .tiktok: found[platform] = (try? await RemyTikTok.stats(ids, account: account)) ?? [:]
                case .youtube: found[platform] = (try? await RemyYouTube.stats(ids, account: account)) ?? [:]
                }
            }
            for post in posts.indices {
                for target in posts[post].targets.indices {
                    let item = posts[post].targets[target]
                    guard let id = item.remoteID, let stats = found[item.platform]?[id] else { continue }
                    posts[post].targets[target].stats = stats
                    if let url = stats.url, item.url == nil { posts[post].targets[target].url = url }
                }
            }
        }
    }

    /// Fetched again when the numbers are more than half an hour old (or never fetched) and there's something to fetch.
    func refreshIfOld() {
        guard posts.contains(where: { $0.targets.contains { $0.state == .posted } }) else { return }
        if (refreshed.map { Date().timeIntervalSince($0) > 1800 } ?? true) { refresh() }
    }

    /// The totals per platform, over every post.
    func totals(_ platform: RemyPlatform) -> (posts: Int, views: Int, likes: Int, comments: Int, shares: Int) {
        let posted = posts.flatMap(\.targets).filter { $0.platform == platform && $0.state == .posted }
        let stats = posted.compactMap(\.stats)
        return (posted.count, stats.compactMap(\.views).reduce(0, +), stats.compactMap(\.likes).reduce(0, +),
                stats.compactMap(\.comments).reduce(0, +), stats.compactMap(\.shares).reduce(0, +))
    }
}
