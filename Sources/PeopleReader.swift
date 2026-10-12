import Vision

// Faces and bodies in the editor window, from Apple's Vision models on this Mac (no download, no
// network). Reading only: nothing here clicks or decides anything in a run. Positions are fractions
// of the window with the origin at the top left, like OCR's boxes; Vision's own are bottom left.
extension Desktop {
    struct Face {
        var rect: CGRect
        /// The same number for the same face from frame to frame (see PeopleFollower); 0 until numbered.
        var id = 0
        /// Not found in this frame but followed from earlier ones (a turn, a hand in front, blur).
        var followed = false
        /// Head tilt and turn in degrees, when Vision gives them.
        var roll: Double?
        var yaw: Double?
        /// Outlines: face contour, eyebrows, eyes, nose, lips; each a line through its points.
        var outlines: [[CGPoint]]
    }

    struct Body {
        /// The person, head to as far down as is visible.
        var rect: CGRect
        /// The person's outline from Vision's person mask, closed. Found even when only part of the
        /// body is in the shot (waist down, hands), where the pose has no joints to give.
        var outline: [CGPoint] = []
        /// Joints found with enough confidence, by name ("left_shoulder_1_joint", …).
        var joints: [String: CGPoint]
        /// Bones between found joints, each a two-point line.
        var bones: [[CGPoint]] { Self.skeleton.compactMap { pair in
            guard let a = joints[pair.0.rawValue.rawValue], let b = joints[pair.1.rawValue.rawValue] else { return nil }
            return [a, b]
        } }
        static let skeleton: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .neck), (.leftEye, .nose), (.rightEye, .nose), (.leftEar, .leftEye), (.rightEar, .rightEye),
            (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .root), (.root, .leftHip), (.root, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        ]
    }

    struct People {
        var faces: [Face] = []
        var bodies: [Body] = []
    }

    /// The Program Monitor's picture: below its "Program: …" tab, above the current-time timecode under
    /// it, and the first stretch of pixels that are not the panel's own background. Vision shrinks what
    /// it is given to a few hundred pixels, so reading only this, not the whole window, gives it about
    /// three times the detail. Nil when the Program tab is not on screen.
    nonisolated static func programPicture(in hits: [TextHit], image: CGImage) -> CGRect? {
        guard let tab = panelTabs(in: hits).first(where: { $0.panel == "Program" })?.rect else { return nil }
        let below = hits.filter { $0.rect.minY > tab.maxY && abs($0.rect.minX - tab.minX) < 0.08 && seconds(ofTimecode: $0.text) != nil }
            .min { $0.rect.minY < $1.rect.minY }?.rect
        // Down to the bottom of the timecode's row: that row is the panel's own background around a little text.
        let band = CGRect(x: max(0, tab.minX - 0.02), y: tab.maxY, width: min(1, tab.minX + 0.7) - max(0, tab.minX - 0.02),
                          height: (below?.maxY ?? 1) - tab.maxY)
        guard band.width > 0.05, band.height > 0.05 else { return nil }
        let pixels = CGRect(x: band.minX * CGFloat(image.width), y: band.minY * CGFloat(image.height),
                            width: band.width * CGFloat(image.width), height: band.height * CGFloat(image.height))
        let width = max(8, Int(pixels.width / 3)), height = max(8, Int(pixels.height / 3))
        let rgba = patch(of: image, rect: pixels, width: width, height: height)
        let luma = (0 ..< width * height).map { (Int(rgba[$0 * 4]) * 30 + Int(rgba[$0 * 4 + 1]) * 59 + Int(rgba[$0 * 4 + 2]) * 11) / 100 }
        // The panel's background: the commonest level in the timecode's row (or the band's last rows).
        var histogram = [Int](repeating: 0, count: 256)
        let floor = below.map { Int(Double(height) * Double(($0.minY - band.minY) / band.height)) } ?? height - 3
        for y in max(0, min(floor, height - 1)) ..< height { for x in 0 ..< width { histogram[luma[y * width + x]] += 1 } }
        let background = histogram.indices.max { histogram[$0] < histogram[$1] } ?? 0
        func content(_ x: Int, _ y: Int) -> Bool { abs(luma[y * width + x] - background) > 6 }
        func runs(_ share: [Double], minimum: Int) -> [Range<Int>] {
            var found: [Range<Int>] = [], start: Int?
            for (index, value) in (share + [0]).enumerated() {
                if value > 0.5 { start = start ?? index } else if let first = start { if index - first >= minimum { found.append(first ..< index) }; start = nil }
            }
            return found
        }
        // Columns: the first wide run from the left is the picture (a ruler is narrow, and anything to its
        // right belongs to the next panel). Rows: the longest run within those columns.
        let columnShare = (0 ..< width).map { x in Double((0 ..< height).filter { content(x, $0) }.count) / Double(height) }
        guard let columns = runs(columnShare, minimum: max(4, Int(Double(width) * 0.06))).first else { return nil }
        let rowShare = (0 ..< height).map { y in Double(columns.filter { content($0, y) }.count) / Double(columns.count) }
        // A dark stretch of the shot (a doorway, a night sky) can match the panel's grey; its rows still have
        // some picture in them, where the panel's own rows have next to none. Such a stretch joins the
        // picture rows on either side of it.
        var merged: [Range<Int>] = []
        for run in runs(rowShare, minimum: 2) {
            if let last = merged.last, (last.upperBound ..< run.lowerBound).allSatisfy({ rowShare[$0] > 0.15 }) {
                merged[merged.count - 1] = last.lowerBound ..< run.upperBound
            } else { merged.append(run) }
        }
        guard let rows = merged.filter({ $0.count >= max(4, Int(Double(height) * 0.1)) }).max(by: { $0.count < $1.count }) else { return nil }
        return CGRect(x: band.minX + band.width * CGFloat(columns.lowerBound) / CGFloat(width),
                      y: band.minY + band.height * CGFloat(rows.lowerBound) / CGFloat(height),
                      width: band.width * CGFloat(columns.count) / CGFloat(width),
                      height: band.height * CGFloat(rows.count) / CGFloat(height))
    }

    /// The part of the image inside an area given as fractions of it; the whole image for the whole area.
    nonisolated static func crop(_ image: CGImage, to area: CGRect) -> CGImage {
        guard area != CGRect(x: 0, y: 0, width: 1, height: 1) else { return image }
        let pixels = CGRect(x: area.minX * CGFloat(image.width), y: area.minY * CGFloat(image.height),
                            width: area.width * CGFloat(image.width), height: area.height * CGFloat(image.height)).integral
        return image.cropping(to: pixels) ?? image
    }

    /// Faces Vision found in an area of the window, in window fractions from the top left.
    nonisolated static func faces(_ results: [VNFaceObservation], in area: CGRect) -> [Face] {
        func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: area.minX + point.x * area.width, y: area.minY + (1 - point.y) * area.height) }
        return results.map { face in
            let box = face.boundingBox
            var outlines: [[CGPoint]] = []
            if let marks = face.landmarks {
                let regions: [(VNFaceLandmarkRegion2D?, Bool)] = [
                    (marks.faceContour, false), (marks.leftEyebrow, false), (marks.rightEyebrow, false),
                    (marks.leftEye, true), (marks.rightEye, true), (marks.nose, true), (marks.outerLips, true),
                ]
                for (region, closed) in regions {
                    guard let points = region?.normalizedPoints, points.count > 1 else { continue }
                    // Landmark points are fractions of the face box.
                    var line = points.map { flip(CGPoint(x: box.minX + CGFloat($0.x) * box.width, y: box.minY + CGFloat($0.y) * box.height)) }
                    if closed, let first = line.first { line.append(first) }
                    outlines.append(line)
                }
            }
            func degrees(_ value: NSNumber?) -> Double? { value.map { $0.doubleValue * 180 / .pi } }
            let corner = flip(CGPoint(x: box.minX, y: box.maxY))
            return Face(rect: CGRect(x: corner.x, y: corner.y, width: box.width * area.width, height: box.height * area.height),
                        roll: degrees(face.roll), yaw: degrees(face.yaw), outlines: outlines)
        }
    }

    /// Every face and body in the image, or in one area of it (the Program Monitor's picture). One
    /// Vision pass for all three requests, then an outline traced around each person's mask.
    nonisolated static func people(in image: CGImage, area: CGRect? = nil) -> People {
        let area = area ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let source = crop(image, to: area)
        let faces = VNDetectFaceLandmarksRequest()
        let poses = VNDetectHumanBodyPoseRequest()
        let masks = VNGeneratePersonInstanceMaskRequest()
        do { try VNImageRequestHandler(cgImage: source, options: [:]).perform([faces, poses, masks]) } catch { return People() }
        // Vision's positions are fractions of what it was given, from the bottom left; ours are fractions
        // of the window from the top left.
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: area.minX + point.x * area.width, y: area.minY + (1 - point.y) * area.height)
        }
        func flip(_ rect: CGRect) -> CGRect {
            let a = flip(CGPoint(x: rect.minX, y: rect.maxY)), b = flip(CGPoint(x: rect.maxX, y: rect.minY))
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }

        var found = People()
        found.faces = Self.faces(faces.results ?? [], in: area)


        // One outline per person in the mask: the largest contour around it, simplified.
        var outlines: [[CGPoint]] = []
        if let result = masks.results?.first {
            for person in result.allInstances {
                guard let mask = try? result.generateMask(forInstances: [person]) else { continue }
                let contours = VNDetectContoursRequest()
                contours.detectsDarkOnLight = false
                contours.maximumImageDimension = 256
                guard (try? VNImageRequestHandler(cvPixelBuffer: mask, options: [:]).perform([contours])) != nil,
                      let largest = contours.results?.first?.topLevelContours.max(by: { $0.pointCount < $1.pointCount }),
                      let simple = try? largest.polygonApproximation(epsilon: 0.003), simple.pointCount >= 3 else { continue }
                var line = simple.normalizedPoints.map { flip(CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))) }
                if let first = line.first { line.append(first) }
                outlines.append(line)
            }
        }
        func bounds(_ points: [CGPoint]) -> CGRect {
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        // The outlines and the poses come from separate models; each pose goes with the outline that
        // holds most of its joints, and a pose with no outline gets a box around its joints.
        let boxes = outlines.map(bounds)
        var used = Set<Int>()
        for pose in poses.results ?? [] {
            guard let points = try? pose.recognizedPoints(.all) else { continue }
            var joints: [String: CGPoint] = [:]
            for (name, point) in points where point.confidence > 0.3 { joints[name.rawValue.rawValue] = flip(point.location) }
            guard joints.count >= 4 else { continue }
            let best = boxes.indices.filter { !used.contains($0) }
                .max { a, b in joints.values.filter { boxes[a].contains($0) }.count < joints.values.filter { boxes[b].contains($0) }.count }
            if let best, joints.values.filter({ boxes[best].contains($0) }).count * 2 >= joints.count {
                used.insert(best)
                found.bodies.append(Body(rect: boxes[best], outline: outlines[best], joints: joints))
            } else {
                let around = bounds(Array(joints.values))
                found.bodies.append(Body(rect: around.insetBy(dx: -around.width * 0.15, dy: -around.height * 0.1), joints: joints))
            }
        }
        for index in boxes.indices where !used.contains(index) { found.bodies.append(Body(rect: boxes[index], outline: outlines[index], joints: [:])) }
        return found
    }
}

/// Follows faces from frame to frame of the live stream: numbers them so the same face keeps its
/// number, re-reads a head the pose shows but the face model missed (at full detail, just that patch),
/// and keeps following a face for a moment when the face model loses it (a turn, a hand in front,
/// blur), marked as followed. Frames come one at a time, never two at once (Store.followPeople), so
/// this needs no locking.
final class PeopleFollower: @unchecked Sendable {
    private struct Followed {
        var face: Desktop.Face
        /// Vision's object tracker, started only once the face model has lost the face: seeded on the
        /// last frame it was found in, then run on each frame after. Nil while the face is being found.
        var tracker: (request: VNTrackObjectRequest, handler: VNSequenceRequestHandler)?
        /// Frames in a row it was only followed, not found.
        var missed = 0
    }
    private var followed: [Followed] = []
    private var nextID = 1
    private var area: CGRect?
    private var lastFrame = Date.distantPast
    /// The previous frame's picture, where a face that is lost now was last found.
    private var previous: CGImage?
    /// About half a second at 30 fps: long enough to bridge a turn or a hand, short enough not to
    /// leave a box behind when someone walks out of the shot.
    private let holdFrames = 15

    func read(_ image: CGImage, area: CGRect?) -> Desktop.People {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        // A different picture area, or a pause (a run, the editor in the background): start over.
        if area != self.area || Date().timeIntervalSince(lastFrame) > 0.5 { followed = []; previous = nil; self.area = area }
        lastFrame = Date()
        let region = area ?? whole
        let source = Desktop.crop(image, to: region)
        defer { previous = source }
        var found = Desktop.people(in: image, area: area)
        found.faces += heads(missedIn: found, image: image)

        // Each face found now takes the number of the face from before that overlaps it most. A frame
        // apart, a face moves only a little of its own size.
        var taken = Set<Int>()
        var next: [Followed] = []
        for var face in found.faces {
            let best = followed.indices.filter { !taken.contains($0) }.max { overlap(face.rect, followed[$0].face.rect) < overlap(face.rect, followed[$1].face.rect) }
            if let best, overlap(face.rect, followed[best].face.rect) > 0.2 {
                taken.insert(best); face.id = followed[best].face.id
            } else { face.id = nextID; nextID += 1 }
            next.append(Followed(face: face))
        }
        // Faces from before that were not found now: followed by the tracker where it still sees them, or
        // held where they were last seen, for a moment, marked. One that comes back there keeps its number.
        for index in followed.indices where !taken.contains(index) && followed[index].missed < holdFrames {
            var entry = followed[index]
            if entry.tracker == nil, let previous { entry.tracker = tracker(for: entry.face.rect, in: region, seededOn: previous) }
            var rect = entry.face.rect
            if let tracker = entry.tracker, (try? tracker.handler.perform([tracker.request], on: source)) != nil,
               let result = tracker.request.results?.first as? VNDetectedObjectObservation, result.confidence > 0.3 {
                tracker.request.inputObservation = result
                rect = window(result.boundingBox, in: region)
            }
            entry.face = shifted(entry.face, to: rect); entry.face.followed = true; entry.missed += 1
            next.append(entry)
        }
        followed = next
        found.faces = next.map(\.face).sorted { $0.id < $1.id }
        return found
    }

    /// A tracker for a face, seeded on the frame it was last found in.
    private func tracker(for rect: CGRect, in region: CGRect, seededOn image: CGImage) -> (request: VNTrackObjectRequest, handler: VNSequenceRequestHandler)? {
        let local = CGRect(x: (rect.minX - region.minX) / region.width, y: 1 - (rect.maxY - region.minY) / region.height,
                           width: rect.width / region.width, height: rect.height / region.height)
        guard local.width > 0, local.height > 0 else { return nil }
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: local))
        request.trackingLevel = .accurate
        let handler = VNSequenceRequestHandler()
        guard (try? handler.perform([request], on: image)) != nil else { return nil }
        if let result = request.results?.first as? VNDetectedObjectObservation { request.inputObservation = result }
        return (request, handler)
    }

    private func window(_ box: CGRect, in region: CGRect) -> CGRect {
        CGRect(x: region.minX + box.minX * region.width, y: region.minY + (1 - box.maxY) * region.height,
               width: box.width * region.width, height: box.height * region.height)
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull else { return 0 }
        return shared.width * shared.height / (a.union(b).width * a.union(b).height)
    }

    /// The face's outlines moved and scaled with its box.
    private func shifted(_ face: Desktop.Face, to rect: CGRect) -> Desktop.Face {
        var copy = face
        let old = face.rect
        guard old.width > 0, old.height > 0 else { copy.rect = rect; return copy }
        copy.outlines = face.outlines.map { line in line.map {
            CGPoint(x: rect.minX + ($0.x - old.minX) / old.width * rect.width, y: rect.minY + ($0.y - old.minY) / old.height * rect.height)
        } }
        copy.rect = rect
        return copy
    }

    /// Heads the pose shows (nose, eyes, ears) with no face found on them: the face model again, on
    /// just that patch of the full-size window, where a distant face has many more pixels.
    private func heads(missedIn found: Desktop.People, image: CGImage) -> [Desktop.Face] {
        var extra: [Desktop.Face] = []
        for body in found.bodies {
            let names: [VNHumanBodyPoseObservation.JointName] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
            let points = names.compactMap { body.joints[$0.rawValue.rawValue] }
            guard points.count >= 2 else { continue }
            let xs = points.map(\.x), ys = points.map(\.y)
            let centre = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
            // The head is a few times the spread of its eyes and ears, and wider still with the neck.
            var size = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) * 3
            if let neck = body.joints[VNHumanBodyPoseObservation.JointName.neck.rawValue.rawValue] { size = max(size, abs(neck.y - centre.y) * 2.6) }
            guard size > 0 else { continue }
            let head = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            // Skipped when a face is already centred in it; a neighbour's face can reach into the square.
            guard !head.isNull, !(found.faces + extra).contains(where: { head.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }) else { continue }
            let request = VNDetectFaceLandmarksRequest()
            guard (try? VNImageRequestHandler(cgImage: Desktop.crop(image, to: head), options: [:]).perform([request])) != nil else { continue }
            extra += Desktop.faces(request.results ?? [], in: head)
        }
        return extra
    }
}
