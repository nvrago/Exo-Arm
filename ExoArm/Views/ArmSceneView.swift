import SwiftUI
import RealityKit
import AppKit
import simd

// swiftUI wrapper

struct ArmSceneView: NSViewRepresentable {
    @ObservedObject var viewModel: SessionViewModel

    func makeNSView(context: Context) -> OrbitARView {
        let view = OrbitARView(frame: .zero)
        view.setupScene()
        viewModel.armRenderer = view
        return view
    }

    func updateNSView(_ nsView: OrbitARView, context: Context) {}
}

// orbit AR view

final class OrbitARView: ARView {

    // camera orbit state, defaults tuned for a horizontal corner view
    private var yaw: Float = 0.55
    private var pitch: Float = 0.12
    private var radius: Float = 1.4
    private let lookAt: SIMD3<Float> = [0, 0.02, 0]
    private var cameraAnchor: AnchorEntity!

    // arm hierarchy
    private var armRoot: Entity!
    private(set) var shoulderJoint: Entity!
    private(set) var elbowJoint: Entity!
    private(set) var wristJoint: Entity!
    private var handEntity: Entity!

    // segment proportions
    private let upperArmLen: Float = 0.30
    private let forearmLen: Float = 0.25
    private let handLen: Float = 0.10

    // hand trail
    private var trailParent: Entity!
    private var trailDots: [Entity] = []
    private var trailMesh: MeshResource!
    private var trailMaterial: UnlitMaterial!
    private var frameCounter: Int = 0
    private let maxTrailDots = 150
    private let trailEveryNFrames = 3

    required init(frame: NSRect) {
        super.init(frame: frame)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    //scene setup

    func setupScene() {
        scene.anchors.removeAll()
        environment.background = .color(NSColor(white: 0.08, alpha: 1.0))

        let root = AnchorEntity(world: .zero)
        scene.addAnchor(root)

        buildLighting(parent: root)
        buildGrid(parent: root)
        buildArm(parent: root)
        buildTrail(parent: root)

        cameraAnchor = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 45
        cameraAnchor.addChild(camera)
        scene.addAnchor(cameraAnchor)
        updateCamera()
    }

    private func buildLighting(parent: Entity) {
        let key = DirectionalLight()
        key.light.intensity = 1800
        key.light.color = .white
        key.look(at: [0, 0, 0], from: [0.6, 1.0, 0.8], relativeTo: nil)
        parent.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 800
        fill.light.color = NSColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1.0)
        fill.look(at: [0, 0, 0], from: [-1.2, 0.3, 0.5], relativeTo: nil)
        parent.addChild(fill)

        let rim = DirectionalLight()
        rim.light.intensity = 600
        rim.light.color = .white
        rim.look(at: [0, 0, 0], from: [0.2, 0.5, -1.0], relativeTo: nil)
        parent.addChild(rim)
    }

    //three-plane corner enclosure, major/minor line hierarchy
    private func buildGrid(parent: Entity) {
        let gridY: Float = -0.38
        let extent: Float = 0.50
        let backZ: Float = -0.50
        let sideX: Float = -0.50

        let cyan = NSColor(red: 0.35, green: 0.72, blue: 0.85, alpha: 1.0)
        let floorMinor = cyan.withAlphaComponent(0.28)
        let floorMajor = cyan.withAlphaComponent(0.68)
        let wallMinor = cyan.withAlphaComponent(0.18)
        let wallMajor = cyan.withAlphaComponent(0.52)

        let floor = makeGridPlane(extent: extent, axis: .y,
                                  minorColor: floorMinor, majorColor: floorMajor)
        floor.position = [0, gridY, 0]
        parent.addChild(floor)

        let back = makeGridPlane(extent: extent, axis: .z,
                                 minorColor: wallMinor, majorColor: wallMajor)
        back.position = [0, gridY + extent, backZ]
        parent.addChild(back)

        let side = makeGridPlane(extent: extent, axis: .x,
                                 minorColor: wallMinor, majorColor: wallMajor)
        side.position = [sideX, gridY + extent, 0]
        parent.addChild(side)
    }

    private enum PlaneAxis { case x, y, z }

    // every 4th line is major (thicker and brighter). i=0 and i=divisions
    // hit major naturally, giving the plane a defined border.
    private func makeGridPlane(extent: Float, axis: PlaneAxis,
                               minorColor: NSColor, majorColor: NSColor) -> Entity {
        let entity = Entity()
        let divisions = 12
        let half = extent
        let step = (extent * 2) / Float(divisions)
        let majorEvery = 4
        let minorThickness: Float = 0.0010
        let majorThickness: Float = 0.0024

        let minorMat = UnlitMaterial(color: minorColor)
        let majorMat = UnlitMaterial(color: majorColor)

        for i in 0...divisions {
            let t = -half + Float(i) * step
            let isMajor = (i % majorEvery == 0)
            let thickness = isMajor ? majorThickness : minorThickness
            let mat = isMajor ? majorMat : minorMat

            let pairs: [(SIMD3<Float>, SIMD3<Float>)]
            switch axis {
            case .y: pairs = [([-half, 0, t], [half, 0, t]), ([t, 0, -half], [t, 0, half])]
            case .z: pairs = [([-half, t, 0], [half, t, 0]), ([t, -half, 0], [t, half, 0])]
            case .x: pairs = [([0, -half, t], [0, half, t]), ([0, t, -half], [0, t, half])]
            }
            for (a, b) in pairs {
                let mid = (a + b) * 0.5
                let len = simd_length(b - a)
                let size: SIMD3<Float>
                switch axis {
                case .y:
                    size = (a.x == b.x) ? [thickness, thickness, len] : [len, thickness, thickness]
                case .z:
                    size = (a.x == b.x) ? [thickness, len, thickness] : [len, thickness, thickness]
                case .x:
                    size = (a.y == b.y) ? [thickness, thickness, len] : [thickness, len, thickness]
                }
                let mesh = MeshResource.generateBox(size: size)
                let model = ModelEntity(mesh: mesh, materials: [mat])
                model.position = mid
                entity.addChild(model)
            }
        }
        return entity
    }

    //capsules for segments, spheres at joints, box hand
    private func buildArm(parent: Entity) {
        let segmentMat = SimpleMaterial(
            color: NSColor(red: 0.78, green: 0.78, blue: 0.82, alpha: 1.0),
            roughness: 0.85, isMetallic: false)
        let jointMat = SimpleMaterial(
            color: NSColor(red: 0.38, green: 0.40, blue: 0.46, alpha: 1.0),
            roughness: 0.6, isMetallic: false)
        let handMat = SimpleMaterial(
            color: NSColor(red: 0.72, green: 0.72, blue: 0.78, alpha: 1.0),
            roughness: 0.85, isMetallic: false)

        armRoot = Entity()
        armRoot.name = "armRoot"
        armRoot.position = [0, 0.35, 0]
        parent.addChild(armRoot)

        // shoulder pivot, gets upper arm IMU rotation
        shoulderJoint = Entity()
        shoulderJoint.name = "shoulderJoint"
        armRoot.addChild(shoulderJoint)

        let shoulderSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [jointMat])
        shoulderJoint.addChild(shoulderSphere)

        // upper arm segment hangs from shoulder
        let upperArm = ModelEntity(
            mesh: .generateCylinder(height: upperArmLen, radius: 0.038),
            materials: [segmentMat])
        upperArm.position = [0, -upperArmLen / 2, 0]
        shoulderJoint.addChild(upperArm)

        // elbow pivot at distal end of upper arm
        elbowJoint = Entity()
        elbowJoint.name = "elbowJoint"
        elbowJoint.position = [0, -upperArmLen, 0]
        shoulderJoint.addChild(elbowJoint)

        let elbowSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.048),
            materials: [jointMat])
        elbowJoint.addChild(elbowSphere)

        let forearm = ModelEntity(
            mesh: .generateCylinder(height: forearmLen, radius: 0.033),
            materials: [segmentMat])
        forearm.position = [0, -forearmLen / 2, 0]
        elbowJoint.addChild(forearm)

        // wrist pivot at distal end of forearm
        wristJoint = Entity()
        wristJoint.name = "wristJoint"
        wristJoint.position = [0, -forearmLen, 0]
        elbowJoint.addChild(wristJoint)

        let wristSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.040),
            materials: [jointMat])
        wristJoint.addChild(wristSphere)

        // solid block hand
        handEntity = ModelEntity(
            mesh: .generateBox(size: [0.075, handLen, 0.030], cornerRadius: 0.012),
            materials: [handMat])
        handEntity.name = "hand"
        handEntity.position = [0, -handLen / 2 - 0.020, 0]
        wristJoint.addChild(handEntity)
    }

    private func buildTrail(parent: Entity) {
        trailParent = Entity()
        trailParent.name = "trailParent"
        parent.addChild(trailParent)
        trailMesh = .generateSphere(radius: 0.006)
        trailMaterial = UnlitMaterial(
            color: NSColor(red: 0.2, green: 0.85, blue: 1.0, alpha: 0.9))
    }

    //pose update

    // drive nested joints with parent relative quaternions so each segment rotates around its anatomical pivot without cascading the parent's rotation.
    func updatePose(_ frame: ProcessedFrame, interpolator: FrameInterpolator) {
        interpolator.pushTarget(frame)
        guard let pose = interpolator.interpolated() else { return }

        let uaQ = pose.upperArm
        let faQ = pose.forearm
        let hdQ = pose.hand

        shoulderJoint.orientation = uaQ
        elbowJoint.orientation = uaQ.inverse * faQ
        wristJoint.orientation = faQ.inverse * hdQ

        frameCounter += 1
        if frameCounter % trailEveryNFrames == 0 {
            addTrailDot()
        }
    }

    private func addTrailDot() {
        let worldPos = handEntity.position(relativeTo: nil)
        let dot = ModelEntity(mesh: trailMesh, materials: [trailMaterial])
        dot.position = worldPos
        trailParent.addChild(dot)
        trailDots.append(dot)

        if trailDots.count > maxTrailDots {
            let old = trailDots.removeFirst()
            old.removeFromParent()
        }
    }

    func clearTrail() {
        for dot in trailDots { dot.removeFromParent() }
        trailDots.removeAll()
    }

    //camera

    private func updateCamera() {
        let x = lookAt.x + radius * cos(pitch) * sin(yaw)
        let y = lookAt.y + radius * sin(pitch)
        let z = lookAt.z + radius * cos(pitch) * cos(yaw)
        cameraAnchor.position = [x, y, z]
        cameraAnchor.look(at: lookAt, from: cameraAnchor.position, relativeTo: nil)
    }

    //mouse input

    override func mouseDragged(with event: NSEvent) {
        yaw += Float(event.deltaX) * 0.006
        pitch -= Float(event.deltaY) * 0.006
        pitch = max(-Float.pi / 2 + 0.05, min(Float.pi / 2 - 0.05, pitch))
        updateCamera()
    }

    override func scrollWheel(with event: NSEvent) {
        radius *= 1.0 - Float(event.scrollingDeltaY) * 0.015
        radius = max(0.4, min(3.0, radius))
        updateCamera()
    }
}

//2D orientation overlay (x,y,z)

struct GizmoOverlay: View {
    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let len: CGFloat = 26

            let axes: [(String, Color, CGPoint)] = [
                ("X", .red, CGPoint(x: cx + len, y: cy)),
                ("Y", .green, CGPoint(x: cx, y: cy - len)),
                ("Z", .blue, CGPoint(x: cx + len * 0.5, y: cy + len * 0.5))
            ]
            for (label, color, end) in axes {
                var path = Path()
                path.move(to: CGPoint(x: cx, y: cy))
                path.addLine(to: end)
                context.stroke(path, with: .color(color), lineWidth: 2.5)
                context.draw(
                    Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color),
                    at: CGPoint(x: end.x + 8, y: end.y))
            }
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }
}
