import AppKit
import SwiftUI

// Sage's research page parts brought back from Creative Assist (2026-11-09): Pick's live steps and its judgement, a video's
// picture that plays it here, the mini player's box, the line between two columns, and the page's motion (cards fade and
// slide in once, lift under the mouse; none of the movement when Reduce Motion is on).

extension Study.Says {
    /// In the app's language.
    var shown: String { text { L($0) } }
}

// MARK: Motion

/// Fades and slides a card in the first time it shows (under `key`), not on every redraw.
private struct SageEnter: ViewModifier {
    let key: String
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool
    /// Cards already shown once, so a redraw (or scrolling back to one) doesn't replay the motion.
    static var entered: Set<String> = []

    init(key: String, index: Int) {
        self.key = key; self.index = index
        _shown = State(initialValue: Self.entered.contains(key))
    }

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                Self.entered.insert(key)
                if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.25).delay(Double(min(index, 8)) * 0.035)) { shown = true } }
            }
    }
}

/// Lifts a card a little under the mouse, with a lighter background when it has one.
private struct SageLift: ViewModifier {
    let fill: Color?
    let corner: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .background(hover ? fill ?? .clear : .clear, in: RoundedRectangle(cornerRadius: corner))
            .offset(y: hover ? -3 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    func sageEnter(_ key: String, index: Int = 0) -> some View { modifier(SageEnter(key: key, index: index)) }
    func sageLift(_ fill: Color? = nil, corner: CGFloat = 10) -> some View { modifier(SageLift(fill: fill, corner: corner)) }
}

// MARK: Playing a video here

/// A video's picture that plays it here in one press: a play button shows on hover; the one playing keeps its mark.
/// Dragging the card still saves it.
struct SagePlayable<Picture: View>: View {
    @ObservedObject var desk: SageDesk
    let video: Study.Video
    var glyph: CGFloat = 16
    let accent: Color
    @ViewBuilder var picture: Picture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        let playing = desk.playing?.id == video.id
        picture
            .overlay {
                Button { desk.play(video) } label: {
                    Image(systemName: playing ? "speaker.wave.2.fill" : "play.fill").font(.system(size: glyph, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: glyph * 2.3, height: glyph * 2.3)
                        .background(playing ? accent.opacity(0.92) : .black.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(playing || hover ? 1 : 0)
                .help(playing ? L("Playing here") : L("Play it here"))
                .accessibilityLabel(L("Play “%@” here", video.title))
            }
            .contentShape(Rectangle())
            .onTapGesture { desk.play(video) }
            .onHover { hover = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hover)
    }
}

/// The mini player: its bar (the video's title and channel; Save, Write, open on YouTube, expand or dock, close) over
/// YouTube's own player. Docked it is 400 pt wide, 16:9 under its bar, and grows up from its bar when it opens.
struct SagePlayerBox: View {
    @ObservedObject var desk: SageDesk
    let video: Study.Video
    let accent: Color
    static let dockedWidth: CGFloat = 400, headHeight: CGFloat = 46
    static var dockedHeight: CGFloat { headHeight + dockedWidth * 9 / 16 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let large = desk.playerExpanded
        VStack(spacing: 0) {
            head.frame(height: Self.headHeight)
            SagePlayerWeb(id: video.id).background(Color.black)
        }
        .frame(width: large ? nil : Self.dockedWidth, height: large ? nil : grown ? Self.dockedHeight : Self.headHeight)
        .frame(maxWidth: large ? .infinity : nil, maxHeight: large ? .infinity : nil)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.45)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: large)
        .onAppear { if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.22)) { grown = true } } }
    }

    var head: some View {
        let recipes = desk.topic.kind == .recipes
        let saved = desk.savedHere.first { $0.id == video.id }
        let large = desk.playerExpanded
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(video.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).help(video.title)
                Text([video.channel, video.duration].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if desk.sources.contains(video.url.absoluteString) {
                Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 10.5)).foregroundStyle(accent)
            } else if desk.writing.contains(video.id) {
                Text(L("Writing…")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            } else {
                if saved == nil {
                    Button { desk.save(video) } label: { Label(L("Save"), systemImage: "bookmark") }.controlSize(.small).help(L("Keep it in Saved to review"))
                } else {
                    Label(L("Saved"), systemImage: "bookmark.fill").font(.system(size: 10.5)).foregroundStyle(accent)
                }
                Button { if let saved { desk.write(saved) } else { desk.write(video) } } label: { Label(recipes ? L("Write recipe") : L("Write note"), systemImage: "square.and.pencil") }
                    .controlSize(.small).help(L("Write its note into the topic's folder now"))
            }
            Group {
                Button { NSWorkspace.shared.open(video.url) } label: { Image(systemName: "arrow.up.right.square") }.help(L("Open on YouTube"))
                Button { desk.playerExpanded.toggle() } label: { Image(systemName: large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(large ? L("Dock the player") : L("Expand the player"))
                Button { desk.closePlayer() } label: { Image(systemName: "xmark") }.help(L("Close the player"))
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .padding(.leading, 10).padding(.trailing, 8)
    }
}

// MARK: Columns

/// The line between two columns: drag it to size them (live). Thin and hidden until the mouse is over it.
struct SageColumnLine: View {
    /// While dragging, how far (points, + to the right) since the drag began; nil when it ends.
    let dragged: (CGFloat?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var dragging = false

    var body: some View {
        Color.clear.frame(width: 14).frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 1).fill(Color.secondary).frame(width: 2).opacity(dragging ? 1 : hover ? 0.55 : 0))
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { dragging = true; dragged($0.translation.width) }
                .onEnded { _ in dragging = false; dragged(nil) })
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hover)
            .accessibilityLabel(L("Drag to resize the columns"))
    }
}

// MARK: Pick for me: its live steps and its judgement

/// Pick's steps as they happen: the ones done ticked, the one it's on with Sage writing.
struct SagePickSteps: View {
    let steps: [String]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let done = index < steps.count - 1
                HStack(spacing: 6) {
                    Group {
                        if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent) }
                        else { PixelSage(pixel: 1, busyUntil: .distantFuture) }
                    }.frame(width: 18)
                    Text(step).font(.system(size: 11.5, weight: done ? .regular : .semibold)).foregroundStyle(done ? .secondary : .primary)
                }
                .sageEnter("step:\(index):\(step)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// What Pick decided, so you can see his judgement: "Saved 2 of 31 looked at", the searches, the picks with why, and
/// (folded) everything passed over with why not, each savable anyway.
struct SagePickOutcome<Card: View>: View {
    @ObservedObject var desk: SageDesk
    let outcome: Study.PickOutcome
    let accent: Color
    /// A pick's card, as Find draws one, with its why and score.
    let card: (Study.Chosen) -> Card
    @State private var passedOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(L("Saved %@ of %@ looked at", outcome.picked.count, outcome.lookedAt), systemImage: outcome.picked.isEmpty ? "info.circle" : "checkmark.circle.fill")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(outcome.picked.isEmpty ? Color.primary : accent)
                Spacer()
                Button { desk.clearPick() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(L("Close and show search results"))
            }
            if !outcome.searches.isEmpty {
                Text(L("Searched %@. Kept only what scored %@/100 or more on relevance, substance, credibility and density; one per channel.",
                       outcome.searches.map { "“\($0)”" }.joined(separator: " · "), Int(Study.Rubric.bar)))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let why = outcome.why {
                Text(why.shown).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 10) {
                    ForEach(Array(outcome.picked.enumerated()), id: \.element.video.id) { index, chosen in
                        card(chosen).sageEnter("pick:\(outcome.id):\(chosen.video.id)", index: index)
                    }
                }.padding(.top, 4)
            }
            if !outcome.passedOver.isEmpty {
                Button { passedOpen.toggle() } label: {
                    Label(L("Passed over (%@)", outcome.passedOver.count), systemImage: passedOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(passedOpen ? L("Hide what Sage passed over") : L("Show what Sage passed over, and why"))
                if passedOpen {
                    VStack(spacing: 4) {
                        ForEach(Array(outcome.passedOver.enumerated()), id: \.element.video.id) { index, passed in
                            row(passed).sageEnter("passed:\(outcome.id):\(passed.video.id)", index: index)
                        }
                    }
                }
            }
        }
    }

    /// A video Pick passed over: why not, its score when it had one, and Save anyway.
    func row(_ passed: Study.Passed) -> some View {
        let video = passed.video
        let facts = [video.channel, video.duration, video.views.map { L("%@ views", $0.formatted(.number.notation(.compactName))) } ?? "",
                     passed.score.map { "\(Int($0))/100" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 8) {
            SagePlayable(desk: desk, video: video, glyph: 10, accent: accent) {
                AsyncImage(url: video.thumbnail) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                    .frame(width: 72, height: 40.5).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 11, weight: .medium)).lineLimit(1).help(video.title)
                Text(facts).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                Text(passed.reason.shown).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if desk.sources.contains(video.url.absoluteString) {
                Label(L("In your vault"), systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(accent)
            } else if desk.savedHere.contains(where: { $0.id == video.id }) {
                Label(L("Saved"), systemImage: "bookmark.fill").font(.system(size: 10)).foregroundStyle(accent)
            } else {
                Button { desk.save(video) } label: { Label(L("Save anyway"), systemImage: "bookmark") }.controlSize(.small).help(L("Overrule Sage and keep it in Saved"))
            }
        }
        .padding(6)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
        .sageLift(.white.opacity(0.07), corner: 7)
        .contentShape(Rectangle())
        .draggable(video.id) {
            Text(video.title).font(.system(size: 11)).lineLimit(1).padding(6).background(accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
