import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Remy, the publisher: a coral blob of a courier in a navy cap with a gold badge, a satchel across him with letters
/// poking out (2026-11-12, you asked). Working: a letter pops up out of the satchel and flies off.
struct PixelRemy: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 240 / 255, green: 110 / 255, blue: 95 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["....CCCCCC......", "...CCCCCCCyC....", "..cccccccccc....", "...OOOOOOOO.....", "...OOKOOKOO.....",
                       "...OOKOOKOO.....", "...OOOkkOOO.....", "...sOOOOOOO.WW..", "...OsOOOOOOWWrW.", "...OOsOOOBBBBBB.",
                       "...OOOsOOBBbBBB.", "...OOOOsOBBBBBB.", "....OOOOsBBBBBB.", ".....D...D......"]
    static let blink = ["....CCCCCC......", "...CCCCCCCyC....", "..cccccccccc....", "...OOOOOOOO.....", "...OOOOOOOO.....",
                        "...OOKOOKOO.....", "...OOOkkOOO.....", "...sOOOOOOO.WW..", "...OsOOOOOOWWrW.", "...OOsOOOBBBBBB.",
                        "...OOOsOOBBbBBB.", "...OOOOsOBBBBBB.", "....OOOOsBBBBBB.", ".....D...D......"]
    static let working: [[String]] = [
        rest,
        ["....CCCCCC......", "...CCCCCCCyC....", "..cccccccccc....", "...OOOOOOOO.....", "...OOKOOKOO.....",
         "...OOKOOKOO.....", "...OOOkkOOO.WW..", "...sOOOOOOOWWrW.", "...OsOOOOOOWWWW.", "...OOsOOOBBBBBB.",
         "...OOOsOOBBbBBB.", "...OOOOsOBBBBBB.", "....OOOOsBBBBBB.", ".....D...D......"],
        ["....CCCCCC......", "...CCCCCCCyC..WW", "..cccccccccc..Wr", "...OOOOOOOO.....", "...OOKOOKOO.....",
         "...OOKOOKOO.....", "...OOOkkOOO.....", "...sOOOOOOO.W...", "...OsOOOOOOWWW..", "...OOsOOOBBBBBB.",
         "...OOOsOOBBbBBB.", "...OOOOsOBBBBBB.", "....OOOOsBBBBBB.", ".....D...D......"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Self.theme, "C": Color(red: 50 / 255, green: 70 / 255, blue: 125 / 255), "c": Color(red: 30 / 255, green: 40 / 255, blue: 75 / 255),
                                "y": Color(red: 1, green: 214 / 255, blue: 80 / 255), "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255),
                                "k": Color(red: 120 / 255, green: 40 / 255, blue: 35 / 255), "s": Color(red: 110 / 255, green: 70 / 255, blue: 40 / 255),
                                "B": Color(red: 160 / 255, green: 105 / 255, blue: 55 / 255), "b": Color(red: 1, green: 214 / 255, blue: 80 / 255),
                                "W": Color(red: 245 / 255, green: 240 / 255, blue: 225 / 255), "r": Color(red: 225 / 255, green: 60 / 255, blue: 60 / 255),
                                "D": Color(red: 150 / 255, green: 60 / 255, blue: 55 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Remy")
    }
}

/// Remy in the sidebar, at work while a post goes up or the numbers come in.
struct RemyIcon: View {
    @ObservedObject var desk: RemyDesk
    var body: some View { PixelRemy(pixel: 1.25, busyUntil: desk.busy || desk.refreshing ? .distantFuture : nil) }
}

/// Remy's page: Post (one video to the platforms you tick), Posts (what went up, and how), Analytics (each post's
/// numbers) and Accounts (your developer apps and sign-ins).
struct RemyPage: View {
    @ObservedObject var desk: RemyDesk
    @AppStorage("remyTab") private var tab = "post"

    var body: some View {
        ThinScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    PixelRemy(pixel: 4, busyUntil: desk.busy || desk.refreshing ? .distantFuture : nil, previewOnHover: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(md: L("Your publisher")).font(.system(size: 13, weight: .semibold))
                        Bullets(["Posts **one video** to **Facebook**, **Instagram**, **TikTok** and **YouTube** in one go",
                                 "One caption, which each platform can take **in its own words**",
                                 "Keeps what went up, and each post's **views, likes and comments**"], size: 11)
                    }
                }
                Picker("", selection: $tab) {
                    Text(L("Post")).tag("post")
                    Text(L("Posts")).tag("posts")
                    Text(L("Analytics")).tag("analytics")
                    Text(L("Accounts")).tag("accounts")
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                switch tab {
                case "posts": RemyPostsView(desk: desk)
                case "analytics": RemyAnalyticsView(desk: desk)
                case "accounts": RemyAccountsView(desk: desk)
                default: RemyComposeView(desk: desk) { tab = "posts" }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .onAppear { desk.open() }
        .sheet(item: $desk.signIn) { request in
            RemySignInSheet(request: request) { desk.finishSignIn(request, $0) }
        }
    }
}

/// A titled box, as on Penny's page.
struct RemySection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

enum RemyStyle {
    static func color(_ platform: RemyPlatform) -> Color {
        switch platform {
        case .facebook: Color(red: 90 / 255, green: 140 / 255, blue: 240 / 255)
        case .instagram: Color(red: 225 / 255, green: 110 / 255, blue: 175 / 255)
        case .tiktok: Color(red: 45 / 255, green: 200 / 255, blue: 200 / 255)
        case .youtube: Color(red: 240 / 255, green: 80 / 255, blue: 75 / 255)
        }
    }
    static func symbol(_ platform: RemyPlatform) -> String {
        switch platform { case .facebook: "f.circle.fill"; case .instagram: "camera.circle.fill"; case .tiktok: "music.note"; case .youtube: "play.rectangle.fill" }
    }
    static func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return whole >= 60 ? String(format: "%d:%02d", whole / 60, whole % 60) : "\(whole) s"
    }
    static func number(_ value: Int?) -> String {
        guard let value else { return "–" }
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return value.formatted()
        }
    }
    static func counter(_ count: Int, _ limit: Int) -> some View {
        Text("\(count) / \(limit)").font(.system(size: 10).monospacedDigit()).foregroundStyle(count > limit ? Color.orange : .secondary)
    }
    static func editor(_ text: Binding<String>, _ prompt: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text).font(.system(size: 12)).scrollContentBackground(.hidden).padding(6)
            if text.wrappedValue.isEmpty {
                Text(prompt).font(.system(size: 12)).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.08)))
    }
}

// MARK: - Post

struct RemyComposeView: View {
    @ObservedObject var desk: RemyDesk
    let posted: () -> Void
    @State private var targeted = false

    var body: some View {
        RemySection(title: L("VIDEO")) { video }
        RemySection(title: L("CAPTION")) {
            RemyStyle.editor($desk.draft.caption, L("What the post says, with its hashtags"), height: 110)
            HStack {
                Text(md: L("Every platform takes this, unless you give it its own below.")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                RemyStyle.counter(desk.draft.caption.count, 2_200)
            }
        }
        RemySection(title: L("PLATFORMS")) {
            ForEach(RemyPlatform.allCases) { platform in
                RemyPlatformRow(desk: desk, platform: platform)
                if platform != .youtube { Divider().opacity(0.4) }
            }
        }
        HStack(spacing: 10) {
            let problem = desk.draft.problem(desk.connected)
            let count = desk.draft.platforms.count
            Button {
                if desk.post() { posted() }
            } label: {
                Label(count == 1 ? L("Post to 1 platform") : L("Post to %@ platforms", String(count)), systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent).tint(PixelRemy.theme).controlSize(.large).disabled(problem != nil)
            if let problem { Text(problem).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder var video: some View {
        if let video = desk.draft.video {
            HStack(alignment: .top, spacing: 14) {
                RemyPlayer(url: video.url)
                    .frame(width: video.vertical ? 150 : 260, height: video.vertical ? 266 : 146)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .id(video.url)
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text("\(RemyStyle.duration(video.seconds)) · \(Int(video.width))×\(Int(video.height)) · \(ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file))")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    ForEach(Remy.notes(video, RemyPlatform.allCases.filter(desk.draft.platforms.contains)), id: \.self) { note in
                        Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button(L("Choose another…")) { choose() }
                        Button(L("Remove")) { desk.draft.video = nil }
                    }.controlSize(.small).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "film").font(.system(size: 26)).foregroundStyle(targeted ? PixelRemy.theme : .secondary)
                Text(md: L("Drop a video here")).font(.system(size: 12))
                if desk.reading { ProgressView().controlSize(.small) } else { Button(L("Add video…")) { choose() }.controlSize(.small) }
                if let problem = desk.videoProblem { Text(problem).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(targeted ? PixelRemy.theme : .white.opacity(0.15)))
            .contentShape(Rectangle())
            .kinoDrop($targeted) { urls in if let url = urls.first { desk.useVideo(url) } }
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { desk.useVideo(url) }
    }
}

/// The video, to watch before it goes; one player for as long as it's shown.
struct RemyPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player).onAppear { if player == nil { player = AVPlayer(url: url) } }.onDisappear { player?.pause() }
    }
}

/// A platform in the post: ticked or not, the account it goes to, and its own words if you give it some.
struct RemyPlatformRow: View {
    @ObservedObject var desk: RemyDesk
    let platform: RemyPlatform

    var body: some View {
        let on = desk.draft.platforms.contains(platform)
        let own = desk.draft.own[platform]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { on }, set: { if $0 { desk.draft.platforms.insert(platform) } else { desk.draft.platforms.remove(platform) } })) {
                    Label(platform.name, systemImage: RemyStyle.symbol(platform)).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? RemyStyle.color(platform) : .secondary)
                }.toggleStyle(.checkbox)
                if let account = desk.accounts[platform] {
                    Text(account.name).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text(L("not connected")).font(.system(size: 11)).foregroundStyle(.orange)
                }
                Spacer()
                if on {
                    if own == nil {
                        Button(L("Own words")) { desk.draft.own[platform] = desk.draft.caption }.controlSize(.small)
                            .help(L("Give %@ its own text, starting from the caption", platform.name))
                    } else {
                        Button(L("Use the caption")) { desk.draft.own[platform] = nil }.controlSize(.small)
                    }
                    RemyStyle.counter(desk.draft.text(platform).count, platform.limit)
                }
            }
            if on, platform == .youtube {
                HStack(spacing: 8) {
                    TextField(L("Title"), text: $desk.draft.title, prompt: Text(Remy.title(from: desk.draft.caption).isEmpty ? L("Title") : Remy.title(from: desk.draft.caption)))
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    RemyStyle.counter(desk.draft.youTubeTitle.count, 100)
                }
            }
            if on, own != nil {
                RemyStyle.editor(Binding(get: { desk.draft.own[platform] ?? "" }, set: { desk.draft.own[platform] = $0 }),
                                 L("%@'s own text", platform.name), height: 80)
            }
        }
    }
}

// MARK: - Posts

struct RemyPostsView: View {
    @ObservedObject var desk: RemyDesk
    var body: some View {
        if desk.posts.isEmpty {
            Text(md: L("Nothing posted yet. Posts you make under **Post** show here, with how each platform took them."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ForEach(desk.posts) { post in
            RemyPostCard(desk: desk, post: post)
        }
    }
}

struct RemyPostCard: View {
    @ObservedObject var desk: RemyDesk
    let post: RemyPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemyThumb(path: post.video)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(post.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11, weight: .medium))
                    Text(post.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Menu {
                        Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: post.video)]) }
                        Button(L("Forget this post"), role: .destructive) { desk.forget(post.id) }.disabled(post.targets.contains(where: \.busy))
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                }
                if !post.caption.isEmpty {
                    Text(post.caption).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(post.targets) { target in
                    RemyTargetRow(desk: desk, post: post.id, target: target)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct RemyTargetRow: View {
    @ObservedObject var desk: RemyDesk
    let post: UUID
    let target: RemyTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label(target.platform.name, systemImage: RemyStyle.symbol(target.platform)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RemyStyle.color(target.platform)).frame(width: 96, alignment: .leading)
                switch target.state {
                case .waiting, .uploading:
                    ProgressView(value: target.progress).frame(maxWidth: 180)
                    Text(L("Uploading %@%", String(Int(target.progress * 100)))).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                case .processing:
                    ProgressView().controlSize(.small)
                    Text(L("%@ is working on it…", target.platform.name)).font(.system(size: 11)).foregroundStyle(.secondary)
                case .posted:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    if let link = target.url.flatMap(URL.init) { Link(L("Open"), destination: link).font(.system(size: 11)) } else { Text(L("Posted")).font(.system(size: 11)) }
                    if let stats = target.stats {
                        Text("\(RemyStyle.number(stats.views)) \(L("views")) · \(RemyStyle.number(stats.likes)) \(L("likes"))")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button(L("Try again")) { desk.retry(post, target.platform) }.controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            if let error = target.error, target.state == .failed {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).padding(.leading, 104)
            }
            if let note = target.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 104)
            }
        }
    }
}

/// A frame from the video, a second in.
struct RemyThumb: View {
    let path: String
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3))
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "film").foregroundStyle(.secondary) }
        }
        .frame(width: 54, height: 96).clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: path) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 220, height: 220)
            if let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image {
                image = NSImage(cgImage: frame, size: .zero)
            }
        }
    }
}

// MARK: - Analytics

struct RemyAnalyticsView: View {
    @ObservedObject var desk: RemyDesk

    var body: some View {
        HStack(spacing: 10) {
            if let refreshed = desk.refreshed {
                Text(L("Numbers from %@", refreshed.formatted(date: .omitted, time: .shortened))).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if desk.refreshing { ProgressView().controlSize(.small) }
            Button { desk.refresh() } label: { Label(L("Update now"), systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered).controlSize(.small).disabled(desk.refreshing)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            ForEach(RemyPlatform.allCases) { platform in tile(platform) }
        }
        let posted = desk.posts.filter { $0.targets.contains { $0.state == .posted } }
        RemySection(title: L("EACH POST"), trailing: L("views · likes · comments")) {
            if posted.isEmpty {
                Text(L("Nothing posted yet.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(posted) { post in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? post.name).font(.system(size: 12)).lineLimit(1)
                        Text(post.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                    ForEach(post.targets.filter { $0.state == .posted }) { target in
                        HStack(spacing: 4) {
                            Image(systemName: RemyStyle.symbol(target.platform)).foregroundStyle(RemyStyle.color(target.platform))
                            Text([target.stats?.views, target.stats?.likes, target.stats?.comments].map(RemyStyle.number).joined(separator: " · "))
                                .font(.system(size: 11).monospacedDigit())
                        }
                        .help(target.platform.name)
                    }
                }
                if post.id != posted.last?.id { Divider().opacity(0.4) }
            }
        }
        .onAppear { desk.refreshIfOld() }
    }

    func tile(_ platform: RemyPlatform) -> some View {
        let total = desk.totals(platform)
        return VStack(alignment: .leading, spacing: 6) {
            Label(platform.name, systemImage: RemyStyle.symbol(platform)).font(.system(size: 11, weight: .semibold)).foregroundStyle(RemyStyle.color(platform))
            Text(RemyStyle.number(total.posts == 0 ? nil : total.views)).font(.system(size: 22, weight: .semibold).monospacedDigit())
            Text(L("views")).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("\(total.posts) \(L("posts")) · \(RemyStyle.number(total.likes)) \(L("likes")) · \(RemyStyle.number(total.comments)) \(L("comments"))"
                 + (platform == .youtube ? "" : " · \(RemyStyle.number(total.shares)) \(L("shares"))"))
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RemyStyle.color(platform).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Accounts

struct RemyAccountsView: View {
    @ObservedObject var desk: RemyDesk
    var body: some View {
        Text(md: L("Each platform posts through a **developer app you register** once. Each box says where to click and what to paste; the ID and secret stay in your Mac's **Keychain**."))
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        ForEach(RemyApp.allCases) { app in RemyAppCard(desk: desk, app: app) }
    }
}

struct RemyAppCard: View {
    @ObservedObject var desk: RemyDesk
    let app: RemyApp
    @State private var editing = RemyCredentials()
    @State private var showSteps = false

    var steps: [String] {
        switch app {
        case .meta:
            return [L("At **developers.facebook.com/apps**, **Create app** (type **Business**), with the use cases to manage your **Page** and **Instagram** content"),
                    L("Under **Facebook Login for Business → Settings**, add the redirect below to **Valid OAuth Redirect URIs**"),
                    L("In **App settings → Basic**, copy the **App ID** and **App secret** here"),
                    L("While the app is in development only you (its admin) can use it, which is all Remy needs; if your posts show only to you, switch it to **Live**"),
                    L("Your Instagram must be a **professional account linked to the Page**")]
        case .tiktok:
            return [L("At **developers.tiktok.com**, **Manage apps → Connect an app**"),
                    L("Add **Login Kit** and **Content Posting API** (turn on **Direct Post**), with the scopes user.info.basic, video.upload, video.publish and video.list"),
                    L("Under Login Kit, add the redirect below (TikTok wants an https address; any you own works, Remy stops there before it loads)"),
                    L("Copy the **Client key** and **Client secret** here"),
                    L("Until TikTok **audits** the app, it may only post as **private**: Remy posts it so and says so, and you make it public in TikTok")]
        case .google:
            return [L("At **console.cloud.google.com**, make a project and turn on **YouTube Data API v3**"),
                    L("Set up the **OAuth consent screen** (External) and add your Google account as a **test user**; **publish** it, or Google asks you to sign in again every 7 days"),
                    L("Under **Credentials**, **Create OAuth client ID** of type **Desktop app**, and copy its **Client ID** and **Client secret** here"),
                    L("Until Google **audits** the project, YouTube keeps its uploads **private**; you can make them public in YouTube Studio")]
        }
    }

    var body: some View {
        let saved = desk.credentials[app] ?? RemyCredentials(redirect: app.redirect)
        let accounts = app.platforms.compactMap { platform in desk.accounts[platform].map { (platform, $0) } }
        RemySection(title: app.name.uppercased(), trailing: app.platforms.map(\.name).joined(separator: " · ")) {
            if !accounts.isEmpty {
                ForEach(accounts, id: \.0) { platform, account in
                    Label { Text(md: L("%@: **%@**", platform.name, account.name)).font(.system(size: 12)) } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            if app == .meta, !desk.pages.isEmpty {
                Text(L("Which Page does Remy post to?")).font(.system(size: 12, weight: .medium))
                ForEach(desk.pages) { page in
                    Button { desk.usePage(page) } label: {
                        Text(page.name + (page.instagramName.map { "  ·  @" + $0 } ?? ""))
                    }.controlSize(.small)
                }
            }
            if let failure = desk.failure[app] {
                Label(failure, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            DisclosureGroup(isExpanded: Binding(get: { showSteps || !saved.ready }, set: { showSteps = $0 })) {
                VStack(alignment: .leading, spacing: 8) {
                    Bullets(steps, numbered: true, size: 11)
                    Link(L("Open %@'s developer site", app.name), destination: app.console).font(.system(size: 11))
                    field(app == .tiktok ? L("Client key") : app == .google ? L("Client ID") : L("App ID"), $editing.id, secret: false)
                    field(app == .meta ? L("App secret") : L("Client secret"), $editing.secret, secret: true)
                    field(L("Redirect"), $editing.redirect, secret: false)
                    HStack(spacing: 8) {
                        Button(L("Save")) { desk.setCredentials(app, editing) }.disabled(editing == saved || !editing.ready)
                        if editing.redirect != app.redirect { Button(L("Default redirect")) { editing.redirect = app.redirect } }
                    }.controlSize(.small)
                }.padding(.top, 6)
            } label: {
                Text(saved.ready ? L("Your developer app") : L("Set up your developer app")).font(.system(size: 12))
            }
            HStack(spacing: 8) {
                if desk.signingIn == app {
                    ProgressView().controlSize(.small)
                    Text(L("Signing in…")).font(.system(size: 11))
                } else {
                    Button(accounts.isEmpty ? L("Sign in to %@", app.name) : L("Sign in again")) { desk.startSignIn(app) }.disabled(!saved.ready)
                    if !accounts.isEmpty { Button(L("Sign out"), role: .destructive) { desk.signOut(app) } }
                }
            }.controlSize(.small)
        }
        .onAppear { editing = saved }
        .onChange(of: saved) { _, value in editing = value }
    }

    func field(_ label: String, _ text: Binding<String>, secret: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Group {
                if secret { SecureField("", text: text) } else { TextField("", text: text) }
            }.textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - Sign-in window

/// The platform's own sign-in page; Remy stops it at the redirect and takes the code. A store that keeps nothing.
struct RemySignInSheet: View {
    let request: RemySignIn
    let done: (Result<String, RemyError>?) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(md: L("Sign in to **%@**", request.app.name)).font(.system(size: 12))
                Spacer()
                Button(L("Cancel")) { done(nil) }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            RemySignInWeb(request: request, done: done)
        }.frame(width: 560, height: 700)
    }
}

struct RemySignInWeb: NSViewRepresentable {
    let request: RemySignIn
    let done: (Result<String, RemyError>?) -> Void
    func makeCoordinator() -> RemySignInCoordinator { RemySignInCoordinator(request: request, done: done) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 650), configuration: configuration)
        // Google turns away sign-ins from pages it takes for an app's web view; Safari's own name gets the normal page.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: request.url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

@MainActor
final class RemySignInCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let request: RemySignIn
    private let done: (Result<String, RemyError>?) -> Void
    private var finished = false
    init(request: RemySignIn, done: @escaping (Result<String, RemyError>?) -> Void) { self.request = request; self.done = done }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let answer = RemyAuth.answer(url, request) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        guard !finished else { return }
        finished = true
        done(answer)
    }

    /// A link that would open a new window opens here.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(action.request)
        return nil
    }
}
