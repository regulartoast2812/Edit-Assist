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

    /// Every face and body in the image. One Vision pass for all three requests.
    nonisolated static func people(in image: CGImage) -> People {
        let faces = VNDetectFaceLandmarksRequest()
        let poses = VNDetectHumanBodyPoseRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([faces, poses, humans]) } catch { return People() }
        func flip(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height) }
        func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }

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
                    var line = points.map { flip(CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)) }
                    if closed, let first = line.first { line.append(first) }
                    outlines.append(line)
                }
            }
            func degrees(_ value: NSNumber?) -> Double? { value.map { $0.doubleValue * 180 / .pi } }
            found.faces.append(Face(rect: flip(box), roll: degrees(face.roll), yaw: degrees(face.yaw), outlines: outlines))
        }

        // The person boxes and the poses come from separate models; each pose goes with the box that
        // holds most of its joints, and a pose with no box gets one around its joints.
        let boxes = (humans.results ?? []).map { flip($0.boundingBox) }
        var used = Set<Int>()
        for pose in poses.results ?? [] {
            guard let points = try? pose.recognizedPoints(.all) else { continue }
            var joints: [String: CGPoint] = [:]
            for (name, point) in points where point.confidence > 0.3 { joints[name.rawValue.rawValue] = flip(point.location) }
            guard joints.count >= 4 else { continue }
            let best = boxes.indices.filter { !used.contains($0) }
                .max { a, b in joints.values.filter { boxes[a].contains($0) }.count < joints.values.filter { boxes[b].contains($0) }.count }
            let rect: CGRect
            if let best, joints.values.filter({ boxes[best].contains($0) }).count * 2 >= joints.count {
                used.insert(best); rect = boxes[best]
            } else {
                let xs = joints.values.map(\.x), ys = joints.values.map(\.y)
                let around = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                rect = around.insetBy(dx: -around.width * 0.15, dy: -around.height * 0.1)
            }
            found.bodies.append(Body(rect: rect, joints: joints))
        }
        for index in boxes.indices where !used.contains(index) { found.bodies.append(Body(rect: boxes[index], joints: [:])) }
        return found
    }
}
