import AppKit
import SceneKit

extension GQWorldBuilder {
    // State plates share a fixed baseline within each row, independent of species and growth.
    static func estateBadge(_ parent: SCNNode, item:GQWorldItem, mode:String) {
        parent.childNode(withName:"estate-badge",recursively:true)?.removeFromParentNode()
        guard !item.title.isEmpty else { return }
        let hasDetail = item.progress != nil || !item.status.isEmpty
        let size=NSSize(width:300,height:hasDetail ? 104 : 62)
        let image=NSImage(size:size)
        image.lockFocus()
        NSColor(calibratedRed:0.07,green:0.16,blue:0.13,alpha:0.88).setFill()
        NSBezierPath(roundedRect:NSRect(origin:.zero,size:size),xRadius:20,yRadius:20).fill()
        let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center
        (item.title as NSString).draw(in:NSRect(x:8,y:size.height-51,width:284,height:47),withAttributes:[.font:NSFont.systemFont(ofSize:46,weight:.semibold),.foregroundColor:NSColor.white,.paragraphStyle:paragraph])
        if !item.status.isEmpty {
            (item.status as NSString).draw(in:NSRect(x:8,y:22,width:284,height:32),withAttributes:[.font:NSFont.systemFont(ofSize:29,weight:.medium),.foregroundColor:NSColor(calibratedWhite:0.94,alpha:1),.paragraphStyle:paragraph])
        }
        if let progress=item.progress {
            NSColor.white.withAlphaComponent(0.20).setFill()
            NSBezierPath(roundedRect:NSRect(x:19,y:10,width:262,height:8),xRadius:4,yRadius:4).fill()
            (progress >= 1 ? NSColor.systemYellow : NSColor(calibratedRed:0.40,green:0.88,blue:0.63,alpha:1)).setFill()
            NSBezierPath(roundedRect:NSRect(x:19,y:10,width:max(0,262*min(1,max(0,progress))),height:8),xRadius:4,yRadius:4).fill()
        }
        image.unlockFocus()
        let plane=SCNPlane(width:1.70,height:hasDetail ? 0.55 : 0.33)
        let material=SCNMaterial(); material.diffuse.contents=image; material.lightingModel = .constant
        material.isDoubleSided=true; plane.materials=[material]
        let badge=SCNNode(geometry:plane); badge.name="estate-badge";badge.castsShadow=false
        // Specimens fit an opaque-art slot no taller than 0.86. The plate
        // starts at 0.905, keeping the entire unit within its own projected row.
        let holder: SCNNode
        if let specimen=parent.childNode(withName:"estate-specimen",recursively:false) {
            holder=specimen
        } else {
            holder=SCNNode(); holder.name="estate-badge-anchor"
            holder.position.y = mode == "farm" ? 0.12 : 0.07
            holder.position.z=0.42
            holder.constraints=[SCNBillboardConstraint()]
            parent.childNode(withName:"estate-badge-anchor",recursively:false)?.removeFromParentNode()
            parent.addChildNode(holder)
        }
        badge.position=SCNVector3(0,1.18,0.025)
        holder.addChildNode(badge)
    }

    private static var surfaceImages:[String:NSImage]=[:]
    static func meadowMaterial(_ type:String) -> SCNMaterial {
        let m=mat(.white,rough:1)
        if type != "soil", let url=Bundle(for:GQWorldSCNView.self).url(forResource:"EstateMeadowV352",withExtension:"png"), let image=GQSharedArt.image(url) {
            m.diffuse.contents=image
            m.multiply.contents=type == "pasture" ? color(1,0.82,0.48) : color(0.80,0.94,0.76)
            return m
        }
        if let image=surfaceImages[type] { m.diffuse.contents=image; return m }
        let image=NSImage(size:NSSize(width:512,height:512)); image.lockFocus()
        let base = type == "farm" ? color(0.31,0.53,0.24) : type == "pasture" ? color(0.62,0.60,0.32) : color(0.29,0.19,0.12)
        base.setFill(); NSRect(x:0,y:0,width:512,height:512).fill()
        // Deterministic blades, flecks and grain; no enlarged fragments of old scenery.
        for i in 0..<2600 {
            let x=CGFloat((i*137+19)%512), y=CGFloat((i*83+i*i*7)%512)
            let light=CGFloat(i%7)/40
            base.blended(withFraction:light+0.08,of:i%3 == 0 ? .black : .white)!.setStroke()
            let p=NSBezierPath(); p.lineWidth=CGFloat(1+i%2)
            p.move(to:NSPoint(x:x,y:y)); p.line(to:NSPoint(x:x+CGFloat(i%5-2),y:y+CGFloat(2+i%7))); p.stroke()
        }
        image.unlockFocus(); surfaceImages[type]=image; m.diffuse.contents=image
        return m
    }
    static func terrainSheet(_ root:SCNNode, type:String, width:CGFloat, depth:CGFloat, y:Float) {
        let plane=SCNPlane(width:width,height:depth), m=meadowMaterial(type)
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform=SCNMatrix4MakeScale(width/5,depth/5,1)
        plane.materials=[m]; let n=SCNNode(geometry:plane); n.eulerAngles.x = -.pi/2; n.position.y=CGFloat(y); root.addChildNode(n)
    }
    static func beam(_ root:SCNNode, from a:SCNVector3, to b:SCNVector3, radius:CGFloat, tint:NSColor) {
        let length=sqrt(pow(b.x-a.x,2)+pow(b.y-a.y,2)+pow(b.z-a.z,2))
        let g=SCNCylinder(radius:radius,height:length); g.radialSegmentCount=8; g.materials=[mat(tint)]
        let n=SCNNode(geometry:g); n.position=SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
        n.look(at:b,up:SCNVector3(0,0,1),localFront:SCNVector3(0,1,0)); root.addChildNode(n)
    }
    static func refinedEstateGround(_ root:SCNNode,mode:String,stage:Int) {
        if mode == "aquarium" {
            // The viewing window has no opaque walls. The backdrop supplies depth,
            // while actual residents swim through the open three-dimensional volume.
            for i in 0..<17 {
                let bubble=sphere(root,0.025+CGFloat(i%3)*0.012,Float(i%7-3)*2.6,-2,Float(i%4-3),color(0.60,0.90,0.92))
                bubble.opacity=0.3
                bubble.runAction(.repeatForever(.sequence([.wait(duration:Double(i)*0.35),.moveBy(x:0.5,y:12,z:0,duration:11+Double(i%4)),.moveBy(x:-0.5,y:-12,z:0,duration:0)])))
            }
            return
        }
        if mode == "fishing" { lakeAtmosphere(root); return }
        terrainSheet(root,type:mode == "pasture" ? "pasture" : "farm",width:60,depth:60,y:-0.32)
        // Deliberately keep trees on the outer perimeter, clear of selectable plots.
        for i in 0..<18 {
            let x:Float = i<10 ? Float(i-5)*2.7 : (i%2 == 0 ? -12.5 : 12.5)
            let z:Float = i<10 ? -10.5 : Float(i-14)*2.5
            worldTree(root,x:x,z:z,tint:mode == "pasture" && i%3 == 0 ? color(0.58,0.54,0.25) : color(0.18,0.43,0.24),scale:0.85+Float(i%3)*0.16)
        }
        let wood=color(0.58,0.39,0.22)
        for x:Float in [-6.45,6.45] {
            for i in 0..<9 { cylinder(root,0.055,0.58,x,0.03,Float(i-4)*1.55,wood) }
            for y:Float in [0.02,0.28] { box(root,0.07,0.07,12.5,x,y,0,wood) }
        }
        for i in 0..<17 { box(root,0.72,0.025,0.43,Float(i-8)*0.87,-0.23,6.1,color(0.66,0.63,0.48),chamfer:0.08) }
        for i in 0..<95 {
            let x:Float=Float((i*19)%180)/10-9
            let z:Float=Float((i*31)%170)/10-8.5
            if abs(x)<6.7 && abs(z)<6.6 { continue }
            for j in 0..<3 {
                let stem=box(root,0.025,0.12+CGFloat(j)*0.055,0.022,x+Float(j)*0.045,-0.18,z,color(0.28,0.47,0.23),chamfer:0)
                stem.eulerAngles.z=CGFloat(j-1)*0.28
            }
            if i%4 == 0 { sphere(root,0.055,x,-0.02,z,i%2 == 0 ? color(0.98,0.89,0.56) : color(0.92,0.69,0.77)) }
        }
        if mode == "farm" {
            for row in 0..<5 { for column in 0..<5 {
                let x=Float(column-2)*2.12,z=Float(row-2)*2.45
                let soil=box(root,1.88,0.13,1.82,x,-0.16,z,color(0.35,0.23,0.14),chamfer:0.10)
                soil.geometry?.materials=[meadowMaterial("soil")]
                for r in 0..<5 { box(root,1.70,0.045,0.028,x,-0.075,z+Float(r-2)*0.31,color(0.26,0.17,0.10),chamfer:0.01) }
            } }
            box(root,0.34,0.07,12.3,-6,-0.19,0,color(0.19,0.57,0.68),chamfer:0.03)
            for x:Float in [-6.25,-5.77] { box(root,0.10,0.10,12.5,x,-0.16,0,color(0.59,0.59,0.43)) }
            box(root,2.0,1.35,1.5,8.1,0.35,-5.8,color(0.68,0.48,0.30))
            for side:Float in [-1,1] { let roof=box(root,1.42,0.12,1.9,8.1+side*0.48,1.30,-5.8,color(0.30,0.43,0.37));roof.eulerAngles.z = CGFloat(-side)*0.45 }
            for i in 0..<3 { cylinder(root,0.22,0.40,7.5+Float(i)*0.55,-0.06,-4.6,color(0.60,0.32,0.19)) }
        } else {
            // Open paddock with hay, trough and a pitched-roof barn outside the herd.
            box(root,2.7,1.60,2.0,8.6,0.45,-5.7,color(0.66,0.29,0.20))
            for side:Float in [-1,1] { let roof=box(root,1.9,0.13,2.4,8.6+side*0.65,1.61,-5.7,color(0.31,0.36,0.34)); roof.eulerAngles.z=CGFloat(-side)*0.42 }
            box(root,0.9,1.2,0.05,8.6,0.20,-4.68,color(0.33,0.23,0.16))
            box(root,1.8,0.35,0.68,-8,0,-1,wood)
            box(root,1.55,0.035,0.50,-8,0.20,-1,color(0.30,0.63,0.69))
            for i in 0..<3 { let hay=cylinder(root,0.42,0.68,7.8+Float(i)*0.8,0.10,3.9,color(0.78,0.65,0.32)); hay.eulerAngles.z = .pi/2 }
        }
    }
    static func lakeAtmosphere(_ root:SCNNode) {
        // Detailed lake panorama with live rod, water glints and float in front.
        beam(root,from:SCNVector3(-5.3,0.4,4),to:SCNVector3(-3.0,2.3,1.5),radius:0.028,tint:color(0.29,0.22,0.16))
        for i in 0..<16 {
            let g=SCNTorus(ringRadius:CGFloat(0.10+Double(i%4)*0.12),pipeRadius:0.006)
            g.materials=[mat(color(0.67,0.87,0.85))]
            let n=SCNNode(geometry:g);n.castsShadow=false
            n.position=SCNVector3(Float((i*37)%95)/10,-0.1,Float((i*17)%90)/10-2)
            n.opacity=0;root.addChildNode(n)
            n.runAction(.repeatForever(.sequence([.wait(duration:Double(i%7)*0.7),.fadeOpacity(to:0.18,duration:0.6),.group([.scale(to:2.3,duration:3.5),.fadeOut(duration:3.5)]),.scale(to:0.6,duration:0)])))
        }
    }
    static func fishingFloat(_ root:SCNNode,item:GQWorldItem) {
        guard item.level>0 else { return }
        let floatNode=SCNNode(); root.addChildNode(floatNode)
        cylinder(floatNode,0.065,0.33,0,0.14,0,color(0.96,0.91,0.77))
        sphere(floatNode,0.10,0,0.12,0,color(0.89,0.26,0.18))
        let bite=item.level==3
        floatNode.runAction(.repeatForever(.sequence([.moveBy(x:0,y:bite ? -0.20 : -0.035,z:0,duration:bite ? 0.20 : 1.0),.moveBy(x:0,y:bite ? 0.20 : 0.035,z:0,duration:bite ? 0.25 : 1.3)])))
        for i in 0..<3 {
            let ring=SCNTorus(ringRadius:0.15,pipeRadius:0.012);ring.materials=[mat(color(0.75,0.94,0.88))]
            let r=SCNNode(geometry:ring);r.position.y = -0.10;root.addChildNode(r)
            r.runAction(.repeatForever(.sequence([.wait(duration:Double(i)*0.5),.group([.scale(to:bite ? 5 : 3,duration:1.6),.fadeOut(duration:1.6)]),.scale(to:1,duration:0),.fadeIn(duration:0)])))
        }
        beam(root,from:SCNVector3(-3-item.x,2.3,1.5-item.z),to:SCNVector3(0,0.18,0),radius:0.008,tint:color(0.77,0.83,0.74))
        if item.level==1 {
            floatNode.position=SCNVector3(-3-item.x,2.3,1.5-item.z)
            floatNode.runAction(.move(to:SCNVector3(0,0,0),duration:0.7),forKey:"cast")
        }
    }
    // Fish artwork faces right. Reflect UVs rather than the billboard's geometry:
    // a negative node scale is unstable when SceneKit recomputes its facing transform.
    static func orientSwimmingFish(_ node: SCNNode, horizontalVelocity: Double) {
        guard let sprite = node.childNode(withName: "fish-sprite", recursively: false),
              let diffuse = sprite.geometry?.firstMaterial?.diffuse else { return }
        var transform = SCNMatrix4Identity
        if horizontalVelocity < 0 {
            transform.m11 = -1
            transform.m41 = 1
        }
        diffuse.contentsTransform = transform
    }

    static func swimResident(_ node:SCNNode,item:GQWorldItem) {
        node.removeAllActions()
        let seed=item.id.utf8.reduce(0) { ($0*31+Int($1))%10007 }
        let start=Double((seed*353)%997)/997 * .pi*2
        let depth=Double(seed%5)*0.6-1.4
        let centerY=1.4+Double(seed%7)*0.63
        let speed=22.0+Double(seed%17)
        let action=SCNAction.customAction(duration:speed) { n,elapsed in
            let t=start+Double(elapsed)/speed * .pi*2
            n.position=SCNVector3(sin(t)*7.6,centerY+sin(t*2+start)*0.40,depth+cos(t)*0.42)
            orientSwimmingFish(n, horizontalVelocity: cos(t))
        }
        node.runAction(.repeatForever(action),forKey:"cruise")
        let scale=0.80+Double(seed%5)*0.08;node.scale=SCNVector3(scale,scale,scale)
        let label=SCNNode();label.name="fish-label";node.addChildNode(label)
        title(label,item.title,y:1.5);label.isHidden=true
    }
}
