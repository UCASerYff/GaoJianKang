import AppKit
import SceneKit
import SwiftUI

// The same scene controls are compiled into each game framework. Each module owns its save data.
struct GQWorldItem: Equatable {
    let id: String
    let title: String
    let kind: String
    let level: Int
    let x: Double
    let z: Double
    var movable = true
    var progress: Double? = nil
    var status: String = ""
}

struct GQWorldScene: NSViewRepresentable {
    let mode: String
    let items: [GQWorldItem]
    let selectedID: String?
    let yaw: Double
    let zoom: Double
    var animationToken = 0
    var trainTravelling = false
    var catLayoutMode = false
    var observationOnly = false
    let onSelect: (String?) -> Void
    let onMove: (String, Double, Double) -> Void
    var onZoom: ((Double) -> Void)? = nil
    var onRotate: ((Double) -> Void)? = nil

    func makeNSView(context: Context) -> GQWorldSCNView {
        let view = GQWorldSCNView(frame: .zero)
        view.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.observationOnly = observationOnly
        view.preferredFramesPerSecond = observationOnly ? 15 : 30
        view.rendersContinuously = false
        view.isPlaying = true
        view.allowsCameraControl = false
        view.onSelect = onSelect
        view.onMove = onMove
        view.onZoom = onZoom
        view.onRotate = onRotate
        return view
    }
    func updateNSView(_ view: GQWorldSCNView, context: Context) {
        view.onSelect = onSelect
        view.onMove = onMove
        view.onZoom = onZoom
        view.onRotate = onRotate
        let signature = "\(mode)|" + items.map {
            "\($0.id):\($0.title):\($0.kind):\($0.level):\($0.x):\($0.z)"
        }.joined(separator: "|")
        if view.sceneSignature != signature {
            view.sceneSignature = signature
            view.scene = GQWorldBuilder.scene(mode: mode, items: items, selectedID: nil)
            view.itemNodes = Dictionary(uniqueKeysWithValues: (items.compactMap { item in
                view.scene?.rootNode.childNode(withName: "item:\(item.id)", recursively: true).map { (item.id, $0) }
            }))
            view.movableIDs = Set(items.filter(\.movable).map(\.id))
            view.selectedID = nil
            view.badgeKeys = [:]
        }
        if mode == "farm" || mode == "pasture" {
            for item in items where item.kind != "__world" {
                let key = "\(item.title)|\(item.status)|\(Int((item.progress ?? -1) * 100))|\(item.level)"
                if view.badgeKeys[item.id] != key, let node = view.itemNodes[item.id] {
                    GQWorldBuilder.estateBadge(node, item: item, mode: mode)
                    view.badgeKeys[item.id] = key
                }
            }
        }
        view.movableIDs = Set(items.filter(\.movable).map(\.id))
        if mode == "train",view.trainTravelling != trainTravelling || view.motionScene !== view.scene {
            view.trainTravelling=trainTravelling;view.motionScene=view.scene
            if let root=view.scene?.rootNode { GQWorldBuilder.setTrainMotion(root,active:trainTravelling) }
        }
        if mode == "cat",view.catLayoutMode != catLayoutMode || view.motionScene !== view.scene {
            view.catLayoutMode=catLayoutMode;view.motionScene=view.scene
            if let root=view.scene?.rootNode { GQWorldBuilder.setBetaMotion(root,items:items,active:!catLayoutMode) }
        }
        if mode == "expedition",let probe=view.itemNodes["probe"],let item=items.first(where:{$0.id=="probe"}) {
            let p=item.progress ?? 0
            SCNTransaction.begin();SCNTransaction.animationDuration=1
            probe.position=SCNVector3(-6.2+p*3.0,1.1,2.2-p*1.2)
            SCNTransaction.commit()
        }
        view.updateSelection(selectedID)
        for (id,node) in view.itemNodes {
            node.childNode(withName:"world-plaque",recursively:false)?.isHidden = id != selectedID
        }
        if mode == "aquarium" {
            for (id, node) in view.itemNodes { node.childNode(withName:"fish-label", recursively:false)?.isHidden = id != selectedID }
        }
        if view.lastAnimationToken != animationToken {
            view.lastAnimationToken = animationToken
            if mode == "battle" && animationToken > 0 {
                let lunge = SCNAction.sequence([.moveBy(x:1.2,y:0,z:0,duration:0.16),
                                                .moveBy(x:-1.2,y:0,z:0,duration:0.24)])
                view.itemNodes["hero"]?.runAction(lunge)
                view.itemNodes["monster"]?.runAction(.sequence([
                    .wait(duration:0.16), .moveBy(x:0.35,y:0,z:0,duration:0.08),
                    .moveBy(x:-0.35,y:0,z:0,duration:0.28)]))
            } else if mode == "cat" && animationToken > 0,
                      let cat = view.itemNodes["cat"] {
                cat.removeAllActions()
                if let root=view.scene?.rootNode { GQWorldBuilder.setBetaMotion(root,items:items,active:!catLayoutMode,greeting:true) }
            }
        }
        if let camera = view.scene?.rootNode.childNode(withName: "camera", recursively: false) {
            let a = yaw * .pi / 180
            let d = mode == "train" ? 19.0 : 17.0
            camera.position = SCNVector3(sin(a) * d, mode == "station" ? 12 : 13, cos(a) * d)
            camera.look(at: SCNVector3(0, 0, 0))
            if mode == "expedition" {
                camera.position=SCNVector3(2,6,19)
                // Timer-driven updates must use world up, not accumulate the previous camera roll.
                camera.look(at:SCNVector3(0,0,0),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            }
            if mode == "farm" || mode == "pasture" {
                camera.position = SCNVector3(0,24,17)
                camera.look(at:SCNVector3(0,0,0))
            }
            if mode == "aquarium" {
                camera.position = SCNVector3(0, 4, 20)
                camera.look(at: SCNVector3(0, 4, 0))
            }
            if mode == "battle" || mode == "camp" {
                camera.position = SCNVector3(0, mode == "battle" ? 2.0 : 1.6, 20)
                camera.look(at:SCNVector3(0, mode == "battle" ? 2.0 : 1.6, 0))
            }
            camera.camera?.orthographicScale = zoom
            view.pointOfView = camera
        }
    }
    static func dismantleNSView(_ view: GQWorldSCNView, coordinator: ()) {
        view.isPlaying = false
        view.scene = nil
    }
}

final class GQWorldSCNView: SCNView {
    var observationOnly = false
    private var visibilityObservers:[NSObjectProtocol]=[]
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) };visibilityObservers=[]
        if window != nil {
            for name in [NSView.boundsDidChangeNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSApplication.didHideNotification,NSApplication.didUnhideNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.updateVisibility() })
            }
        }
        updateVisibility()
    }
    override func layout() { super.layout();updateVisibility() }
    private func updateVisibility() { isPlaying = window?.isVisible == true && window?.isMiniaturized != true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && !NSApp.isHidden }
    deinit { for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { observationOnly ? nil : super.hitTest(point) }
    var sceneSignature = ""
    var trainTravelling = false
    var catLayoutMode = false
    weak var motionScene: SCNScene?
    var badgeKeys: [String:String] = [:]
    var selectedID: String?
    var lastAnimationToken = 0
    var itemNodes: [String: SCNNode] = [:]
    var movableIDs = Set<String>()
    var onSelect: ((String?) -> Void)?
    var onMove: ((String, Double, Double) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onRotate: ((Double) -> Void)?
    func updateSelection(_ id: String?) {
        guard selectedID != id else { return }
        for node in itemNodes.values { node.childNode(withName: "selection-ring", recursively: false)?.removeFromParentNode() }
        selectedID = id
        guard let id, let node = itemNodes[id] else { return }
        let ring = SCNTorus(ringRadius: sceneSignature.hasPrefix("train") ? 1.08 : 0.95, pipeRadius: 0.04)
        let m = SCNMaterial(); m.diffuse.contents = NSColor.systemYellow; m.lightingModel = .physicallyBased
        ring.materials = [m]
        let marker = SCNNode(geometry: ring); marker.name = "selection-ring"; marker.position.y = 0.08
        node.addChildNode(marker)
    }
    private var mouseStart = NSPoint.zero
    private var draggingID: String?
    private var didDrag = false
    private var dragOrigin: SCNVector3?

    private func itemID(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil)
        for result in hitTest(point, options: [.firstFoundOnly: false]) {
            var node: SCNNode? = result.node
            while let current = node {
                if let name = current.name, name.hasPrefix("item:") { return String(name.dropFirst(5)) }
                node = current.parent
            }
        }
        return nil
    }
    private func groundPoint(at event: NSEvent) -> SCNVector3? {
        let p = convert(event.locationInWindow, from: nil)
        let near = unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dy = far.y - near.y
        guard abs(dy) > 0.0001 else { return nil }
        let t = -near.y / dy
        return SCNVector3(near.x + (far.x - near.x) * t, 0, near.z + (far.z - near.z) * t)
    }
    override func mouseDown(with event: NSEvent) {
        mouseStart = convert(event.locationInWindow, from: nil)
        draggingID = itemID(at: event)
        didDrag = false
        dragOrigin = draggingID.flatMap { itemNodes[$0]?.position }
        onSelect?(draggingID)
    }
    override func mouseDragged(with event: NSEvent) {
        if draggingID == nil {
            let current = convert(event.locationInWindow, from:nil)
            onRotate?(Double(current.x-mouseStart.x)*0.28)
            mouseStart=current
            return
        }
        guard let id = draggingID, movableIDs.contains(id), let node = itemNodes[id],
              let point = groundPoint(at: event) else { return }
        let current = convert(event.locationInWindow, from: nil)
        if hypot(current.x - mouseStart.x, current.y - mouseStart.y) < 4 && !didDrag { return }
        didDrag = true
        let edge: CGFloat = sceneSignature.hasPrefix("island") || sceneSignature.hasPrefix("cat") ? 11 : 5
        node.position.x = min(edge, max(-edge, point.x))
        node.position.z = min(edge, max(-edge, point.z))
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag, let id = draggingID, let node = itemNodes[id] {
            let proposed=node.position
            // Rejected placements snap back; accepted ones arrive through the saved/draft model.
            if let dragOrigin { node.position=dragOrigin }
            onMove?(id, Double(proposed.x), Double(proposed.z))
        }
        draggingID = nil
        didDrag = false
    }
    override func scrollWheel(with event:NSEvent) {
        if let onZoom { onZoom(Double(event.scrollingDeltaY)*0.06) }
        else { super.scrollWheel(with:event) }
    }
}

enum GQWorldBuilder {
    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
    static func mat(_ c: NSColor, metal: CGFloat = 0.0, rough: CGFloat = 0.56) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.metalness.contents = metal
        m.roughness.contents = rough
        m.lightingModel = .physicallyBased
        return m
    }
    @discardableResult static func box(_ parent: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                        _ x: Float, _ y: Float, _ z: Float, _ c: NSColor,
                                        chamfer: CGFloat = 0.06, metal: CGFloat = 0) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer)
        g.materials = [mat(c, metal: metal)]
        let n = SCNNode(geometry: g); n.position = SCNVector3(x,y,z); parent.addChildNode(n); return n
    }
    @discardableResult static func cylinder(_ parent: SCNNode, _ radius: CGFloat, _ h: CGFloat,
                                             _ x: Float, _ y: Float, _ z: Float, _ c: NSColor,
                                             metal: CGFloat = 0) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: h); g.radialSegmentCount = 24
        g.materials = [mat(c, metal: metal)]
        let n = SCNNode(geometry: g); n.position = SCNVector3(x,y,z); parent.addChildNode(n); return n
    }
    @discardableResult static func sphere(_ parent: SCNNode, _ r: CGFloat, _ x: Float, _ y: Float,
                                           _ z: Float, _ c: NSColor, metal: CGFloat = 0) -> SCNNode {
        let g = SCNSphere(radius: r); g.segmentCount = 20; g.materials = [mat(c, metal: metal)]
        let n = SCNNode(geometry: g); n.position = SCNVector3(x,y,z); parent.addChildNode(n); return n
    }
    static func cone(_ parent: SCNNode, _ bottom: CGFloat, _ top: CGFloat, _ h: CGFloat,
                     _ x: Float, _ y: Float, _ z: Float, _ c: NSColor) {
        let g = SCNCone(topRadius: top, bottomRadius: bottom, height: h); g.radialSegmentCount = 8
        g.materials = [mat(c)]
        let n = SCNNode(geometry: g); n.position = SCNVector3(x,y,z); parent.addChildNode(n)
    }
    static func title(_ parent: SCNNode, _ text: String, y: Float) {
        let g = SCNText(string: text, extrusionDepth: 0.008)
        g.font = NSFont.systemFont(ofSize: 0.28, weight: .semibold)
        g.flatness = 0.04; g.materials = [mat(.white)]
        let n = SCNNode(geometry: g)
        let bound = n.boundingBox
        n.position = SCNVector3(Float(-(bound.max.x - bound.min.x)/2), y, 0)
        let billboard = SCNBillboardConstraint(); billboard.freeAxes = .Y
        n.constraints = [billboard]
        parent.addChildNode(n)
    }
    static func scene(mode: String, items: [GQWorldItem], selectedID: String?) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = ["station","expedition"].contains(mode) ? color(0.015,0.025,0.07) :
            mode == "battle" ? color(0.18,0.26,0.35) :
            mode == "aquarium" ? color(0.04,0.30,0.39) :
            mode == "island" ? color(0.48,0.77,0.85) :
            mode == "train" ? color(0.70,0.84,0.92) : color(0.77,0.79,0.78)
        if mode == "aquarium", let url=Bundle(for:GQWorldSCNView.self).url(forResource:"AquariumPanoramaV352",withExtension:"png") {
            scene.background.contents = GQSharedArt.image(url)
        }
        if mode == "fishing", let url=Bundle(for:GQWorldSCNView.self).url(forResource:"FishingGameSceneV15",withExtension:"png") {
            scene.background.contents = GQSharedArt.image(url)
        }
        if mode == "battle" || mode == "camp",
           let url = Bundle(for:GQWorldSCNView.self).url(forResource:mode == "battle" ? "AdventureBattleV353" : "AdventureCampV353",withExtension:"png") {
            scene.background.contents = GQSharedArt.image(url)
        }
        let root = scene.rootNode
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 100
        root.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedWhite: 0.68, alpha: 1); root.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.color = NSColor(calibratedWhite: 0.96, alpha: 1)
        sun.light?.castsShadow = true; sun.light?.shadowRadius = 5
        sun.eulerAngles = SCNVector3(-0.9,0.7,-0.35); root.addChildNode(sun)
        premiumLighting(scene,mode:mode)
        let worldStage = items.first(where: { $0.kind == "__world" })?.level ?? 0
        if mode == "interior" {
            if let carriage=items.first(where:{ $0.kind != "__world" }) { trainInteriorGround(root, item:carriage) }
            return scene
        }
        switch mode {
        case "island": premiumIslandGround(root, stage: worldStage)
        case "cat": premiumCatRoom(root, stage: worldStage)
        case "station": explorerPort(root,stage:worldStage)
        case "expedition": explorerPlanet(root,index:worldStage)
        case "farm", "pasture", "fishing", "aquarium": estateGround(root, mode:mode, stage:worldStage)
        case "battle", "camp": adventureGround(root, mode:mode, stage:worldStage)
        default: premiumTrainGround(root, stage: worldStage)
        }
        for item in items where item.kind != "__world" {
            let node = SCNNode(); node.name = "item:\(item.id)"
            node.position = SCNVector3(Float(item.x), 0, Float(item.z))
            if mode == "battle" && item.kind.hasPrefix("pet") { node.position.y = -1.55 }
            if mode == "camp" {
                let floors: [String:CGFloat] = ["forge":3.0,"study":2.0,"stable":-2.0,"altar":-2.3]
                node.position = SCNVector3(CGFloat(item.x), floors[item.id] ?? 0, 0)
            }
            root.addChildNode(node)
            switch mode {
            case "island": premiumIslandBuilding(node, item)
            case "cat": catItem(node, item)
            case "station": explorerFacility(node,item)
            case "expedition": explorerShip(node,level:item.level)
            case "farm", "pasture", "fishing", "aquarium": estateObject(node, mode:mode, item:item)
            case "battle", "camp": adventureObject(node, mode:mode, item:item)
            default: premiumTrainCar(node, item)
            }
            if selectedID == item.id {
                let ring = SCNTorus(ringRadius: mode == "train" ? 1.08 : 0.95, pipeRadius: 0.035)
                ring.materials = [mat(color(1,0.72,0.25), metal: 0.5)]
                let marker = SCNNode(geometry: ring); marker.position.y = 0.07
                node.addChildNode(marker)
            }
            if (mode == "battle" || mode == "camp") && !item.title.isEmpty && !item.kind.hasPrefix("pet") {
                adventureLabel(node,text:item.title,y:mode == "camp" ? -0.22 : item.kind.hasPrefix("pet") ? 1.5 : 3.6)
            }
            if mode == "aquarium" {
                swimResident(node, item:item)
            }
            if !item.title.isEmpty && ["island","cat","station","train"].contains(mode) {
                worldPlaque(node,item:item,mode:mode)
                node.childNode(withName:"world-plaque",recursively:false)?.isHidden = selectedID != item.id
            }

        }
        if mode == "station" || mode == "expedition" { explorerMatteFinish(root) }
        return scene
    }
    static func islandGround(_ root: SCNNode, stage: Int) {
        box(root, 100, 0.08, 100, 0,-0.55,0,color(0.14,0.55,0.68),chamfer:0)
        cylinder(root, 7.8, 0.55, 0,-0.23,0,color(0.88,0.75,0.47))
        cylinder(root, 7.1, 0.21, 0,0.13,0,color(0.30,0.60,0.37))
        for i in 0..<13 {
            let a = Float(i) * 0.71
            let x = sin(a) * 6.6, z = cos(a) * 6.6
            cylinder(root, 0.14, 0.55, x,0.51,z,color(0.47,0.34,0.22))
            sphere(root, 0.45, x,0.93,z,color(0.16,0.46,0.30))
            sphere(root, 0.35, x+0.25,0.81,z,color(0.22,0.55,0.34))
        }
        for i in 0..<9 {
            let z = Float(i-4) * 1.35
            box(root, 0.4, 0.018, 1.15, -0.9,0.25,z,color(0.80,0.69,0.46),chamfer:0.1)
        }
        if stage >= 1 {
            cylinder(root,2.2,0.37,5.9,-0.15,1.9,color(0.86,0.72,0.45))
            cylinder(root,1.85,0.16,5.9,0.10,1.9,color(0.31,0.58,0.36))
            box(root,2.0,0.11,0.8,4.5,0.20,1.3,color(0.53,0.37,0.22))
        }
        if stage >= 2 {
            cylinder(root,1.8,0.37,-5.9,-0.14,-2.0,color(0.85,0.70,0.44))
            cylinder(root,1.4,0.16,-5.9,0.10,-2.0,color(0.30,0.56,0.34))
            for x: Float in [-6.4,-5.8,-5.2] { cone(root,0.37,0,1.0,x,0.69,-2.2,color(0.20,0.48,0.32)) }
        }
        if stage >= 3 {
            box(root,3.2,0.12,0.8,0.1,0.05,7.2,color(0.52,0.39,0.27))
            for x: Float in [-1.3,1.3] { cylinder(root,0.08,0.6,x,-0.23,7.2,color(0.55,0.39,0.28)) }
        }
    }
    static func legacyIslandBuilding(_ n: SCNNode, _ item: GQWorldItem) {
        let level = max(1,item.level)
        let wood = color(0.56,0.37,0.24), cream = color(0.93,0.83,0.62)
        let roof = color(0.24,0.41,0.41), leaf = color(0.26,0.57,0.40)
        cylinder(n, 0.98, 0.08, 0,0.24,0,color(0.70,0.62,0.47))
        switch item.kind {
        case "campfire":
            for i in 0..<6 { let a = Float(i) * Float.pi / 3; box(n,0.16,0.15,0.75,sin(a)*0.28,0.38,cos(a)*0.28,wood).eulerAngles.y = CGFloat(a) }
            cone(n,0.28,0,0.62,0,0.67,0,color(1,0.48,0.13))
            if level >= 3 { for x: Float in [-0.7,0.7] { cylinder(n,0.05,1.6,x,1.05,0,wood) }; box(n,1.5,0.08,0.13,0,1.8,0,wood) }
        case "well":
            cylinder(n,0.62,0.65,0,0.58,0,color(0.65,0.67,0.64))
            cylinder(n,0.43,0.04,0,0.93,0,color(0.15,0.45,0.65))
            for x: Float in [-0.55,0.55] { cylinder(n,0.055,1.15,x,1.0,0,wood) }
            cone(n,0.82,0,0.43,0,1.65,0,roof)
            if level >= 3 { cylinder(n,0.32,0.50,0,2.05,0,color(0.29,0.63,0.77)) }
        case "garden", "farm", "herbGarden":
            box(n,1.62,0.34,1.50,0,0.42,0,wood)
            box(n,1.42,0.05,1.28,0,0.62,0,color(0.35,0.29,0.21))
            for x in [-0.44,0,0.44] { for z in [-0.37,0.18] {
                sphere(n,item.kind == "farm" ? 0.19 : 0.13,Float(x),0.85,Float(z),
                       item.kind == "herbGarden" ? color(0.62,0.43,0.74) : leaf)
            } }
            if level >= 3 {
                for x: Float in [-0.72,0.72] { cylinder(n,0.04,1.1,x,1.1,0,cream) }
                let glass = box(n,1.55,0.06,1.5,0,1.64,0,color(0.54,0.82,0.86),metal:0.12)
                glass.eulerAngles.z = 0.14
            }
        default:
            let h = CGFloat(0.75 + Double(level-1)*0.25)
            box(n,1.35,h,1.18,0,Float(0.26+h/2),0,cream)
            box(n,0.35,0.62,0.025,0,0.59,0.605,wood)
            for x: Float in [-0.43,0.43] { box(n,0.22,0.25,0.03,x,0.82,0.61,color(0.38,0.68,0.78),metal:0.08) }
            let r = box(n,1.60,0.20,1.42,0,Float(0.34+h),0,roof)
            r.eulerAngles.z = item.kind == "shelter" ? 0.06 : 0
            if level >= 2 { box(n,1.62,0.10,1.43,0,Float(0.17+h),0,color(0.86,0.63,0.33)) }
            if level >= 3 { cylinder(n,0.19,0.86,0.42,Float(0.8+h),-0.25,wood); cone(n,0.31,0,0.32,0.42,Float(1.32+h),-0.25,roof) }
            if level >= 4 { for x: Float in [-0.53,0.53] { cylinder(n,0.035,0.8,x,Float(0.8+h),0.49,color(0.93,0.82,0.49)) } }
        }
        finishIsland(n,kind:item.kind,level:level)
    }
    static func catRoom(_ root: SCNNode, stage: Int) {
        box(root,14,0.35,10,0,-0.19,0,color(0.73,0.55,0.39),chamfer:0.2)
        for i in -6...6 { box(root,0.028,0.012,9.6,Float(i),0.01,0,color(0.54,0.36,0.23),chamfer:0) }
        box(root,14,4.6,0.22,0,2.15,-4.8,color(0.94,0.89,0.79),chamfer:0.08)
        box(root,0.22,4.6,10,-6.9,2.15,0,color(0.93,0.87,0.77),chamfer:0.08)
        box(root,2.4,1.6,0.08,2.9,2.8,-4.63,color(0.49,0.74,0.84),metal:0.1)
        for x: Float in [1.66,4.14] { box(root,0.08,1.9,0.15,x,2.8,-4.53,.white) }
        box(root,2.8,0.08,0.15,2.9,3.7,-4.52,.white)
        box(root,4.4,0.025,3.1,0,0.02,0.7,color(0.91,0.74,0.59),chamfer:0.6)
        box(root,2.4,0.82,0.76,-2.0,0.48,-4.1,color(0.55,0.73,0.65))
        for x: Float in [-2.9,-1.1] { box(root,0.24,0.75,0.24,x,0.95,-4.10,color(0.85,0.65,0.42)) }
        if stage >= 3 {
            box(root,3.4,0.31,4.8,8.2,-0.18,1.6,color(0.77,0.59,0.44))
            box(root,0.18,3.5,5,9.8,1.61,1.6,color(0.94,0.88,0.78))
            box(root,2.2,0.16,1.4,8.2,0.08,2.1,color(0.41,0.64,0.48))
            for x: Float in [7.3,8.3,9.1] { sphere(root,0.27,x,0.55,2.3,color(0.23,0.56,0.36)) }
        }
        if stage >= 5 {
            box(root,3.0,0.19,2.4,-4.9,0.04,6.0,color(0.84,0.71,0.55))
            for x: Float in [-5.8,-4.7,-3.8] { sphere(root,0.30,x,0.44,6.0,color(0.89,0.54,0.55)) }
        }
    }
    static func catItem(_ n: SCNNode, _ item: GQWorldItem) {
        let wood = color(0.69,0.48,0.29), teal = color(0.34,0.66,0.64)
        if item.kind == "cat" { premiumCat(n,coat:item.level); return }
        defer { refineCatFacility(n,item) }
        let level = max(1,item.level)
        if item.kind.hasPrefix("furniture") {
            let index = Int(item.kind.dropFirst("furniture".count)) ?? 0
            switch index {
            case 0:
                let rug=cylinder(n,0.86,0.035,0,0.10,0,color(0.87,0.49,0.41)); rug.scale.z=0.72
                cylinder(n,0.55,0.04,0,0.13,0,color(0.94,0.70,0.55))
            case 1:
                for x: Float in [-0.50,0.50] { box(n,0.46,1.45,0.09,x,0.84,0,color(0.40,0.65,0.65)) }
                box(n,1.34,0.11,0.12,0,1.58,0,wood)
            case 2:
                let board=box(n,0.64,0.08,1.30,0,0.59,0,wood); board.eulerAngles.x = -0.55
                cylinder(n,0.20,0.10,0,0.20,-0.55,teal)
            case 3:
                cylinder(n,0.68,0.26,0,0.23,0,color(0.68,0.60,0.49))
                cylinder(n,0.56,0.03,0,0.38,0,color(0.31,0.68,0.78),metal:0.13)
                sphere(n,0.13,0.22,0.48,0.10,color(0.95,0.63,0.28))
            case 4:
                box(n,1.20,1.05,0.08,0,0.75,0,wood)
                box(n,1.04,0.89,0.09,0,0.75,0,color(0.63,0.76,0.71))
                sphere(n,0.22,0.23,0.85,0.06,color(0.91,0.66,0.44))
            default:
                cylinder(n,0.38,0.08,0,0.13,0,wood)
                cylinder(n,0.07,1.25,0,0.78,0,color(0.71,0.66,0.52),metal:0.25)
                cone(n,0.43,0.24,0.52,0,1.58,0,color(0.97,0.84,0.60))
            }
            return
        }
        box(n,1.65,0.11,1.35,0,0.15,0,color(0.82,0.69,0.52))
        switch item.kind {
        case "pantry":
            box(n,1.42,CGFloat(0.7+0.15*Double(level)),0.92,0,0.58,0,wood)
            box(n,1.3,0.08,0.18,0,1.05,0.55,color(0.95,0.86,0.68))
            for x: Float in [-0.4,0.4] { cylinder(n,0.18,0.12,x,1.12,0.14,color(0.90,0.52,0.42),metal:0.25) }
        case "playroom":
            for x: Float in [-0.5,0.5] { cylinder(n,0.09,1.45,x,0.87,0,wood) }
            box(n,1.25,0.09,0.6,0,1.58,0,teal)
            sphere(n,0.23,0,0.42,0.35,color(0.89,0.55,0.47))
            if level >= 3 { cylinder(n,0.12,0.8,0.5,1.96,0,wood); box(n,0.6,0.07,0.55,0.5,2.34,0,teal) }
        case "greenhouse":
            for x: Float in [-0.42,0.42] { foliage(n,index:3,x:x,y:0.2,z:0,height:1.1) }
            if level >= 2 { let glass=box(n,1.6,0.035,1.3,0,1.5,0,color(0.58,0.83,0.84),metal:0.14);glass.geometry?.firstMaterial?.transparency=0.28 }
        default:
            detailBox(n,1.5,0.06,1.16,0,0.22,0,1)
            if level >= 3 { for x:Float in [-0.55,0.55] { cylinder(n,0.035,0.65,x,0.6,-0.5,wood) } }
        }
    }
    static func stationGround(_ root: SCNNode, stage: Int) {
        for i in 0..<65 {
            let a = Float(i*41 % 360) * Float.pi / 180
            let r = Float(8 + (i*17 % 12))
            sphere(root,0.025,sin(a)*r,Float((i*7)%11)-5,cos(a)*r,.white)
        }
        cylinder(root,1.48,0.78,0,0,0,color(0.35,0.42,0.52),metal:0.75)
        cylinder(root,1.15,0.36,0,0.56,0,color(0.19,0.58,0.69),metal:0.58)
        sphere(root,0.72,0,1.05,0,color(0.55,0.80,0.88),metal:0.4)
        let ring = SCNTorus(ringRadius: 1.82, pipeRadius: 0.17)
        ring.materials = [mat(color(0.60,0.68,0.76),metal:0.8)]
        let node = SCNNode(geometry:ring); node.position.y = 0.46; root.addChildNode(node)
        node.runAction(.repeatForever(.rotateBy(x:0,y:CGFloat.pi*2,z:0,duration:28)))
        for x: Float in [-2.7,2.7] {
            box(root,2.1,0.08,0.85,x,0.18,0,color(0.12,0.35,0.61),metal:0.4)
            for j in -2...2 { box(root,0.02,0.085,0.85,x+Float(j)*0.39,0.23,0,color(0.54,0.72,0.84),metal:0.7) }
        }
        if stage >= 2 {
            for z: Float in [-2.8,2.8] { box(root,1.8,0.07,0.7,0,0.17,z,color(0.18,0.38,0.64),metal:0.48) }
        }
        if stage >= 3 {
            let outer=SCNTorus(ringRadius:2.7,pipeRadius:0.08)
            outer.materials=[mat(color(0.37,0.76,0.86),metal:0.5)]
            let n=SCNNode(geometry:outer); n.position.y=0.24; root.addChildNode(n)
        }
        if stage >= 4 { sphere(root,0.38,0,2.3,0,color(0.72,0.89,0.94),metal:0.5) }
    }
    static func stationPod(_ n: SCNNode, _ item: GQWorldItem) {
        if item.kind == "account" {
            cylinder(n,0.43,0.17,0,0.12,0,color(0.32,0.40,0.51),metal:0.65)
            cylinder(n,0.29,0.53,0,0.48,0,color(0.44,0.57,0.68),metal:0.6)
            sphere(n,0.25,0,0.88,0,color(0.34,0.83,0.90),metal:0.3)
            let pulse=sphere(n,0.07,0,1.2,0,color(0.95,0.84,0.58))
            pulse.runAction(.repeatForever(.sequence([.fadeOpacity(to:0.22,duration:1.1),.fadeOpacity(to:1,duration:1.1)])))
            return
        }
        let level = max(1,item.level)
        let trim = item.kind == "compute" ? color(0.37,0.75,0.95) : item.kind == "archive" ? color(0.68,0.58,0.91) : item.kind == "studio" ? color(0.97,0.63,0.40) : color(0.44,0.82,0.61)
        box(n,1.8,0.28,0.32,0,0.32,1.12,color(0.47,0.56,0.67),metal:0.7)
        cylinder(n,0.88,0.98,0,0.70,0,color(0.31,0.38,0.48),metal:0.7)
        cylinder(n,0.72,0.06,0,1.22,0,trim,metal:0.4)
        sphere(n,0.56,0,1.43,0,color(0.53,0.72,0.81),metal:0.25)
        for i in 0..<6 { let a = Float(i) * Float.pi / 3; box(n,0.11,0.50,0.15,sin(a)*0.76,0.72,cos(a)*0.76,trim,metal:0.4).eulerAngles.y = CGFloat(a) }
        if level >= 2 { for x: Float in [-0.68,0.68] { box(n,0.46,0.06,1.4,x,0.85,0,color(0.17,0.43,0.70),metal:0.5) } }
        if level >= 3 { cylinder(n,0.13,0.64,0,2.2,0,color(0.75,0.80,0.88),metal:0.7); sphere(n,0.18,0,2.58,0,trim,metal:0.3) }
        if level >= 4 { let ring=SCNTorus(ringRadius:1.1,pipeRadius:0.055); ring.materials=[mat(trim,metal:0.5)]; let r=SCNNode(geometry:ring); r.position.y=1.0; n.addChildNode(r); r.runAction(.repeatForever(.rotateBy(x:0,y:CGFloat.pi*2,z:0,duration:12))) }
        let bot=sphere(n,0.13,0.95,1.1,0,trim,metal:0.5)
        bot.runAction(.repeatForever(.sequence([.moveBy(x:-1.9,y:0.15,z:0,duration:3),.moveBy(x:1.9,y:-0.15,z:0,duration:3)])))
        finishStation(n,kind:item.kind,level:level)
    }
    static func trainGround(_ root: SCNNode, stage: Int) {
        let landscape = stage == 1 ? color(0.83,0.82,0.73) : stage == 2 ? color(0.75,0.85,0.87) : color(0.40,0.65,0.49)
        box(root,100,0.10,100,0,-0.47,0,landscape,chamfer:0)
        box(root,17,0.20,2.15,0,-0.30,0,color(0.54,0.53,0.47),chamfer:0)
        for i in -15...15 { box(root,0.16,0.08,2.35,Float(i)*0.53,-0.13,0,color(0.41,0.32,0.24),chamfer:0.02) }
        for z: Float in [-0.68,0.68] { box(root,17,0.08,0.07,0,-0.06,z,color(0.72,0.74,0.76),metal:0.8) }
        for i in 0..<11 {
            let x=Float(i*19%17)-8, z=Float((i*13)%4)*0.7+2.2
            cylinder(root,0.10,0.8,x,0.1,z,color(0.46,0.34,0.24))
            cone(root,0.53,0,1.3,x,1.06,z,stage == 2 ? color(0.84,0.91,0.90) : color(0.16,0.48,0.32))
        }
        for x: Float in [-5.9,5.7] { box(root,1.05,0.10,0.82,x,0.02,-2.25,color(0.82,0.75,0.57)) }
    }
    static func legacyTrainCar(_ n: SCNNode, _ item: GQWorldItem) {
        if item.kind == "ghost" {
            let frame = SCNBox(width:2.04,height:1.15,length:1.24,chamferRadius:0.04)
            let blueprint=mat(color(0.22,0.78,0.75),metal:0.15)
            blueprint.fillMode = .lines
            blueprint.lightingModel = .constant
            frame.materials=[blueprint]
            let body=SCNNode(geometry:frame); body.position.y=1.06; n.addChildNode(body)
            for x: Float in [-0.68,0.68] { for z: Float in [-0.5,0.5] {
                let wheel=cylinder(n,0.20,0.07,x,0.28,z,color(0.24,0.55,0.54))
                wheel.eulerAngles.x = .pi/2
            } }
            return
        }
        let level=max(1,item.level)
        let base=item.kind == "engine" ? color(0.16,0.47,0.52) : color(0.76,0.36,0.24)
        let dark=color(0.20,0.27,0.31), gold=color(0.88,0.70,0.40)
        box(n,2.1,0.19,1.35,0,0.55,0,dark,metal:0.45)
        for x: Float in [-0.68,0.68] { for z: Float in [-0.5,0.5] {
            let wheel=cylinder(n,0.23,0.12,x,0.30,z,dark,metal:0.45); wheel.eulerAngles.x = .pi/2
            wheel.runAction(.repeatForever(.rotateBy(x:0,y:CGFloat.pi*2,z:0,duration:3)))
        } }
        box(n,1.85,0.92,1.22,0,1.13,0,base,metal:0.18)
        box(n,2.05,0.16,1.36,0,1.68,0,level >= 3 ? gold : dark,metal:0.26)
        for x: Float in [-0.62,-0.2,0.22,0.64] {
            box(n,0.27,0.31,0.025,x,1.24,-0.625,color(0.48,0.78,0.86),metal:0.12)
            box(n,0.27,0.31,0.025,x,1.24,0.625,color(0.48,0.78,0.86),metal:0.12)
        }
        if item.kind == "engine" {
            cylinder(n,0.23,1.10,-0.55,1.0,0,gold,metal:0.42)
            cylinder(n,0.13,0.60,-0.57,1.80,0,dark,metal:0.52)
            sphere(n,0.20,-1.02,1.08,0,color(1,0.84,0.50))
        } else if level >= 2 {
            for z: Float in [-0.51,0.51] { box(n,1.60,0.06,0.08,0,1.68,z,gold,metal:0.42) }
        }
        if level >= 4 { box(n,0.48,0.32,0.48,0,1.92,0,color(0.51,0.75,0.80),metal:0.20) }
        finishTrain(n,kind:item.kind,level:level)
    }
    static func trainInteriorGround(_ root:SCNNode,item:GQWorldItem) {
        let wood=color(0.66,0.44,0.28), cream=color(0.93,0.84,0.67), teal=color(0.25,0.55,0.57)
        detailBox(root,7.5,0.28,3.0,0,-0.15,0,1)
        box(root,7.5,2.8,0.13,0,1.25,-1.45,cream)
        box(root,0.13,2.8,3.0,-3.7,1.25,0,cream)
        box(root,0.13,2.8,3.0,3.7,1.25,0,cream)
        for x:Float in [-2.35,0,2.35] {
            box(root,1.55,1.20,0.08,x,1.65,-1.36,color(0.44,0.74,0.82),metal:0.12)
            box(root,1.72,0.07,0.15,x,2.3,-1.30,wood)
            for side:Float in [-0.83,0.83] { box(root,0.07,1.25,0.16,x+side,1.65,-1.3,wood) }
        }
        for x:Float in [-2.7,-0.9,0.9,2.7] {
            cylinder(root,0.15,0.10,x,2.55,0,color(0.99,0.87,0.55),metal:0.15)
        }
        switch item.kind {
        case "sleeper":
            for x:Float in [-2.2,0.2,2.4] {
                box(root,1.7,0.28,1.0,x,0.37,0.45,teal)
                box(root,0.55,0.12,0.72,x-0.45,0.59,0.45,cream)
            }
        case "dining":
            for x:Float in [-2.2,0,2.2] {
                box(root,1.35,0.12,0.75,x,0.80,0.05,wood)
                for z:Float in [-0.55,0.55] { box(root,0.62,0.32,0.48,x,0.29,z,teal) }
                cylinder(root,0.18,0.08,x,0.91,0.05,color(0.97,0.91,0.80))
            }
        case "observation":
            for x:Float in [-2.2,0,2.2] {
                box(root,1.35,0.27,0.75,x,0.30,0.3,teal)
                box(root,1.35,0.68,0.18,x,0.75,-0.12,teal)
            }
            cylinder(root,0.17,1.24,0,0.63,1.03,color(0.62,0.68,0.71),metal:0.6)
            sphere(root,0.27,0,1.3,1.03,color(0.37,0.58,0.68),metal:0.3)
        case "garden":
            for x:Float in [-2.4,-0.8,0.8,2.4] {
                cylinder(root,0.32,0.28,x,0.18,0.65,wood)
                sphere(root,0.39,x,0.75,0.65,color(0.28,0.62,0.39))
                sphere(root,0.20,x+0.15,1.0,0.65,color(0.84,0.48,0.52))
            }
        default:
            for x:Float in [-2.3,0,2.3] {
                box(root,1.6,1.35,0.45,x,0.72,0.45,wood)
                for y:Float in [0.40,0.75,1.10] { box(root,1.45,0.07,0.48,x,y,0.48,cream) }
                for offset:Float in [-0.45,0,0.45] { box(root,0.15,0.26,0.22,x+offset,0.95,0.48,teal) }
            }
        }
        box(root,6.9,0.015,0.35,0,0.02,1.1,color(0.49,0.27,0.22),chamfer:0.02)
        for x:Float in [-2.35,0,2.35] {
            for side:Float in [-0.68,0.68] { for j in 0..<3 { cylinder(root,0.028,1.16,x+side+Float(j)*0.035,1.68,-1.23,color(0.55,0.34,0.27)) } }
            box(root,1.52,0.035,0.14,x,1.03,-1.2,color(0.75,0.56,0.31))
            if item.kind == "dining" {
                for z:Float in [-0.22,0.22] { cylinder(root,0.12,0.015,x,0.91,z,.white);cylinder(root,0.034,0.15,x+0.29,0.98,z,color(0.78,0.82,0.74),metal:0.2) }
                cylinder(root,0.06,0.22,x,1.02,0,cream);glow(sphere(root,0.038,x,1.16,0,color(0.96,0.74,0.35)),cream)
            }
            if item.kind == "garden" { foliage(root,index:3,x:x,y:0.22,z:0.3,height:1.0) }
        }
        if item.level>=3 { for x:Float in [-3.4,3.4] { cylinder(root,0.06,2.5,x,1.27,1.24,color(0.87,0.68,0.39),metal:0.28) } }
    }
}
