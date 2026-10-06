import AppKit
import SceneKit

extension GQWorldBuilder {
    static func expandedIslandBuilding(_ n:SCNNode,_ item:GQWorldItem)->Bool {
        guard ["rainCollector","orchard","workshop","windmill","kitchen","teaHouse"].contains(item.kind) else { return false }
        let wood=color(0.42,0.29,0.18),sage=color(0.24,0.43,0.36),cream=color(0.88,0.80,0.62),brass=color(0.74,0.54,0.25)
        let level=max(1,item.level)
        detailBox(n,1.85,0.14,1.8,0,0.32,0,2)
        switch item.kind {
        case "rainCollector":
            cylinder(n,0.46,0.95,0.3,0.88,0.14,sage,metal:0.4)
            for h:Float in [0.47,0.70,1.06,1.33] { let r=ring(n,r:0.466,pipe:0.02,y:h,tint:brass);r.position.x=0.3;r.position.z=0.14 }
            cylinder(n,0.43,0.025,0.3,1.37,0.14,color(0.18,0.62,0.72),metal:0.2)
            for x:Float in [-0.76,0.76] { cylinder(n,0.04,1.55,x,1.16,-0.48,wood) }
            let catchment=box(n,1.72,0.055,0.92,0,1.83,-0.25,sage);catchment.eulerAngles.x=0.22
            cylinder(n,0.05,1.70,0,1.73,0.22,brass).eulerAngles.z = .pi/2
            beam(n,from:SCNVector3(0.70,1.72,0.22),to:SCNVector3(0.70,1.18,0.22),radius:0.038,tint:brass)
            beam(n,from:SCNVector3(0.3,0.57,0.55),to:SCNVector3(0.3,0.57,0.82),radius:0.045,tint:brass)
            cylinder(n,0.13,0.16,0.3,0.43,0.77,cream)
            for i in 0..<8 { box(n,0.025,0.045,0.025,-0.13,0.62+Float(i)*0.075,0.40,cream) }
        case "orchard":
            for (i,x) in [Float(-0.48),0.45].enumerated() {
                let z:Float=i==0 ? -0.30 : 0.35
                cylinder(n,0.075,0.97,x,0.90,z,wood)
                foliage(n,index:1,x:x,y:0.63,z:z,height:1.48)
                for k in 0..<5 { let a=Float(k)*1.256
                    beam(n,from:SCNVector3(x,1.03,z),to:SCNVector3(x+sin(a)*0.30,1.5,z+cos(a)*0.28),radius:0.035,tint:wood)
                    sphere(n,0.065,x+sin(a)*0.42,1.42,z+cos(a)*0.38,i==0 ? color(0.82,0.25,0.12) : color(0.93,0.65,0.18))
                }
            }
            for z:Float in [-0.81,0.81] { for i in 0..<7 { detailBox(n,0.06,0.36,0.05,Float(i-3)*0.26,0.60,z,1) };box(n,1.7,0.05,0.05,0,0.67,z,wood) }
            detailBox(n,0.40,0.22,0.35,0.48,0.51,-0.61,1)
            for i in 0..<6 { sphere(n,0.065,0.36+Float(i%3)*0.11,0.65,-0.68+Float(i/3)*0.12,color(0.89,0.40,0.12)) }
        case "workshop":
            detailBox(n,1.58,0.84,0.13,0,0.87,-0.67,1)
            for x:Float in [-0.72,0.72] { detailBox(n,0.09,1.45,0.09,x,1.09,-0.60,1) }
            pitchedRoof(n,w:1.85,d:1.35,y:1.77,tint:sage)
            detailBox(n,1.37,0.11,0.59,0,0.92,0.17,1)
            for x:Float in [-0.58,0.58] { for z:Float in [-0.05,0.40] { detailBox(n,0.07,0.5,0.07,x,0.65,z,1) } }
            let blade=cylinder(n,0.23,0.024,0.25,1.02,0.13,cream,metal:0.65);blade.eulerAngles.x = .pi/2
            for i in 0..<5 { let x=Float(i-2)*0.23
                box(n,0.035,0.28,0.035,x,1.23,-0.56,wood)
                box(n,0.14,0.07,0.06,x,1.39,-0.56,brass,metal:0.6)
            }
            for i in 0..<4 { cylinder(n,0.055,1.25,0,0.47+Float(i)*0.11,0.62,wood).eulerAngles.z = .pi/2 }
        case "windmill":
            cone(n,0.58,0.34,1.65,0,1.18,0,cream)
            for i in 0..<7 { let r=ring(n,r:0.55-CGFloat(i)*0.029,pipe:0.014,y:0.46+Float(i)*0.21,tint:wood);r.opacity=0.45 }
            cone(n,0.60,0,0.60,0,2.29,0,sage)
            detailBox(n,0.28,0.54,0.05,0,0.70,0.52,1)
            let rotor=SCNNode();rotor.position=SCNVector3(0,1.83,0.52);n.addChildNode(rotor)
            for i in 0..<4 { let sail=SCNNode();sail.eulerAngles.z=CGFloat(i) * .pi/2;rotor.addChildNode(sail)
                detailBox(sail,0.055,1.08,0.055,0,0.49,0,1)
                box(sail,0.23,0.72,0.028,0.12,0.58,0,cream)
                for j in 0..<5 { box(sail,0.27,0.02,0.038,0.12,0.26+Float(j)*0.15,0.025,wood) }
            }
            sphere(rotor,0.10,0,0,0.05,brass,metal:0.5)
            rotor.runAction(.repeatForever(.rotateBy(x:0,y:0,z:-2*CGFloat.pi,duration:12)),forKey:"wind")
        case "kitchen":
            let oven=sphere(n,0.64,-0.22,0.78,-0.15,color(0.69,0.43,0.27));oven.scale=SCNVector3(1,0.9,0.85)
            detailBox(n,1.25,0.36,1.12,-0.22,0.51,-0.15,2)
            box(n,0.50,0.40,0.04,-0.22,0.71,0.40,color(0.13,0.11,0.09),chamfer:0.15)
            glow(box(n,0.31,0.08,0.045,-0.22,0.55,0.43,color(0.94,0.42,0.11)),color(1,0.3,0.03))
            detailBox(n,0.24,0.78,0.25,-0.4,1.62,-0.33,2)
            detailBox(n,0.50,0.09,1.30,0.65,0.91,0,1)
            for z:Float in [-0.5,0.5] { detailBox(n,0.10,0.5,0.10,0.65,0.63,z,1) }
            for z:Float in [-0.38,0.12] { cylinder(n,0.12,0.025,0.65,0.98,z,cream);sphere(n,0.09,0.65,1.025,z,color(0.82,0.63,0.27)).scale=SCNVector3(1,0.5,0.8) }
            beam(n,from:SCNVector3(-0.78,0.41,0.67),to:SCNVector3(-0.78,1.28,0.62),radius:0.026,tint:wood)
        default: // Open pavilion, visible seating and a proper tea service.
            for x:Float in [-0.70,0.70] { for z:Float in [-0.65,0.65] { cylinder(n,0.055,1.36,x,1.05,z,wood) } }
            pitchedRoof(n,w:1.95,d:1.88,y:1.90,tint:sage)
            cylinder(n,0.40,0.065,0,0.88,0,wood);cylinder(n,0.075,0.45,0,0.64,0,wood)
            for x:Float in [-0.60,0.60] { detailBox(n,0.22,0.09,1.05,x,0.64,0,1);for z:Float in [-0.4,0.4] { detailBox(n,0.08,0.24,0.09,x,0.49,z,1) } }
            sphere(n,0.11,0,1.01,0,cream).scale=SCNVector3(1,0.8,1)
            beam(n,from:SCNVector3(0.06,1.01,0),to:SCNVector3(0.19,1.07,0),radius:0.028,tint:cream)
            for x:Float in [-0.21,0.21] { cylinder(n,0.052,0.07,x,0.96,0.15,sage) }
            for x:Float in [-0.70,0.70] { glow(sphere(n,0.075,x,1.49,0.65,cream),cream) }
        }
        // Upgrades add crafted edging, planters and lanterns to every new model.
        if level>=2 { for z:Float in [-0.86,0.86] { box(n,1.8,0.035,0.035,0,0.41,z,brass,metal:0.5) } }
        if level>=3 { for x:Float in [-0.80,0.80] { cylinder(n,0.11,0.16,x,0.48,0.71,wood);foliage(n,index:5,x:x,y:0.55,z:0.71,height:0.35) } }
        if level>=4 { for x:Float in [-0.79,0.79] { cylinder(n,0.027,0.93,x,0.85,-0.79,brass);glow(sphere(n,0.065,x,1.35,-0.79,cream),cream) } }
        return true
    }

    static func setTrainMotion(_ root:SCNNode,active:Bool) {
        root.childNode(withName:"train-motion",recursively:false)?.removeFromParentNode()
        root.childNode(withName:"train-station",recursively:false)?.isHidden=active
        root.enumerateChildNodes { node,_ in
            if node.name == "parked-sleeper" { node.isHidden=active }
            if node.name == "train-wheel" {
                node.removeAction(forKey:"roll")
                if active { node.runAction(.repeatForever(.rotateBy(x:0,y:0,z:2*CGFloat.pi,duration:0.8)),forKey:"roll") }
            }
        }
        guard active else { return }
        let motion=SCNNode();motion.name="train-motion";root.addChildNode(motion)
        // Periodic scenery flows past a coherent train. Each tile wraps outside the camera.
        for i in 0..<48 {
            let p=SCNNode();p.position.x=CGFloat(i)*0.5-12;motion.addChildNode(p)
            detailBox(p,0.15,0.075,1.8,0,-0.125,0,1)
            let x=p.position.x
            p.runAction(.repeatForever(.customAction(duration:4) { node,t in node.position.x = -12 + (x+12+CGFloat(t)*6).truncatingRemainder(dividingBy:24) }))
        }
        for i in 0..<16 {
            let tree=SCNNode();let initial=CGFloat(i)*3-24;tree.position.x=initial;motion.addChildNode(tree)
            foliage(tree,index:i%3==0 ? 2:1,x:0,y:-0.38,z:Float(i%2==0 ? -4.7:4.8),height:2.0+CGFloat(i%3)*0.45)
            tree.runAction(.repeatForever(.customAction(duration:8) { node,t in node.position.x = -24+(initial+24+CGFloat(t)*6).truncatingRemainder(dividingBy:48) }))
        }
        for i in 0..<7 {
            let puff=sphere(motion,0.10,-6.14,1.98,0,color(0.91,0.93,0.88));puff.opacity=0
            puff.runAction(.repeatForever(.sequence([.wait(duration:Double(i)*0.18),.group([
                .customAction(duration:1.4) { node,t in let q=CGFloat(t)/1.4;node.position=SCNVector3(-6.14+q*1.8,1.98+q*1.7,0);node.scale=SCNVector3(1+q*3,1+q*3,1+q*3);node.opacity=0.55*(1-q) }
            ]),.wait(duration:Double(6-i)*0.18)])))
        }
    }
}
