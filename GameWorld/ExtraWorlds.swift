import AppKit
import SceneKit

// Shared, lightweight scenery. Gameplay numbers and saves remain in the owning feature engines.
extension GQWorldBuilder {
    static func worldTree(_ root: SCNNode, x: Float, z: Float, tint: NSColor, scale: Float = 1) {
        let wood=color(0.38,0.27,0.18)
        cylinder(root,CGFloat(0.12*scale),CGFloat(1.08*scale),x,0.52*scale,z,wood)
        for i in 0..<5 {
            let a=Float(i)*Float.pi*2/5
            let dx=sin(a)*0.36*scale, dz=cos(a)*0.34*scale
            let branch=cylinder(root,CGFloat(0.045*scale),CGFloat(0.64*scale),x+dx*0.43,1.03*scale,z+dz*0.43,wood)
            branch.eulerAngles.z=CGFloat(-dx*0.55)
            let leaf=sphere(root,CGFloat(0.42*scale),x+dx,1.38*scale+Float(i%2)*0.18*scale,z+dz,tint)
            leaf.scale=SCNVector3(1.15,0.92,0.88)
        }
        sphere(root,CGFloat(0.43*scale),x,1.83*scale,z,tint)
    }
    static func estateGround(_ root: SCNNode, mode: String, stage: Int) {
        refinedEstateGround(root, mode:mode, stage:stage)
    }

    static func estateObject(_ n:SCNNode,mode:String,item:GQWorldItem) {
        if mode == "farm" {
            let bed=box(n,1.67,0.14,1.56,0,0,0,item.kind == "locked" ? color(0.51,0.49,0.41) : color(0.56,0.36,0.23),chamfer:0.08)
            if item.kind != "locked" {
                bed.geometry?.materials=[meadowMaterial("soil")]
                for row in 0..<5 { box(n,1.51,0.015,0.024,0,0.079,Float(row-2)*0.29,color(0.25,0.16,0.10),chamfer:0) }
            }
            if item.kind == "locked" { return }
            if item.kind == "unlock" {
                box(n,0.13,0.63,0.13,0,0.4,0,color(0.58,0.42,0.29))
                box(n,0.76,0.46,0.06,0,0.72,0,color(0.90,0.77,0.48))
                return
            }
            guard item.kind.hasPrefix("crop:") else { return }
            if illustratedCrop(n,id:String(item.kind.dropFirst(5)),level:item.level) { return }
            let ripe=item.level >= 3, tall=["wheat","corn","sunflower","tea","coffee","apple","peach"].contains(String(item.kind.dropFirst(5)))
            let height:Float = item.level == 1 ? 0.28 : item.level == 2 ? 0.57 : tall ? 1.24 : 0.86
            for dx: Float in [-0.43,0,0.43] { for dz: Float in [-0.34,0.31] {
                cylinder(n,0.035,CGFloat(height),dx,height/2+0.11,dz,color(0.18,0.47,0.24))
                sphere(n,CGFloat(height*0.25),dx,height+0.13,dz,color(0.24,0.62,0.32))
                if ripe { sphere(n,0.12,dx+0.08,height+0.18,dz,color(0.95,0.60,0.23)) }
            } }
            return
        }
        if mode == "pasture" {
            if item.kind == "shelter" || item.kind == "unlock" {
                box(n,1.44,0.12,1.39,0,0.04,0,color(0.71,0.55,0.36))
                if item.kind == "unlock" { cone(n,0.68,0,1.1,0,0.65,0,color(0.93,0.74,0.36)) }
                else { for x:Float in [-0.54,0.54] { cylinder(n,0.035,0.22,x,0.16,0.45,color(0.69,0.55,0.34)) } }
                return
            }
            let species=String(item.kind.dropFirst(7))
            if illustratedAnimal(n,id:species,level:item.level) { return }
            let palette:[NSColor]=[color(0.92,0.82,0.63),color(0.85,0.73,0.56),color(0.72,0.63,0.50),color(0.94,0.91,0.78)]
            let tint=palette[item.kind.utf8.reduce(0) { ($0 + Int($1)) % palette.count }]
            let birdSpecies:Set<String>=["chicken","duck","goose","quail","turkey","guineafowl","ostrich","peacock"]
            if species == "bee" {
                let body=sphere(n,0.36,0,0.67,0,color(0.94,0.72,0.30)); body.scale=SCNVector3(1.4,0.8,0.8)
                for x:Float in [-0.19,0.17] { box(n,0.08,0.39,0.58,x,0.68,0,color(0.30,0.27,0.23)) }
                for z:Float in [-0.35,0.35] { let wing=sphere(n,0.30,-0.08,1.02,z,color(0.72,0.87,0.93)); wing.scale=SCNVector3(1,0.24,0.60) }
            } else if birdSpecies.contains(species) {
                let tall=species == "goose" || species == "ostrich"
                let body=sphere(n,tall ? 0.45 : 0.38,0,0.62,0,tint); body.scale=SCNVector3(1.23,0.80,0.78)
                cylinder(n,0.14,tall ? 0.82 : 0.28,0.36,tall ? 1.11 : 0.92,0,tint)
                sphere(n,0.23,0.40,tall ? 1.48 : 1.10,0,tint)
                cone(n,0.16,0,0.31,0.65,tall ? 1.43 : 1.06,0,color(0.91,0.57,0.25))
                for z:Float in [-0.19,0.19] { cylinder(n,0.045,0.34,0.05,0.24,z,color(0.68,0.39,0.25)) }
                for z:Float in [-0.19,0.19] { let wing=sphere(n,0.28,-0.04,0.69,z*2,tint); wing.scale=SCNVector3(1,0.5,0.48) }
                if species == "peacock" || species == "turkey" {
                    for angle in -2...2 { sphere(n,0.15,-0.47,1.0+Float(abs(angle))*0.11,Float(angle)*0.25,color(0.24,0.54,0.59)) }
                }
            } else if species == "rabbit" {
                let body=sphere(n,0.45,0,0.53,0,tint); body.scale=SCNVector3(1.15,0.68,0.72)
                sphere(n,0.30,0.40,0.75,0,tint)
                for z:Float in [-0.15,0.15] { cone(n,0.11,0,0.67,0.39,1.30,z,tint) }
                sphere(n,0.09,-0.50,0.62,0,color(0.98,0.95,0.87))
            } else {
                let bulk=species == "cow" || species == "buffalo" || species == "yak" || species == "highlandcow"
                let coat=species == "pig" ? color(0.92,0.62,0.57) : tint
                box(n,bulk ? 1.38 : 1.10,bulk ? 0.76 : 0.62,0.69,0,0.67,0,coat,chamfer:0.26)
                sphere(n,0.34,0.48,0.93,0,coat)
                for x:Float in [-0.38,0.37] { for z:Float in [-0.23,0.23] {
                    cylinder(n,0.075,0.46,x,0.24,z,color(0.52,0.43,0.35))
                } }
                if species == "sheep" || species == "alpaca" { for x:Float in [-0.36,0,0.36] { sphere(n,0.23,x,1.04,0,color(0.97,0.94,0.87)) } }
                if species == "pig" { cylinder(n,0.17,0.10,0.78,0.82,0,color(0.85,0.48,0.47)) }
                if ["goat","cow","yak","buffalo","reindeer","deer","highlandcow"].contains(species) {
                    for z:Float in [-0.22,0.22] { cone(n,0.11,0,0.48,0.44,1.35,z,color(0.79,0.68,0.49)) }
                }
                if species == "horse" || species == "donkey" { for x:Float in [-0.43,-0.21,0] { sphere(n,0.13,x,1.18,0,color(0.40,0.30,0.25)) } }
            }
            if item.level < 2 { n.scale=SCNVector3(0.78,0.78,0.78) }
            if item.level >= 3 { sphere(n,0.14,-0.32,1.06,0,color(0.98,0.83,0.50)) }
            n.runAction(.repeatForever(.sequence([.moveBy(x:0.16,y:0,z:0.10,duration:2.7),
                                                   .moveBy(x:-0.16,y:0,z:-0.10,duration:2.7)])))
            return
        }
        if mode == "fishing" && item.kind.hasPrefix("bobber") {
            fishingFloat(n, item:item)
            return
        }
        if mode == "fishing" && item.kind == "legacyBobber" {
            sphere(n,0.18,0,0.05,0,color(0.96,0.33,0.28))
            let ring=SCNTorus(ringRadius:0.42,pipeRadius:0.02)
            ring.materials=[mat(color(0.78,0.96,0.97))]
            let r=SCNNode(geometry:ring); r.position.y = -0.10; n.addChildNode(r)
            r.runAction(.repeatForever(.sequence([.scale(to:1.7,duration:1.4),.scale(to:1,duration:0.1)])))
            return
        }
        if item.kind.hasPrefix("fish:") {
            if illustratedFish(n,id:String(item.kind.dropFirst(5)),level:item.level) { return }
            let tint=item.level >= 4 ? color(0.98,0.68,0.39) : item.level >= 2 ? color(0.52,0.83,0.91) : color(0.78,0.89,0.77)
            let body=sphere(n,0.32,0,0.8,0,tint); body.scale=SCNVector3(1.35,0.60,0.52)
            cone(n,0.23,0,0.40,-0.52,0.8,0,tint)
            sphere(n,0.055,0.20,0.84,0.13,color(0.12,0.22,0.27))
            n.runAction(.repeatForever(.sequence([.moveBy(x:0.36,y:0.12,z:0,duration:2.2),
                                                   .moveBy(x:-0.36,y:-0.12,z:0,duration:2.2)])))
        }
    }

    static func adventureGround(_ root:SCNNode,mode:String,stage:Int) {
        // Fixed perspective painted environments provide the terrain and lighting.
        // Selectable actors and buildings remain separate live SceneKit nodes.
    }
    static func adventureObject(_ n:SCNNode,mode:String,item:GQWorldItem) {
        if mode == "camp" {
            if illustratedCamp(n,kind:item.kind) { return }
            let tint=item.kind == "forge" ? color(0.78,0.47,0.33) : item.kind == "study" ? color(0.38,0.59,0.73) : item.kind == "stable" ? color(0.72,0.62,0.42) : color(0.63,0.48,0.71)
            box(n,2.15,1.36,1.72,0,0.73,0,tint,chamfer:0.15)
            cone(n,1.64,0,1.15,0,1.96,0,color(0.39,0.31,0.34))
            for x:Float in [-0.58,0.58] { box(n,0.32,0.38,0.04,x,0.94,0.88,color(0.93,0.82,0.49)) }
            if item.level >= 2 { sphere(n,0.25,0,2.61,0,tint,metal:0.22) }
            finishCamp(n,kind:item.kind,level:item.level)
            return
        }
        if item.kind.hasPrefix("hero") {
            if illustratedHero(n) { return }
            let armored=item.kind.contains("armor1"), armed=item.kind.contains("weapon1")
            let coat=armored ? color(0.51,0.65,0.76) : color(0.35,0.52,0.73)
            for x:Float in [-0.25,0.25] { box(n,0.25,0.80,0.30,x,0.43,0,color(0.29,0.36,0.43)) }
            box(n,0.98,1.06,0.58,0,1.28,0,coat,chamfer:0.21,metal:armored ? 0.55 : 0.12)
            sphere(n,0.38,0,2.06,0,color(0.91,0.73,0.56))
            cone(n,0.46,0,0.52,0,2.50,0,color(0.31,0.37,0.47))
            for x:Float in [-0.67,0.67] { box(n,0.28,0.86,0.29,x,1.26,0,coat) }
            box(n,0.12,armed ? 1.68 : 1.25,0.15,0.89,1.30,0,armed ? color(0.79,0.87,0.89) : color(0.47,0.34,0.23),metal:armed ? 0.75 : 0)
            if armored { box(n,0.53,0.65,0.15,-0.84,1.32,0,color(0.76,0.65,0.44),metal:0.55) }
            return
        }
        if item.kind.hasPrefix("pet") {
            let parts=item.kind.split(separator:":")
            if parts.count >= 2, let index=Int(parts[1]), illustratedPet(n,index:index,level:item.level) { return }
            let tint=[color(0.90,0.69,0.43),color(0.66,0.79,0.88),color(0.67,0.78,0.51)][item.kind.utf8.reduce(0) { ($0 + Int($1)) % 3 }]
            sphere(n,0.45,0,0.47,0,tint)
            sphere(n,0.28,0.32,0.76,0,tint)
            for z:Float in [-0.20,0.20] { cone(n,0.11,0,0.26,0.27,1.10,z,tint) }
            if item.level>=2 { sphere(n,0.15,-0.44,0.61,0,tint) }
            n.runAction(.repeatForever(.sequence([.moveBy(x:0.18,y:0,z:0.15,duration:2.2),
                                                   .moveBy(x:-0.18,y:0,z:-0.15,duration:2.2)])))
            return
        }
        // Ten monster silhouettes follow the real rotating monster index.
        let type=Int(item.kind.split(separator:":").last ?? "0") ?? 0
        if illustratedMonster(n,index:type) { return }
        let tint:[NSColor]=[color(0.62,0.43,0.38),color(0.72,0.36,0.40),color(0.46,0.63,0.47),color(0.48,0.54,0.73),color(0.74,0.62,0.38)]
        let bodyColor=tint[type%tint.count]
        cylinder(n,0.78,1.55,0,1.02,0,bodyColor)
        sphere(n,0.66,0,1.98,0,bodyColor)
        for x:Float in [-0.44,0.44] { sphere(n,0.09,x,2.08,0.55,color(0.99,0.82,0.48)) }
        for x:Float in [-0.61,0.61] { cone(n,0.17,0,0.65,x,2.62,0,bodyColor) }
        if type%2 == 0 { for x:Float in [-0.88,0.88] { box(n,0.27,1.0,0.29,x,1.25,0,bodyColor) } }
        if type%3 == 0 { let ring=SCNTorus(ringRadius:0.88,pipeRadius:0.05); ring.materials=[mat(color(0.95,0.55,0.37))]; let r=SCNNode(geometry:ring); r.position.y=0.23; n.addChildNode(r) }
    }
}
