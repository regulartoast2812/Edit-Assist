import Vision

// Faces and bodies in the editor window, from Apple's Vision models on this Mac (no download, no
// network). Reading only: nothing here clicks or decides anything in a run. Positions are fractions
// of the window with the origin at the top left, like OCR's boxes; Vision's own are bottom left.
extension Desktop {
    struct Face {
        var rect: CGRect
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

    /// Every face and body in the image, or in one area of it (the Program Monitor's picture). One
    /// Vision pass for all three requests, then an outline traced around each person's mask.
    nonisolated static func people(in image: CGImage, area: CGRect? = nil) -> People {
        var source = image
        let area = area ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        if area != CGRect(x: 0, y: 0, width: 1, height: 1),
           let cropped = image.cropping(to: CGRect(x: area.minX * CGFloat(image.width), y: area.minY * CGFloat(image.height),
                                                   width: area.width * CGFloat(image.width), height: area.height * CGFloat(image.height)).integral) {
            source = cropped
        }
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
        for face in faces.results ?? [] {
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
            found.faces.append(Face(rect: flip(box), roll: degrees(face.roll), yaw: degrees(face.yaw), outlines: outlines))
        }

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
