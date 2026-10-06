import AppKit
import SceneKit

// The original game art is kept in each feature framework. Transparent art planes
// give each species its own silhouette inside the interactive 3D terrain.
extension GQWorldBuilder {
    private static let cropIDs = ["carrot","potato","wheat","corn","tomato","cabbage",
                                  "cucumber","onion","garlic","pepper","eggplant","broccoli",
                                  "peanut","soybean","rice","strawberry","grape","watermelon",
                                  "pumpkin","sunflower","tea","coffee","apple","peach"]
    private static let animalIDs = ["chicken","duck","goose","rabbit","quail","bee",
                                    "goat","sheep","pig","cow","silkworm","turkey",
                                    "guineafowl","alpaca","donkey","deer","yak","buffalo",
                                    "horse","ostrich","peacock","camel","reindeer","highlandcow"]
    private static var imageCache: [String: NSImage] = [:]

    static func art(_ name: String, index: Int? = nil, columns: Int = 1, rows: Int = 1) -> NSImage? {
        let key = "\(name):\(index ?? -1)"
        if let cached = imageCache[key] { return cached }
        guard let url = Bundle(for: GQWorldSCNView.self).url(forResource: name, withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let image: NSImage
        if let index {
            let col = index % columns, row = index / columns
            let x0 = cg.width * col / columns, x1 = cg.width * (col + 1) / columns
            let y0 = cg.height * row / rows, y1 = cg.height * (row + 1) / rows
            guard let tile = cg.cropping(to: CGRect(x: x0, y: y0, width: x1-x0, height: y1-y0)) else { return nil }
            image = NSImage(cgImage: tile, size: NSSize(width:x1-x0,height:y1-y0))
        } else { image = source }
        imageCache[key] = image
        return image
    }

    @discardableResult private static func picture(_ parent: SCNNode, image: NSImage,
                                                    width: CGFloat, height: CGFloat, y: Float) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position.y = CGFloat(y)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
        parent.addChildNode(node)
        return node
    }

    static func paintedTerrain(_ parent:SCNNode, mode:String, stage:Int) {
        let names=["farm":"FarmGameSceneV15","pasture":"PastureGameSceneV15",
                   "fishing":"FishingGameSceneV15","aquarium":"AquariumGameSceneV15"]
        guard let name=names[mode], let source=art(name),
              let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
        // The middle of each original scene is clear terrain, away from painted buildings.
        let bounds: CGRect
        if mode == "fishing" {
            // Keep this crop fully on the open water; the left side contains a painted dock.
            bounds=CGRect(x:CGFloat(cg.width)*0.55,y:CGFloat(cg.height)*0.44,
                          width:CGFloat(cg.width)*0.20,height:CGFloat(cg.height)*0.27)
        } else {
            let fraction:CGFloat = mode == "aquarium" ? 0.28 : 0.34
            bounds=CGRect(x:CGFloat(cg.width)*(0.5-fraction/2),y:CGFloat(cg.height)*(0.5-fraction/2),
                          width:CGFloat(cg.width)*fraction,height:CGFloat(cg.height)*fraction)
        }
        guard let tile=cg.cropping(to:bounds) else { return }
        let image=NSImage(cgImage:tile,size:bounds.size)
        let dimensions:(CGFloat,CGFloat,Float)=mode == "fishing" ? (32,15,-0.12) :
            mode == "aquarium" ? (12,8.7,0.29) : (70,70,-0.315)
        let plane=SCNPlane(width:dimensions.0,height:dimensions.1)
        let material=mat(.white,rough:0.9)
        material.diffuse.contents=image
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        let repeatCount:CGFloat = mode == "farm" || mode == "pasture" ? 6 : 1
        material.diffuse.contentsTransform=SCNMatrix4MakeScale(repeatCount,repeatCount,1)
        if stage == 2 && (mode == "farm" || mode == "pasture") {
            material.multiply.contents=color(0.82,0.67,0.47)
        } else if stage == 3 && (mode == "farm" || mode == "pasture") {
            material.multiply.contents=color(0.86,0.91,0.90)
        }
        plane.materials=[material]
        let node=SCNNode(geometry:plane)
        node.eulerAngles.x = -.pi/2
        node.position.y=CGFloat(dimensions.2)
        if mode == "fishing" { node.position.z=3 }
        parent.addChildNode(node)
    }

    static func aquariumBackdrop(_ parent:SCNNode) {
        guard let source=art("AquariumGameSceneV15"),
              let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let crop=cg.cropping(to:CGRect(x:CGFloat(cg.width)*0.13,y:CGFloat(cg.height)*0.22,
                                             width:CGFloat(cg.width)*0.74,height:CGFloat(cg.height)*0.43)) else { return }
        let image=NSImage(cgImage:crop,size:NSSize(width:crop.width,height:crop.height))
        let plane=SCNPlane(width:12.1,height:3.25)
        let material=mat(.white,rough:0.5)
        material.diffuse.contents=image
        material.lightingModel = .constant
        material.isDoubleSided=true
        plane.materials=[material]
        let node=SCNNode(geometry:plane)
        node.position=SCNVector3(0,1.72,-4.39)
        parent.addChildNode(node)
    }

    private static func estateSpecimen(_ parent:SCNNode,image:NSImage,width:CGFloat,height:CGFloat,base:CGFloat) {
        let holder=SCNNode();holder.name="estate-specimen";holder.position.y=base;holder.position.z=0.42
        holder.constraints=[SCNBillboardConstraint()]
        let tight = opaqueSprite(image)
        let ratio = tight.size.width / max(1,tight.size.height)
        let fittedHeight = min(0.86, height * 0.68, 1.40 / ratio)
        let plane=SCNPlane(width:fittedHeight * ratio,height:fittedHeight)
        let material=SCNMaterial();material.diffuse.contents=tight;material.lightingModel = .constant
        material.isDoubleSided=true;material.transparencyMode = .aOne;plane.materials=[material]
        let body=SCNNode(geometry:plane);body.position.y=fittedHeight/2;body.castsShadow=false
        holder.addChildNode(body);parent.addChildNode(holder)
    }

    static func illustratedCrop(_ parent: SCNNode, id: String, level: Int) -> Bool {
        guard let index = cropIDs.firstIndex(of: id) else { return false }
        let young = level == 1
        guard let image = art(young ? "CropYoungAtlasV15" : "CropAtlasV15", index:index, columns:6, rows:4) else { return false }
        let scale: CGFloat = young ? 0.60 : level == 2 ? 0.82 : 1.0
        let height: CGFloat = ["apple","peach","corn","sunflower"].contains(id) ? 1.70 : 1.38
        estateSpecimen(parent,image:image,width:1.52*scale,height:height*scale*0.84,base:0.12)
        return true
    }

    static func illustratedAnimal(_ parent: SCNNode, id: String, level: Int) -> Bool {
        guard let index = animalIDs.firstIndex(of:id) else { return false }
        let young = level < 2
        guard let image = art(young ? "AnimalYoungAtlasV23" : "AnimalAtlasV23", index:index, columns:6, rows:4) else { return false }
        let scale: CGFloat = young ? 0.74 : 1.0
        let height: CGFloat = ["horse","ostrich","camel","yak","peacock"].contains(id) ? 1.66 : 1.37
        estateSpecimen(parent,image:image,width:1.53*scale,height:height*scale*0.84,base:0.07)
        if level >= 3 { sphere(parent,0.07,0.66,0.64,0.42,color(1,0.79,0.29),metal:0.28) }
        parent.runAction(.repeatForever(.sequence([.moveBy(x:0.09,y:0,z:0.05,duration:2.5),
                                                  .moveBy(x:-0.09,y:0,z:-0.05,duration:2.5)])))
        return true
    }

    static func illustratedFish(_ parent: SCNNode, id: String, level: Int) -> Bool {
        guard let image = art("Fish-\(id)-V15") else { return false }
        let scale: CGFloat = level >= 4 ? 1.18 : level == 1 ? 0.88 : 1.0
        picture(parent,image:image,width:1.40*scale,height:0.98*scale,y:0.78).name = "fish-sprite"
        parent.runAction(.repeatForever(.sequence([.moveBy(x:0.28,y:0.08,z:0,duration:2.5),
                                                  .moveBy(x:-0.28,y:-0.08,z:0,duration:2.5)])))
        return true
    }

    static func adventureLabel(_ parent: SCNNode, text: String, y: Float) {
        let image = NSImage(size:NSSize(width:360,height:64))
        image.lockFocus()
        NSColor(calibratedRed:0.035,green:0.09,blue:0.11,alpha:0.86).setFill()
        NSBezierPath(roundedRect:NSRect(x:0,y:0,width:360,height:64),xRadius:22,yRadius:22).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (text as NSString).draw(in:NSRect(x:8,y:7,width:344,height:54),withAttributes:[.font:NSFont.systemFont(ofSize:42,weight:.semibold),.foregroundColor:NSColor.white,.paragraphStyle:style])
        image.unlockFocus()
        let node = picture(parent,image:image,width:2.35,height:0.42,y:y)
        node.constraints = [SCNBillboardConstraint()]
    }

    static func illustratedHero(_ parent: SCNNode) -> Bool {
        guard let image = art("AdventureHeroV353") else { return false }
        let node = picture(parent, image: image, width: 2.5, height: 3.75, y: 1.70)
        node.constraints = [SCNBillboardConstraint()]
        return true
    }

    static func illustratedCamp(_ parent: SCNNode, kind: String) -> Bool {
        let kinds = ["forge", "study", "stable", "altar"]
        guard let index = kinds.firstIndex(of: kind), let sheet = art("AdventureBuildingsV353"),
              let cg = sheet.cgImage(forProposedRect:nil, context:nil, hints:nil) else { return false }
        // The painted atlas has a wider left column; use its actual cell boundaries.
        let x: CGFloat = index % 2 == 0 ? 0 : 0.572
        let w: CGFloat = index % 2 == 0 ? 0.572 : 0.428
        let y: CGFloat = index < 2 ? 0 : 0.508
        let h: CGFloat = index < 2 ? 0.508 : 0.492
        guard let crop = cg.cropping(to:CGRect(x:x*CGFloat(cg.width), y:y*CGFloat(cg.height),
                                              width:w*CGFloat(cg.width), height:h*CGFloat(cg.height))) else { return false }
        let height: CGFloat = kind == "study" ? 3.0 : 2.7
        let image = NSImage(cgImage:crop, size:NSSize(width:crop.width,height:crop.height))
        let node = picture(parent,image:image,width:height*w/h,height:height,y:Float(height/2))
        node.constraints = [SCNBillboardConstraint()]
        return true
    }

    static func illustratedMonster(_ parent:SCNNode, index:Int) -> Bool {
        guard (0..<10).contains(index), let image=art("MonsterSpriteSheetV16",index:index,columns:5,rows:2) else { return false }
        picture(parent,image:image,width:2.70,height:3.10,y:1.70)
        return true
    }

    static func illustratedPet(_ parent:SCNNode, index:Int, level:Int) -> Bool {
        guard (0..<12).contains(index) else { return false }
        let stage = level >= 4 ? 2 : level >= 2 ? 1 : 0
        let cell = (index/2)*6 + (index%2)*3 + stage
        guard let image=art("PetSpriteSheetV16",index:cell,columns:6,rows:6) else { return false }
        picture(parent,image:image,width:1.23,height:1.23,y:0.69)
        parent.runAction(.repeatForever(.sequence([.moveBy(x:0.12,y:0,z:0.08,duration:2.2),
                                                  .moveBy(x:-0.12,y:0,z:-0.08,duration:2.2)])))
        return true
    }
}
