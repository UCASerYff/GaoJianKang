import AppKit
import SceneKit

// Authored surface maps are cached once per framework. Geometry, picking and
// saved placements remain real scene nodes; textures only supply surface detail.
extension GQWorldBuilder {
    private static var premiumImages: [Int:NSImage] = [:]
    static func surface(_ quadrant:Int, tint:NSColor = .white, metal:CGFloat = 0.1) -> SCNMaterial {
        let m=mat(tint,metal:metal,rough:quadrant == 3 ? 0.34 : 0.7)
        if premiumImages[quadrant] == nil,
           let url=Bundle(for:GQWorldSCNView.self).url(forResource:"WorldMaterialsV357",withExtension:"png"),
           let im=GQSharedArt.image(url),let cg=im.cgImage(forProposedRect:nil,context:nil,hints:nil),
           let tile=cg.cropping(to:CGRect(x:cg.width/2*(quadrant%2),y:cg.height/2*(quadrant/2),width:cg.width/2,height:cg.height/2)) {
            premiumImages[quadrant]=NSImage(cgImage:tile,size:NSSize(width:tile.width,height:tile.height))
        }
        if let image=premiumImages[quadrant] { m.diffuse.contents=image;m.multiply.contents=tint }
        return m
    }
    // Runtime atlas sampling removes transparent margins without modifying source art.
    static func opaqueSprite(_ image:NSImage) -> NSImage {
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return image }
        let w=cg.width,h=cg.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        guard let ctx=CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        var minX=w,minY=h,maxX=0,maxY=0
        for y in 0..<h { for x in 0..<w where pixels[(y*w+x)*4+3]>32 {
            minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
        } }
        guard maxX>minX,maxY>minY,
              let crop=cg.cropping(to:CGRect(x:max(0,minX-2),y:max(0,minY-2),width:min(w-minX,maxX-minX+5),height:min(h-minY,maxY-minY+5))) else { return image }
        return NSImage(cgImage:crop,size:NSSize(width:crop.width,height:crop.height))
    }
    @discardableResult static func detailBox(_ n:SCNNode,_ w:CGFloat,_ h:CGFloat,_ d:CGFloat,_ x:Float,_ y:Float,_ z:Float,_ texture:Int) -> SCNNode {
        let b=box(n,w,h,d,x,y,z,.white,chamfer:min(0.035,min(w,h,d)/4)); b.geometry?.materials=[(w,h),(d,h),(w,h),(d,h),(w,d),(w,d)].map { u,v in
            let m=surface(texture);m.diffuse.wrapS = .repeat;m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform=SCNMatrix4MakeScale(max(0.25,u/2),max(0.25,v/2),1);return m
        };return b
    }
    @discardableResult static func ring(_ n:SCNNode,r:CGFloat,pipe:CGFloat,y:Float,tint:NSColor) -> SCNNode {
        let g=SCNTorus(ringRadius:r,pipeRadius:pipe);g.ringSegmentCount=64;g.pipeSegmentCount=10;g.materials=[mat(tint,metal:0.45)]
        let node=SCNNode(geometry:g);node.position.y=CGFloat(y);n.addChildNode(node);return node
    }
    static func glow(_ node:SCNNode,_ tint:NSColor) {
        node.geometry?.firstMaterial?.emission.contents=tint;node.geometry?.firstMaterial?.emission.intensity=0.65
    }
    static func pitchedRoof(_ n:SCNNode,w:Float,d:CGFloat,y:Float,tint:NSColor) {
        for side:Float in [-1,1] {
            let roof=box(n,CGFloat(w)*0.61,0.095,d,side*w*0.25,y,0,tint,chamfer:0.02)
            roof.eulerAngles.z=CGFloat(-side)*0.48
            for i in 0..<8 {
                let rib=box(roof,CGFloat(w)*0.61,0.035,0.035,0,0.057,Float(i-4)*Float(d)/8,tint.blended(withFraction:0.16,of:.white)!,chamfer:0.01)
                rib.castsShadow=false
            }
        }
        cylinder(n,0.065,d,0,y+w*0.13,0,tint).eulerAngles.x = .pi/2
    }
    private static var foliageCache:[Int:NSImage]=[:]
    static func foliage(_ n:SCNNode,index:Int,x:Float,y:Float=0,z:Float,height:CGFloat) {
        if foliageCache[index] == nil,let im=art("FoliageV357",index:index,columns:4,rows:2) { foliageCache[index]=opaqueSprite(im) }
        guard let image=foliageCache[index] else { return }
        let g=SCNPlane(width:height*image.size.width/image.size.height,height:height)
        let m=mat(.white);m.diffuse.contents=image;m.lightingModel = .constant;m.isDoubleSided=true;g.materials=[m]
        let node=SCNNode(geometry:g);node.position=SCNVector3(CGFloat(x),CGFloat(y)+height/2,CGFloat(z));node.castsShadow=false
        let billboard=SCNBillboardConstraint();billboard.freeAxes = .Y;node.constraints=[billboard];n.addChildNode(node)
    }
    static func palm(_ n:SCNNode,x:Float,z:Float,scale:Float=1) {
        foliage(n,index:0,x:x,y:0.18,z:z,height:CGFloat(scale)*2.5)
    }

    static func premiumIslandGround(_ n:SCNNode,stage:Int) {
        let radius=7.1+CGFloat(stage)*0.7
        let ocean=box(n,100,0.08,100,0,-0.56,0,color(0.10,0.44,0.53),chamfer:0)
        ocean.geometry?.firstMaterial?.roughness.contents=0.72
        _ = islandLayer(n,radius:radius+1.15,height:0.16,y:-0.50,tint:color(0.30,0.63,0.61))
        _ = islandLayer(n,radius:radius+0.7,height:0.45,y:-0.34,tint:color(0.79,0.73,0.56))
        let turf=islandLayer(n,radius:radius,height:0.20,y:0.03,tint:color(0.32,0.52,0.32));let grass=meadowMaterial("farm");grass.diffuse.wrapS = .repeat;grass.diffuse.wrapT = .repeat;grass.diffuse.contentsTransform=SCNMatrix4MakeScale(3,3,1);turf.geometry?.materials=[grass]
        for i in 0..<72 {
            let a=Float(i)*Float.pi*2/72, r=Float(radius)+0.32*sin(a*3+0.7)+0.18*cos(a*7)+0.20+Float(i%3)*0.15
            let rock=sphere(n,0.28+CGFloat(i%4)*0.04,sin(a)*r,-0.05,cos(a)*r,color(0.67,0.64,0.51));rock.scale=SCNVector3(1.4,0.6,0.85)
        }
        for i in 0..<11 {
            let a=Float(i)*Float.pi*2/11+0.14*sin(Float(i)*2.7)
            palm(n,x:sin(a)*Float(radius-0.5),z:cos(a)*Float(radius-0.5),scale:0.85+Float(i%3)*0.18)
        }
        for i in -6...6 {
            let z=Float(i)*0.88,x=sin(z*0.55)*0.55
            let stone=detailBox(n,0.62,0.025,0.65,x,0.245,z,2);stone.eulerAngles.y=CGFloat(sin(z)*0.15)
        }
        for i in 0..<9 {
            let a=Float(i)*0.19+1.1,r=Float(radius)-0.15
            let rock=sphere(n,0.32+CGFloat(i%3)*0.12,sin(a)*r,0.10,cos(a)*r,color(0.48,0.51,0.43));rock.scale=SCNVector3(1.3,0.8,1)
        }
        for i in 0..<18 {
            let a=Float(i)*0.73,r=Float(radius)+1.2+Float(i%5)*0.65
            let wave=ring(n,r:0.28+CGFloat(i%3)*0.14,pipe:0.013,y:-0.49,tint:color(0.55,0.80,0.76));wave.position.x=CGFloat(sin(a)*r);wave.position.z=CGFloat(cos(a)*r);wave.scale.z=0.25;wave.opacity=0.42
            wave.runAction(.repeatForever(.sequence([.fadeOpacity(to:0.12,duration:2+Double(i%3)),.fadeOpacity(to:0.42,duration:3)])))
        }
        let dock=SCNNode();dock.position.z=radius+0.9;n.addChildNode(dock)
        for i in 0..<13 { detailBox(dock,2.1,0.08,0.19,0,-0.05,Float(i)*0.22-1.1,1) }
        for x:Float in [-0.9,0.9] { for z:Float in [-1,1] { cylinder(dock,0.08,0.9,x,-0.17,z,color(0.40,0.29,0.20)) } }
    }
    static func premiumIslandBuilding(_ n:SCNNode,_ item:GQWorldItem) {
        if expandedIslandBuilding(n,item) { return }
        let level=max(1,item.level),wood=color(0.40,0.29,0.19),roof=color(0.18,0.38,0.36),cream=color(0.88,0.83,0.68)
        detailBox(n,1.9,0.13,1.8,0,0.29,0,2)
        if ["garden","farm","herbGarden"].contains(item.kind) {
            detailBox(n,1.6,0.25,1.35,0,0.47,0,1)
            box(n,1.45,0.03,1.2,0,0.61,0,color(0.31,0.23,0.15))
            foliage(n,index:item.kind == "garden" ? 4 : item.kind == "farm" ? 6 : 5,x:0,y:0.62,z:0,height:0.86)
            if level>=2 { for z:Float in [-0.7,0.7] { for i in 0..<7 { cylinder(n,0.022,0.40,Float(i-3)*0.23,0.71,z,wood) };box(n,1.65,0.035,0.035,0,0.89,z,wood) } }
            if level>=3 { for x:Float in [-0.78,0.78] { cylinder(n,0.025,1.1,x,1.05,-0.5,cream) };box(n,1.62,0.035,0.07,0,1.6,-0.5,cream) }
            if level>=4 { cylinder(n,0.18,0.45,0.72,0.6,0.75,color(0.28,0.48,0.49));beam(n,from:SCNVector3(0.72,0.8,0.7),to:SCNVector3(0.4,0.85,0.4),radius:0.025,tint:cream) }
            return
        }
        if ["campfire","well"].contains(item.kind) {
            legacyIslandBuilding(n,item)
            if item.kind == "well" {
                for row in 0..<3 { for i in 0..<12 { let a=Float(i)*Float.pi/6+Float(row%2)*0.26
                    let b=box(n,0.24,0.17,0.13,sin(a)*0.58,0.41+Float(row)*0.20,cos(a)*0.58,color(0.67+CGFloat(i%3)*0.045,0.66,0.57),chamfer:0.03);b.eulerAngles.y=CGFloat(a)
                } }
            }
            if item.kind == "campfire" {
                for x:Float in [-0.86,0.86] { detailBox(n,0.24,0.19,1.25,x,0.50,0.1,1) }
            }
            if level>=2 && ["garden","farm","herbGarden"].contains(item.kind) {
                for z:Float in [-0.80,0.80] { for i in 0..<8 { cylinder(n,0.024,0.42,Float(i-4)*0.20,0.54,z,wood) };box(n,1.8,0.04,0.04,0,0.72,z,wood) }
            }
            return
        }
        let h:Float=1.03+Float(level-1)*0.14
        if item.kind == "training" {
            for x:Float in [-0.66,0.66] { cylinder(n,0.065,1.55,x,1.08,-0.5,wood) }
            beam(n,from:SCNVector3(-0.66,1.84,-0.5),to:SCNVector3(0.66,1.84,-0.5),radius:0.05,tint:wood)
            for x:Float in [-0.26,0.26] {
                beam(n,from:SCNVector3(x,1.80,-0.5),to:SCNVector3(x,1.25,-0.5),radius:0.015,tint:cream)
                let r=ring(n,r:0.11,pipe:0.025,y:1.14,tint:wood);r.position.x=CGFloat(x);r.position.z = -0.5;r.eulerAngles.x = .pi/2
            }
            for z:Float in [-0.35,0.28] { detailBox(n,0.95,0.12,0.2,0,0.57,z,1) }
            for x:Float in [-0.62,0.62] { cylinder(n,0.12,0.06,x,0.52,0.62,roof).eulerAngles.z = .pi/2 }
        } else {
            box(n,1.4,CGFloat(h),1.18,0,0.35+h/2,0,cream,chamfer:0.035)
            for i in 0..<7 { box(n,1.42,0.012,1.2,0,0.43+Float(i)*0.14,0,color(0.74,0.68,0.53),chamfer:0) }
            detailBox(n,0.33,0.71,0.055,0,0.70,0.61,1)
            sphere(n,0.026,0.11,0.71,0.66,color(0.84,0.64,0.29),metal:0.5)
            for x:Float in [-0.48,0.48] {
                box(n,0.30,0.41,0.045,x,0.92,0.62,wood,chamfer:0.015)
                glow(box(n,0.24,0.33,0.055,x,0.92,0.65,color(0.98,0.77,0.39)),color(0.9,0.57,0.22))
                box(n,0.02,0.34,0.02,x,0.92,0.69,cream,chamfer:0)
                box(n,0.25,0.025,0.02,x,0.92,0.69,cream,chamfer:0)
            }
            pitchedRoof(n,w:1.72,d:1.52,y:h+0.42,tint:roof)
            detailBox(n,1.35,0.09,0.40,0,0.33,0.90,1)
            if item.kind == "clinic" {
                box(n,0.13,0.46,0.05,0,1.18,0.66,color(0.73,0.29,0.25))
                box(n,0.44,0.12,0.05,0,1.18,0.67,color(0.73,0.29,0.25))
            }
        }
        if level>=2 { for x:Float in [-0.80,0.80] { cylinder(n,0.14,0.22,x,0.46,0.72,wood);sphere(n,0.19,x,0.65,0.72,color(0.28,0.51,0.28)) } }
        if level>=3 { detailBox(n,0.23,0.75,0.24,0.45,1.63,-0.35,2) }
        if level>=4 { for x:Float in [-0.82,0.82] { cylinder(n,0.035,1.7,x,1.12,-0.78,wood);glow(sphere(n,0.09,x,1.99,-0.78,cream),cream) } }
    }
    static func premiumCatRoom(_ n:SCNNode,stage:Int) {
        detailBox(n,14,0.35,10,0,-0.19,0,1)
        let sage=color(0.49,0.62,0.55),ivory=color(0.91,0.85,0.71),brass=color(0.71,0.54,0.28)
        // Fixed camera looks into the open front; solid back walls frame the room.
        box(n,0.18,3.5,9.6,-6.9,1.57,0,sage)
        box(n,8.6,3.5,0.18,-2.7,1.57,-4.8,sage)
        box(n,2.8,3.5,0.18,5.6,1.57,-4.8,sage)
        box(n,2.6,0.95,0.18,2.9,0.325,-4.8,sage)
        box(n,2.6,0.38,0.18,2.9,3.14,-4.8,sage)
        for y:Float in [0.15,0.85,3.35] {
            box(n,14,0.07,0.23,0,y,-4.68,ivory)
            box(n,0.23,0.07,9.6,-6.78,y,0,ivory)
        }
        for z:Float in [-4,-2.5,-1,0.5,2,3.5] { box(n,0.04,0.65,0.055,-6.77,0.50,z,ivory) }
        for x:Float in [-6,-4.5,-3,-1.5,0,5.5,6.7] { box(n,0.055,0.65,0.04,x,0.5,-4.67,ivory) }
        for z:Float in [4.8] { box(n,14,0.30,0.14,0,0.12,z,sage);box(n,14,0.055,0.20,0,0.3,z,ivory) }
        box(n,0.14,0.30,9.6,6.9,0.12,0,sage)
        box(n,0.20,0.055,9.6,6.9,0.3,0,ivory)
        let glass=box(n,2.6,2.15,0.04,2.9,1.95,-4.79,color(0.62,0.82,0.85))
        glass.geometry?.firstMaterial?.emission.contents=color(0.18,0.30,0.32)
        // Freestanding bay window, narrow mullions, curtains and sill.
        for x:Float in [1.6,2.9,4.2] { box(n,0.07,2.7,0.09,x,1.65,-4.6,ivory) }
        for y:Float in [0.95,2.10,3.02] { box(n,2.7,0.07,0.09,2.9,y,-4.6,ivory) }
        for x:Float in [1.7,4.1] { for i in 0..<5 { cylinder(n,0.055,2.05,x+Float(i)*0.05,1.91,-4.45,color(0.71,0.51,0.37)) } }
        detailBox(n,3.0,0.08,0.55,2.9,0.85,-4.43,1)
        let rug=box(n,4.9,0.026,3.4,0,0.015,0.5,color(0.55,0.35,0.31),chamfer:0.30)
        for inset:CGFloat in [0.15,0.28] {
            let frame=SCNBox(width:4.9-inset*2,height:0.03,length:3.4-inset*2,chamferRadius:0.2)
            frame.materials=[mat(color(0.80,0.65,0.43))];let f=SCNNode(geometry:frame);f.position.y=0.008;rug.addChildNode(f)
        }
        box(n,4.20,0.02,2.74,0,0.053,0.5,color(0.55,0.35,0.31),chamfer:0.2)
        box(n,2.65,0.42,1.0,-2.2,0.48,-3.5,sage,chamfer:0.19)
        box(n,2.7,0.73,0.22,-2.2,0.95,-3.92,sage,chamfer:0.1)
        for x:Float in [-3.48,-0.92] { box(n,0.23,0.58,1.0,x,0.72,-3.5,sage,chamfer:0.1) }
        for x:Float in [-2.9,-2.2,-1.5] { box(n,0.64,0.16,0.74,x,0.76,-3.45,ivory,chamfer:0.09) }
        for x:Float in [-3.25,-1.15] { for z:Float in [-3.85,-3.10] { cylinder(n,0.06,0.30,x,0.16,z,brass) } }
        detailBox(n,1.4,0.12,0.85,-2.2,0.48,-2.30,1)
        for x:Float in [-2.70,-1.70] { cylinder(n,0.035,0.42,x,0.24,-2.30,brass) }
        for i in 0..<5 { box(n,0.32,0.045,0.40,-2.30,0.56+Float(i)*0.045,-2.30,color(0.24+CGFloat(i)*0.09,0.43,0.48),chamfer:0.01) }
        for x:Float in [-5.9,5.9] { foliage(n,index:3,x:x,z:-3.7,height:1.85) }

        if stage>=3 {
            detailBox(n,3.2,0.3,4.7,8.5,-0.17,1.6,1)
            for i in 0..<7 { box(n,0.065,0.75,0.065,9.85,0.32,Float(i)*0.70-0.5,ivory) }
            box(n,0.09,0.08,4.7,9.85,0.72,1.6,ivory)
        }
        if stage>=5 { detailBox(n,3,0.15,2.4,-4.9,-0.02,6.0,1) }
    }
    static func premiumCat(_ n:SCNNode,coat:Int) {
        if let image=betaFrames(row:0).first {
            let g=SCNPlane(width:1.65,height:1.65*208/192)
            let m=mat(.white);m.diffuse.contents=image;m.lightingModel = .constant;m.isDoubleSided=true
            m.writesToDepthBuffer=false;g.materials=[m]
            let sprite=SCNNode(geometry:g);sprite.name="cat-sprite";sprite.position.y=g.height/2+0.04;sprite.castsShadow=false
            let billboard=SCNBillboardConstraint();billboard.freeAxes = .Y
            sprite.constraints=[billboard];n.addChildNode(sprite)
            animateBeta(n,row:0)
        }
        let shadow=cylinder(n,0.60,0.006,0,0.017,0,.black);shadow.opacity=0.14;shadow.scale.z=0.5;shadow.castsShadow=false
    }
    static func refineCatFacility(_ n:SCNNode,_ item:GQWorldItem) {
        guard item.kind != "cat" else { return }
        let brass=color(0.77,0.60,0.32), cream=color(0.89,0.82,0.65)
        if item.kind == "pantry" {
            for x:Float in [-0.42,0.42] {
                detailBox(n,0.54,0.62,0.06,x,0.66,0.48,1)
                sphere(n,0.035,x-0.12,0.76,0.54,brass,metal:0.5)
                cylinder(n,0.14,0.24,x,1.2,-0.25,cream)
                cylinder(n,0.15,0.035,x,1.33,-0.25,brass)
            }
            for i in 0..<6 { sphere(n,0.025,Float(i%3)*0.065-0.47,1.2,0.16+Float(i/3)*0.05,color(0.47,0.29,0.19)) }
        } else if item.kind == "playroom" {
            for x:Float in [-0.5,0.5] { for i in 0..<16 { ring(n,r:0.10,pipe:0.013,y:0.25+Float(i)*0.074,tint:cream).position.x=CGFloat(x) } }
            box(n,0.67,0.51,0.65,0,0.5,-0.1,color(0.49,0.61,0.55),chamfer:0.12)
            cylinder(n,0.19,0.025,0,0.52,0.24,color(0.18,0.26,0.24)).eulerAngles.x = .pi/2
            beam(n,from:SCNVector3(0.42,1.55,0.25),to:SCNVector3(0.42,1.10,0.25),radius:0.014,tint:cream)
            sphere(n,0.11,0.42,1.04,0.25,brass)
        } else if item.kind == "observatory" {
            for a:Float in [0,2.1,4.2] { beam(n,from:SCNVector3(sin(a)*0.55,0.2,cos(a)*0.55),to:SCNVector3(0,1.2,0),radius:0.033,tint:brass) }
            let scope=cylinder(n,0.15,0.85,0,1.60,0,cream,metal:0.4);scope.eulerAngles.z=0.95
            let lens=cylinder(n,0.17,0.035,-0.35,1.85,0,color(0.17,0.34,0.43),metal:0.65);lens.eulerAngles.z=0.95
        } else if item.kind == "greenhouse" {
            for x:Float in [-0.68,0.68] { for z:Float in [-0.48,0.48] { cylinder(n,0.025,1.35,x,0.87,z,brass) } }
            for i in 0..<5 { box(n,0.025,0.035,1.1,Float(i-2)*0.33,1.55,0,brass) }
        }
        if item.level>=3 { for x:Float in [-0.70,0.70] { glow(sphere(n,0.055,x,0.28,0.6,cream),cream) } }
    }
    static func premiumStationGround(_ n:SCNNode,stage:Int) {
        let silver=color(0.67,0.74,0.77),cyan=color(0.30,0.79,0.86),dark=color(0.09,0.15,0.23)
        for i in 0..<130 {
            let a=Float(i*137%360)*Float.pi/180,r=Float(12+i%21)
            let star=sphere(n,i%13 == 0 ? 0.050 : 0.018,sin(a)*r,Float(i*7%21)-8,cos(a)*r,.white);glow(star,.white);star.castsShadow=false
        }
        let planet=sphere(n,4.4,-14,-5,-16,color(0.19,0.39,0.57));planet.geometry?.firstMaterial?.roughness.contents=1
        let orbit=ring(planet,r:6.0,pipe:0.17,y:0,tint:color(0.37,0.52,0.60));orbit.eulerAngles.z = 0.38;orbit.scale.y=0.13
        cylinder(n,1.65,0.50,0,-0.04,0,dark,metal:0.5)
        let core=cylinder(n,1.42,0.68,0,0.43,0,.white);core.geometry?.materials=[surface(0,metal:0.45)]
        for y:Float in [0.13,0.72] { glow(ring(n,r:1.45,pipe:0.035,y:y,tint:cyan),cyan) }
        let dome=sphere(n,1.03,0,0.81,0,color(0.18,0.43,0.54),metal:0.5);dome.scale.y=0.53
        for i in 0..<12 {
            let a=Float(i)*Float.pi/6
            let panel=detailBox(n,0.38,0.08,0.30,sin(a)*1.10,1.08,cos(a)*1.10,0);panel.eulerAngles.y=CGFloat(a)
        }
        cylinder(n,0.11,1.0,0,1.35,0,silver,metal:0.6)
        glow(sphere(n,0.18,0,1.88,0,cyan),cyan)
        let orbital=ring(n,r:6.35,pipe:0.019,y:-0.08,tint:color(0.17,0.31,0.41));orbital.castsShadow=false
        for side:Float in [-1,1] {
            for row in 0..<3 {
                let panel=box(n,1.20,0.045,0.75,side*2.6,-0.25,Float(row-1)*0.85,color(0.08,0.22,0.40),chamfer:0.01,metal:0.4)
                for i in 0..<6 { box(panel,0.012,0.006,0.72,Float(i-3)*0.19,0.025,0,silver,chamfer:0) }
            }
            beam(n,from:SCNVector3(side*1.4,-0.25,0),to:SCNVector3(side*3.3,-0.25,0),radius:0.07,tint:silver)
        }
    }
    static func stationBridges(_ n:SCNNode,items:[GQWorldItem]) {
        let metal=color(0.43,0.53,0.60)
        for item in items where item.kind != "__world" && item.kind != "account" && item.level>0 {
            let d=hypot(item.x,item.z),dx=item.x/d,dz=item.z/d
            beam(n,from:SCNVector3(dx*1.3,0,dz*1.3),to:SCNVector3(item.x,0,item.z),radius:0.15,tint:metal)
            for side:Double in [-0.23,0.23] {
                beam(n,from:SCNVector3(dx*1.3-dz*side,0.23,dz*1.3+dx*side),to:SCNVector3(item.x-dz*side,0.23,item.z+dx*side),radius:0.027,tint:color(0.35,0.80,0.88))
            }
        }
    }
    static func premiumStationPod(_ n:SCNNode,_ item:GQWorldItem) {
        let silver=color(0.73,0.79,0.81),dark=color(0.10,0.18,0.25)
        let accent=item.kind == "archive" ? color(0.58,0.47,0.83) : item.kind == "studio" ? color(0.91,0.59,0.26) : item.kind == "habitat" ? color(0.35,0.72,0.50) : color(0.29,0.72,0.86)
        if item.kind == "account" {
            let signal=item.level == 1 ? color(0.33,0.81,0.57) : item.level == 3 ? color(0.94,0.36,0.29) : color(0.91,0.68,0.29)
            detailBox(n,0.42,0.36,0.44,0,0.5,0,0)
            for side:Float in [-1,1] {
                box(n,0.57,0.025,0.65,side*0.53,0.5,0,color(0.09,0.25,0.43),chamfer:0.01,metal:0.4)
                for j in 0..<4 { box(n,0.01,0.01,0.65,side*0.53+Float(j-2)*0.12,0.52,0,silver,chamfer:0) }
            }
            glow(sphere(n,0.085,0,0.75,0,signal),signal)
            cylinder(n,0.018,0.42,0,0.95,0,silver);return
        }
        if item.level == 0 {
            let b=box(n,1.65,0.70,1.35,0,0.37,0,accent);b.geometry?.firstMaterial?.fillMode = .lines;b.geometry?.firstMaterial?.lightingModel = .constant
            ring(n,r:1.05,pipe:0.025,y:0.03,tint:accent)
            return
        }
        let level=max(1,item.level)
        cylinder(n,1.05,0.16,0,0.04,0,dark,metal:0.5)
        glow(ring(n,r:1.03,pipe:0.025,y:0.15,tint:accent),accent)
        switch item.kind {
        case "compute":
            detailBox(n,1.65,0.22,1.35,0,0.27,0,0)
            for x:Float in [-0.48,0,0.48] {
                detailBox(n,0.35,0.90+CGFloat(level)*0.12,0.72,x,0.94,0,0)
                for row in 0..<6 { box(n,0.27,0.055,0.035,x,0.54+Float(row)*0.13,0.38,dark,chamfer:0.006);glow(sphere(n,0.016,x+0.1,0.54+Float(row)*0.13,0.41,accent),accent) }
                for i in 0..<4 { box(n,0.38,0.025,0.78,x,1.50+Float(i)*0.065,0,silver,chamfer:0.008) }
            }
        case "archive":
            for row in 0..<(2+min(level,3)) {
                let y:Float=0.40+Float(row)*0.29
                detailBox(n,1.68,0.09,1.32,0,y,0,0)
                for col in 0..<5 { box(n,0.20,0.18,0.89,Float(col-2)*0.28,y+0.12,0,accent,chamfer:0.015,metal:0.3) }
            }
        case "studio":
            detailBox(n,1.65,0.70,1.25,0,0.63,0,0)
            let screen=box(n,1.1,0.63,0.055,0,1.31,-0.20,dark,chamfer:0.04)
            glow(box(screen,0.98,0.47,0.012,0,0,0.039,accent,chamfer:0.02),accent)
            for x:Float in [-0.73,0.73] {
                cylinder(n,0.04,1.0,x,1.37,-0.28,silver,metal:0.6)
                glow(sphere(n,0.11,x,1.88,-0.28,accent),accent)
                beam(n,from:SCNVector3(x,0.7,0.25),to:SCNVector3(x*0.65,1.35,0.25),radius:0.035,tint:silver)
            }
        default:
            detailBox(n,1.55,0.30,1.30,0,0.30,0,0)
            for x:Float in [-0.44,0,0.44] { cylinder(n,0.17,0.23,x,0.61,0,color(0.42,0.32,0.25));sphere(n,0.22,x,0.95,0,accent) }
            let g=SCNSphere(radius:0.95);g.segmentCount=40
            let glass=mat(color(0.31,0.55,0.59),metal:0.12,rough:0.17);glass.transparency=0.22;glass.isDoubleSided=true;glass.writesToDepthBuffer=false;g.materials=[glass]
            let dome=SCNNode(geometry:g);dome.position.y=0.7;dome.scale=SCNVector3(1,0.9,0.85);n.addChildNode(dome)
            for i in 0..<3 { let r=ring(n,r:0.94,pipe:0.025,y:0.7,tint:silver);r.eulerAngles.x = .pi/2;r.eulerAngles.y=CGFloat(i) * .pi / 3;r.scale.y=0.85 }
        }
        for x:Float in [-0.76,0.76] { for z:Float in [-0.60,0.60] { cylinder(n,0.045,0.50,x,0.41,z,silver,metal:0.6) } }
        if level>=2 { for side:Float in [-1,1] { box(n,0.35,0.055,0.87,side*1.02,0.48,0,accent,metal:0.5) } }
        if level>=3 { cylinder(n,0.025,0.6,0,2.04,-0.3,silver);glow(sphere(n,0.06,0,2.36,-0.3,accent),accent) }
        if level>=4 { glow(ring(n,r:1.19,pipe:0.023,y:0.28,tint:accent),accent) }
    }
    static func premiumTrainGround(_ n:SCNNode,stage:Int) {
        let terrain=stage == 2 ? color(0.80,0.87,0.86) : stage == 1 ? color(0.69,0.63,0.44) : color(0.32,0.49,0.34)
        let meadow=box(n,100,0.12,100,0,-0.48,0,terrain,chamfer:0)
        if stage == 0 { meadow.geometry?.materials=[meadowMaterial("farm")] }
        for layer in (0...2).reversed() {
            landscapeRidge(n,layer:layer,tint:terrain.blended(withFraction:0.20+CGFloat(layer)*0.16,of:color(0.64,0.76,0.75))!)
        }
        for i in 0..<24 {
            let x=Float(i*19%37)-18,z=Float(i*13%5)+3.8
            foliage(n,index:stage == 2 || i%3 == 0 ? 2 : 1,x:x,y:-0.40,z:z,height:2.1+CGFloat(i%4)*0.36)
        }
        detailBox(n,24,0.16,2.05,0,-0.27,0,2)
        for i in -23...23 { detailBox(n,0.15,0.07,1.80,Float(i)*0.5,-0.13,0,1).name="parked-sleeper" }
        for z:Float in [-0.56,0.56] { box(n,24,0.10,0.065,0,-0.06,z,color(0.49,0.52,0.52),chamfer:0.01,metal:0.7) }
        let stationGroup=SCNNode();stationGroup.name="train-station";n.addChildNode(stationGroup)
        let n=stationGroup
        detailBox(n,19,0.28,2.6,0,-0.25,-2.8,2)
        for i in -16...16 { box(n,0.42,0.015,0.13,Float(i)*0.53,-0.09,-1.58,color(0.89,0.78,0.51),chamfer:0.01) }
        for x:Float in [-7,0,7] {
            cylinder(n,0.055,1.65,x,0.71,-3.6,color(0.26,0.30,0.26))
            glow(sphere(n,0.12,x,1.58,-3.6,color(0.96,0.78,0.48)),color(0.96,0.78,0.48))
            detailBox(n,1.10,0.085,0.4,x,0.27,-2.9,1)
            for dx:Float in [-0.4,0.4] { cylinder(n,0.04,0.35,x+dx,0.1,-2.9,color(0.26,0.30,0.26)) }
        }
        let station=SCNNode();station.position=SCNVector3(-6,0,-5.3);n.addChildNode(station)
        detailBox(station,2.8,1.5,1.35,0,0.65,0,1)
        pitchedRoof(station,w:3.4,d:1.7,y:1.65,tint:color(0.27,0.38,0.36))
        box(station,0.48,0.94,0.03,0,0.40,0.69,color(0.17,0.26,0.28))
        for x:Float in [-0.91,0.91] { glow(box(station,0.51,0.56,0.04,x,0.8,0.70,color(0.88,0.70,0.40)),color(0.88,0.70,0.40)) }
    }
    static func premiumTrainCar(_ n:SCNNode,_ item:GQWorldItem) {
        if item.kind == "ghost" { legacyTrainCar(n,item);return }
        let level=max(1,item.level),brass=color(0.80,0.63,0.33),iron=color(0.12,0.18,0.20),ivory=color(0.88,0.81,0.64)
        box(n,2.05,0.15,1.22,0,0.44,0,iron,metal:0.5)
        for x:Float in [-0.66,0,0.66] { for z:Float in [-0.54,0.54] {
            let wheel=SCNNode();wheel.name="train-wheel";wheel.position=SCNVector3(x,0.23,z);n.addChildNode(wheel)
            cylinder(wheel,0.25,0.13,0,0,0,iron,metal:0.55).eulerAngles.x = .pi/2
            cylinder(wheel,0.12,0.015,0,0,z<0 ? -0.076:0.076,brass,metal:0.6).eulerAngles.x = .pi/2
            for j in 0..<6 { let a=Float(j)*Float.pi/3
                beam(wheel,from:SCNVector3(0,0,z<0 ? -0.083:0.083),to:SCNVector3(sin(a)*0.21,cos(a)*0.21,z<0 ? -0.083:0.083),radius:0.012,tint:brass)
            }
        } }
        for x:Float in [-1.10,1.10] { box(n,0.25,0.08,0.16,x,0.41,0,iron,metal:0.65) }
        if item.kind == "engine" {
            let boiler=cylinder(n,0.41,1.27,-0.35,0.98,0,iron,metal:0.4);boiler.eulerAngles.z = .pi/2
            for x:Float in [-0.88,-0.45,-0.05] {
                let band=ring(n,r:0.418,pipe:0.024,y:0.98,tint:brass);band.position.x=CGFloat(x);band.eulerAngles.z = .pi/2
            }
            detailBox(n,0.74,1.06,1.04,0.60,1.04,0,3)
            box(n,0.93,0.14,1.29,0.60,1.63,0,iron,chamfer:0.10)
            for z:Float in [-0.53,0.53] { glow(box(n,0.41,0.43,0.025,0.62,1.22,z,ivory),color(0.75,0.50,0.23));box(n,1.25,0.045,0.04,-0.15,0.25,z*1.17,brass,metal:0.6) }
            cylinder(n,0.12,0.53,-0.64,1.56,0,iron,metal:0.4);cylinder(n,0.19,0.05,-0.64,1.84,0,brass,metal:0.5)
            let lamp=cylinder(n,0.12,0.06,-1.01,1.10,0,ivory);lamp.eulerAngles.z = .pi/2;glow(lamp,ivory)
            for i in 0..<6 { beam(n,from:SCNVector3(-1.12,0.46,Float(i-3)*0.16),to:SCNVector3(-1.29,0.25,Float(i-3)*0.18),radius:0.019,tint:brass) }
            return
        }
        detailBox(n,1.93,0.82,1.14,0,0.98,0,3)
        for z:Float in [-0.58,0.58] {
            for y:Float in [0.64,1.37] { box(n,1.96,0.025,0.028,0,y,z,brass,chamfer:0.007,metal:0.5) }
            for x:Float in [-0.66,-0.22,0.22,0.66] {
                box(n,0.34,0.48,0.035,x,1.10,z,brass,chamfer:0.03,metal:0.4)
                glow(box(n,0.28,0.39,0.041,x,1.10,z*1.014,color(0.48,0.65,0.64)),color(0.30,0.43,0.36))
                if item.kind == "sleeper" { for dx:Float in [-0.11,0.11] { box(n,0.06,0.37,0.01,x+dx,1.10,z*1.06,color(0.69,0.47,0.33)) } }
                if item.kind == "dining" { glow(sphere(n,0.035,x,0.98,z*1.06,ivory),ivory) }
                if item.kind == "library" { for j in 0..<4 { box(n,0.033,0.14,0.01,x+Float(j-2)*0.05,0.98,z*1.06,color(0.40+CGFloat(j)*0.1,0.30,0.21)) } }
            }
        }
        if item.kind == "garden" {
            detailBox(n,1.70,0.13,0.85,0,1.45,0,1)
            foliage(n,index:4,x:0,y:1.52,z:0,height:0.60)
            for x:Float in [-0.80,0.80] { for z:Float in [-0.50,0.50] { cylinder(n,0.025,0.73,x,1.73,z,brass) } }
            box(n,1.90,0.06,1.18,0,2.11,0,ivory)
        } else if item.kind == "observation" {
            box(n,1.90,0.34,1.1,0,1.63,0,color(0.36,0.59,0.62),chamfer:0.15,metal:0.35)
            for x:Float in [-0.72,-0.24,0.24,0.72] { box(n,0.025,0.035,1.07,x,1.81,0,brass) }
        } else {
            box(n,2.07,0.22,1.30,0,1.50,0,iron,chamfer:0.10,metal:0.3)
            for i in 0..<10 { box(n,0.025,0.024,1.17,Float(i)*0.2-0.9,1.617,0,color(0.35,0.42,0.42),chamfer:0.008) }
        }
        if level>=2 { for z:Float in [-0.59,0.59] { box(n,1.86,0.025,0.02,0,0.72,z,brass,metal:0.5) } }
        if level>=3 { for x:Float in [-0.93,0.93] { cylinder(n,0.025,0.95,x,1.05,0.63,brass,metal:0.6) } }
        if level>=4 { for x:Float in [-0.91,0.91] { glow(sphere(n,0.045,x,1.48,0.62,ivory),ivory) } }
    }
    static func premiumLighting(_ scene:SCNScene,mode:String) {
        guard ["island","cat","station","expedition","train","interior"].contains(mode) else { return }
        let c=scene.rootNode.childNode(withName:"camera",recursively:false)?.camera
        c?.wantsHDR=true;c?.bloomIntensity=0.12;c?.bloomThreshold=1.1;c?.bloomBlurRadius=3
        if mode == "station" || mode == "expedition" {
            // A mostly black sky must not make automatic exposure bleach ships and planets.
            c?.wantsExposureAdaptation=false;c?.exposureOffset = 0.0;c?.whitePoint=1.4;c?.bloomIntensity=0
            for node in scene.rootNode.childNodes {
                if node.light?.type == .ambient { node.light?.intensity=320 }
                if node.light?.type == .directional { node.light?.intensity=750 }
            }
        }
        c?.screenSpaceAmbientOcclusionIntensity=0.65;c?.screenSpaceAmbientOcclusionRadius=0.35
        let fill=SCNNode();fill.light=SCNLight();fill.light?.type = .omni;fill.light?.intensity=["station","expedition"].contains(mode) ? 170 : 210
        fill.light?.color=color(0.62,0.77,0.92);fill.position=SCNVector3(-7,8,-5);scene.rootNode.addChildNode(fill)
        if mode == "cat" || mode == "interior" { scene.background.contents=color(0.23,0.31,0.30) }
        if mode == "train" { scene.fogColor=color(0.73,0.81,0.77);scene.fogStartDistance=32;scene.fogEndDistance=65 }
    }
    static func worldPlaque(_ n:SCNNode,item:GQWorldItem,mode:String) {
        let size=NSSize(width:512,height:94),im=NSImage(size:NSSize(width:512,height:94));im.lockFocus()
        color(0.08,0.17,0.19).withAlphaComponent(0.92).setFill();NSBezierPath(roundedRect:NSRect(origin:.zero,size:size),xRadius:24,yRadius:24).fill()
        let p=NSMutableParagraphStyle();p.alignment = .center
        let text=item.title+(item.kind == "account" || item.kind == "cat" ? "" : item.level>0 ? " · \(item.level)" : " · +")
        (text as NSString).draw(in:NSRect(x:16,y:17,width:480,height:58),withAttributes:[.font:NSFont.systemFont(ofSize:39,weight:.medium),.foregroundColor:NSColor.white,.paragraphStyle:p]);im.unlockFocus()
        let g=SCNPlane(width:mode == "train" ? 1.75 : 2,height:0.37),m=mat(.white);m.diffuse.contents=im;m.lightingModel = .constant;m.isDoubleSided=true;g.materials=[m]
        let label=SCNNode(geometry:g);label.name="world-plaque";label.position=SCNVector3(0,item.kind == "account" ? 1.42 : item.kind == "cat" ? 3.0 : 2.55,0)
        label.constraints=[SCNBillboardConstraint()];label.castsShadow=false;n.addChildNode(label)
    }
}

extension GQWorldBuilder {
    /// Irregular, layered coastline; buildable ground remains inside the safe placement radius.
    static func islandLayer(_ root:SCNNode,radius:CGFloat,height:CGFloat,y:Float,tint:NSColor)->SCNNode {
        let path=NSBezierPath()
        for i in 0..<96 {
            let a=CGFloat(i)*CGFloat.pi*2/96
            let r=radius+0.32*sin(a*3+0.7)+0.18*cos(a*7)
            let p=NSPoint(x:sin(a)*r,y:cos(a)*r)
            if i==0 { path.move(to:p) } else { path.line(to:p) }
        }
        path.close()
        let shape=SCNShape(path:path,extrusionDepth:height);shape.chamferRadius=0.05;shape.materials=[mat(tint)]
        let node=SCNNode(geometry:shape);node.eulerAngles.x = -.pi/2;node.position.y=CGFloat(y);root.addChildNode(node);return node
    }
    static func landscapeRidge(_ root:SCNNode,layer:Int,tint:NSColor) {
        let path=NSBezierPath();path.move(to:NSPoint(x:-35,y:0))
        for i in 0...30 {
            let x=CGFloat(i)*2.4-35
            let y=CGFloat(2+layer)+CGFloat(sin(Double(i)*0.8+Double(layer))*1.3)+CGFloat(i%3)*0.4
            path.line(to:NSPoint(x:x,y:y))
        }
        path.line(to:NSPoint(x:37,y:-2));path.close()
        let shape=SCNShape(path:path,extrusionDepth:2);shape.materials=[mat(tint)]
        let node=SCNNode(geometry:shape);node.position=SCNVector3(0,-0.5,-12-Float(layer)*5);root.addChildNode(node)
    }
}
