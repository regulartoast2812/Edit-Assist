import SwiftUI

// A guided tour of a function: the window dims, the control being explained is cut out of the dim and outlined,
// and a popup with an arrow points at it. Started from Guide in the sidebar. The steps point at the real controls,
// marked with .guideTarget("id"); a step whose control is not on screen is skipped.

struct GuideStep {
    var target: String
    var title: String
    /// One short line under the title, optional.
    var lead: String = ""
    /// The points, one idea each; **bold** marks the key words.
    var points: [String] = []
    /// A tip at the end, optional.
    var tip: String = ""
}

enum Guide {
    static func steps(for function: EditFunction) -> [GuideStep] {
        // No numbers in the titles: the popup counts the steps.
        var steps = [
            GuideStep(target: "project", title: "Your script",
                      points: ["Click your **project**", "**Paste formatted text** from your script", "**Bold** becomes the phrases to highlight, shown in **green**"],
                      tip: "Select words and press **⌘B** to mark more."),
            GuideStep(target: "editor", title: "Premiere's panels",
                      lead: "Keep these visible in Premiere's main window:",
                      points: ["**Program Monitor**: the captions are read and clicked here", "**Timeline**: the playhead steps clip by clip", "**Properties**, with its tab **in front**"],
                      tip: "Resize and arrange them freely; don't close them or make them float. Premiere **2025 or later**, in **English**."),
            GuideStep(target: "function", title: "This function",
                      points: ["Pick the function here", "Its page shows the **phrases still to do**", "and **how they will be styled**"]),
            GuideStep(target: "apply", title: "What each phrase gets",
                      points: ["**Apply**: Style & size, Style only or Size only", "**Style**: the tile you click in Premiere's style browser on the first phrase", "**Keep style**: reuse it on the next run", "**Font size step**: how much the size grows; **0** leaves it"]),
            GuideStep(target: "todo", title: "Progress",
                      points: ["Every phrase and **how much is done**", "**Redo** clears one phrase", "**Reset progress** clears all"]),
        ]
        if function == .highlightGraphics {
            steps.append(GuideStep(target: "run", title: "Before you run",
                                   lead: "Graphic text sits on a **video track**.",
                                   points: ["If the **caption track** shows the same words on top, **hide it** (its eye icon in the timeline)", "Then clicks land on the **graphics**"]))
        }
        steps += [
            GuideStep(target: "run", title: "Run",
                      points: ["In Premiere, put the **playhead before the first caption**", "Press **Run**", "**Let go of the mouse** while it works", "The first time, **click your style** when it asks"],
                      tip: "Moving the mouse **pauses**; **Escape** stops."),
            GuideStep(target: "detection", title: "Seeing what it sees",
                      points: ["**During runs**: boxes over what the bot reads while it works", "**Off**: no boxes", "**Always**: boxes all the time"]),
            GuideStep(target: "log", title: "If something goes wrong",
                      points: ["Open **Log**", "Click **Show log file**: you get **one zip**", "Drag it into your chat and **send it to the developer**"]),
        ]
        return steps
    }
}

struct GuideTargets: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks a control the guide can point at.
    func guideTarget(_ id: String) -> some View {
        anchorPreference(key: GuideTargets.self, value: .bounds) { [id: $0] }
    }
}

/// The dim, the cut-out around the step's control, and the popup with its arrow.
struct GuideOverlay: View {
    @EnvironmentObject var s: Store
    let anchors: [String: Anchor<CGRect>]
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)

    var body: some View {
        GeometryReader { space in
            if let function = s.guide {
                let steps = Guide.steps(for: function).filter { anchors[$0.target] != nil }
                if steps.isEmpty { Color.clear.onAppear { s.guide = nil } } else {
                    let index = min(s.guideStep, steps.count - 1)
                    let step = steps[index]
                    let target = anchors[step.target].map { space[$0].insetBy(dx: -8, dy: -8) } ?? .zero
                    ZStack(alignment: .topLeading) {
                        // The dim, with the control cut out.
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: space.size))
                            path.addRoundedRect(in: target, cornerSize: CGSize(width: 12, height: 12))
                        }
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle()).onTapGesture { }
                        RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 2)
                            .frame(width: target.width, height: target.height).offset(x: target.minX, y: target.minY)
                            .allowsHitTesting(false)
                        popup(step, index: index, count: steps.count, target: target, in: space.size)
                    }
                    .animation(.easeInOut(duration: 0.22), value: index)
                }
            }
        }
    }

    /// Placed beside the control: to its right when it is in the sidebar, else below it, or above when there is no room.
    func popup(_ step: GuideStep, index: Int, count: Int, target: CGRect, in size: CGSize) -> some View {
        // Height from the content: about 46 characters a line at this width.
        func lines(_ text: String) -> CGFloat { text.isEmpty ? 0 : CGFloat(max(1, (L(text).count + 45) / 46)) }
        let width: CGFloat = 350, gap: CGFloat = 16
        let height: CGFloat = 104 + lines(step.lead) * 17 + step.points.reduce(0) { $0 + lines($1) * 18 + 6 }
            + (step.tip.isEmpty ? 0 : lines(step.tip) * 15 + 22)
        enum Side { case right, below, above }
        let side: Side = target.maxX + gap + width < size.width && target.minX < 260 ? .right
            : target.maxY + gap + height < size.height ? .below : .above
        let x: CGFloat, y: CGFloat
        switch side {
        case .right: x = target.maxX + gap; y = min(max(12, target.midY - height / 2), size.height - height - 12)
        case .below: x = min(max(12, target.midX - width / 2), size.width - width - 12); y = target.maxY + gap
        case .above: x = min(max(12, target.midX - width / 2), size.width - width - 12); y = target.minY - gap - height
        }
        // The arrow from the popup's edge toward the control.
        let arrow: (CGPoint, Angle) = {
            switch side {
            case .right: return (CGPoint(x: -7, y: min(max(20, target.midY - y), height - 20)), .degrees(-90))
            case .below: return (CGPoint(x: min(max(20, target.midX - x), width - 20), y: -7), .zero)
            case .above: return (CGPoint(x: min(max(20, target.midX - x), width - 20), y: height + 7), .degrees(180))
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(step.title)).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(L("%@ of %@", index + 1, count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            if !step.lead.isEmpty {
                Text(md: L(step.lead)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(step.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(md: L(point)).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !step.tip.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lightbulb").font(.system(size: 10)).foregroundStyle(accent)
                    Text(md: L(step.tip)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            Spacer(minLength: 0)
            HStack {
                Button(L("Skip")) { s.guide = nil }.buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                Spacer()
                if index > 0 { Button(L("Back")) { s.guideStep = index - 1 } }
                Button(index + 1 < count ? L("Next") : L("Done")) {
                    if index + 1 < count { s.guideStep = index + 1 } else { s.guide = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.font(.system(size: 12))
        }
        .padding(16).frame(width: width, height: height, alignment: .topLeading)
        .background(Color(red: 0.11, green: 0.13, blue: 0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.6)))
        .overlay(alignment: .topLeading) {
            Triangle().fill(accent).frame(width: 14, height: 8).rotationEffect(arrow.1)
                .position(arrow.0)
        }
        .tint(accent)
        .offset(x: x, y: y)
    }
}

/// The popup's arrow, pointing up before it is rotated.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
