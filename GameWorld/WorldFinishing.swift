import AppKit
import SceneKit

// Feature-specific geometry gives each selectable structure a different silhouette.
extension GQWorldBuilder {
    static func finishIsland(_ n:SCNNode, kind:String, level:Int) {
        let timber=color(0.46,0.28,0.17), brass=color(0.87,0.67,0.32)
        switch kind {
        case "campfire":
            for i in 0..<8 {
                let a = Float(i) * Float.pi / 4
                sphere(n,0.16,sin(a)*0.66,0.32,cos(a)*0.66,color(0.57,0.54,0.47))
            }
            for i in 0..<3 {
                let flame=coneNode(n,0.11,0,0.47,Float(i-1)*0.17,0.85,0,color(1,0.75,0.22))
                flame.eulerAngles.z=CGFloat(i-1)*0.14
            }
        case "well":
            cylinder(n,0.06,1.0,0,1.42,0,timber).eulerAngles.z = .pi/2
            cylinder(n,0.17,0.11,-0.72,1.42,0,brass,metal:0.28).eulerAngles.z = .pi/2
            let rope=cylinder(n,0.025,0.55,0,1.03,0,color(0.73,0.65,0.45))
            rope.eulerAngles.z=0.06
            cylinder(n,0.23,0.37,0,0.68,0,timber)
        case "garden","farm","herbGarden":
            for i in 0..<7 {
                let x=Float((i*3)%7-3)*0.18, z=Float((i*5)%7-3)*0.17
                cylinder(n,0.025,0.37,x,0.88,z,color(0.23,0.54,0.29))
                if kind == "herbGarden" {
                    for dx:Float in [-0.11,0.11] { sphere(n,0.09,x+dx,1.00,z,color(0.40,0.58,0.33)) }
                    sphere(n,0.055,x,1.14,z,color(0.73,0.48,0.76))
                } else if kind == "farm" {
                    cone(n,0.14,0,0.38,x,1.10,z,color(0.73,0.60,0.28))
                } else {
                    sphere(n,0.12,x,1.08,z,color(0.85,0.64,0.42))
                }
            }
        case "shelter":
            for x:Float in [-0.73,0.73] { cylinder(n,0.055,1.16,x,1.20,0.68,timber) }
            box(n,1.8,0.10,0.58,0,1.75,0.67,color(0.37,0.49,0.48))
            box(n,0.35,0.18,0.05,0,1.36,0.63,brass)
        case "clinic":
            box(n,0.66,0.13,0.08,0,1.16,0.64,color(0.78,0.30,0.29))
            box(n,0.13,0.66,0.08,0,1.16,0.65,color(0.78,0.30,0.29))
            for x:Float in [-0.51,0.51] { sphere(n,0.055,x,0.82,0.66,brass) }
        case "training":
            for x:Float in [-0.75,0.75] { cylinder(n,0.05,1.55,x,0.98,0.85,timber) }
            cylinder(n,0.045,1.50,0,1.67,0.85,brass).eulerAngles.z = .pi/2
            for x:Float in [-0.35,0.35] { sphere(n,0.16,x,0.52,0.87,color(0.40,0.45,0.48),metal:0.22) }
        default: break
        }
        if level >= 3 && kind != "campfire" {
            for x:Float in [-0.45,0.45] { sphere(n,0.08,x,2.07,0.62,brass,metal:0.30) }
        }
    }

    static func finishCat(_ n:SCNNode, coat:Int) {
        let dark=color(0.16,0.21,0.22), pink=color(0.89,0.52,0.56)
        // Eyes, iris, whiskers, paws and coat patches remain geometry at every view angle.
        for z:Float in [-0.23,0.23] {
            sphere(n,0.115,0.76,0.88,z,dark)
            sphere(n,0.045,0.84,0.91,z+0.012,color(0.74,0.87,0.68))
            sphere(n,0.08,0.62,0.70,z*1.15,color(0.96,0.91,0.83))
            for i in -1...1 {
                let whisker=box(n,0.43,0.009,0.009,0.88,0.67+Float(i)*0.07,z+0.16*(z > 0 ? 1 : -1),color(0.94,0.91,0.82),chamfer:0)
                whisker.eulerAngles.y = z > 0 ? -0.22 : 0.22
            }
        }
        sphere(n,0.07,0.86,0.73,0,pink)
        for x:Float in [-0.36,0.36] { for z:Float in [-0.22,0.22] {
            sphere(n,0.085,x,0.08,z,color(0.94,0.85,0.76))
        } }
        if coat == 0 || coat == 2 {
            for x:Float in [-0.34,-0.09,0.18] {
                let patch=box(n,0.10,0.035,0.42,x,0.88,0,color(0.36,0.32,0.29),chamfer:0.04)
                patch.eulerAngles.z = -0.28
            }
        }
        cylinder(n,0.17,0.08,0.39,0.70,0,color(0.84,0.31,0.36)).eulerAngles.z = .pi/2
        sphere(n,0.07,0.45,0.59,0,color(0.95,0.78,0.35),metal:0.30)
    }

    static func finishStation(_ n:SCNNode, kind:String, level:Int) {
        let silver=color(0.68,0.80,0.87), glow=color(0.36,0.83,0.94)
        switch kind {
        case "compute":
            for x:Float in [-0.38,0,0.38] {
                let tower=box(n,0.24,0.65,0.16,x,1.68,0,silver,metal:0.6)
                tower.eulerAngles.z=0.05
                for y:Float in [1.48,1.64,1.80] { box(n,0.16,0.025,0.02,x,y,0.10,glow,metal:0.4) }
            }
            let dish=cylinder(n,0.35,0.07,0,2.12,0,glow,metal:0.55); dish.eulerAngles.z=0.22
        case "archive":
            for x:Float in [-0.48,-0.16,0.16,0.48] {
                box(n,0.23,0.55,0.31,x,1.68,0,color(0.42,0.47,0.79),metal:0.42)
                box(n,0.17,0.05,0.33,x,1.85,0,silver,metal:0.45)
            }
            box(n,1.42,0.09,0.43,0,2.01,0,silver,metal:0.58)
        case "studio":
            for x:Float in [-0.43,0.43] {
                cylinder(n,0.05,0.90,x,1.83,0,silver,metal:0.55)
                sphere(n,0.18,x,2.28,0,color(0.97,0.59,0.31),metal:0.38)
            }
            let panel=box(n,0.91,0.52,0.05,0,1.78,0.36,color(0.25,0.59,0.75),metal:0.27)
            panel.eulerAngles.x = -0.23
        case "habitat":
            for x:Float in [-0.43,0.43] {
                cylinder(n,0.10,0.47,x,1.61,0,color(0.65,0.76,0.75),metal:0.35)
                sphere(n,0.24,x,1.98,0,color(0.27,0.71,0.49))
            }
            let ring=SCNTorus(ringRadius:0.59,pipeRadius:0.045)
            ring.materials=[mat(color(0.42,0.85,0.61),metal:0.25)]
            let node=SCNNode(geometry:ring); node.position.y=1.68; node.eulerAngles.x=0.40; n.addChildNode(node)
        default: break
        }
        if level >= 3 { sphere(n,0.11,0,2.76,0,glow,metal:0.38) }
    }

    static func finishTrain(_ n:SCNNode, kind:String, level:Int) {
        let brass=color(0.84,0.68,0.40), iron=color(0.31,0.39,0.42)
        switch kind {
        case "engine":
            for x:Float in [-0.9,0.9] { sphere(n,0.15,x,1.05,0.65,color(1,0.83,0.52)) }
            cylinder(n,0.27,0.20,-0.55,1.80,0,iron,metal:0.65)
            for z:Float in [-0.48,0.48] { box(n,1.82,0.04,0.07,0,0.72,z,brass,metal:0.40) }
        case "sleeper":
            for x:Float in [-0.57,0.57] { box(n,0.60,0.07,0.72,x,1.79,0,color(0.82,0.77,0.63),chamfer:0.07) }
            for z:Float in [-0.68,0.68] { box(n,0.26,0.12,0.03,0,1.28,z,brass,metal:0.40) }
        case "dining":
            for x:Float in [-0.6,0,0.6] { cylinder(n,0.10,0.05,x,1.81,0,color(0.97,0.88,0.62),metal:0.15) }
            for z:Float in [-0.68,0.68] { box(n,1.52,0.07,0.03,0,0.87,z,color(0.91,0.73,0.43)) }
        case "observation":
            box(n,1.50,0.48,0.89,0,1.91,0,color(0.43,0.70,0.76),chamfer:0.18,metal:0.22)
            for z:Float in [-0.47,0.47] { box(n,1.60,0.05,0.06,0,2.13,z,brass,metal:0.36) }
        case "garden":
            for x:Float in [-0.55,0,0.55] {
                cylinder(n,0.10,0.20,x,1.87,0,color(0.57,0.40,0.25))
                sphere(n,0.24,x,2.10,0,color(0.26,0.61,0.35))
                sphere(n,0.07,x+0.12,2.19,0,color(0.92,0.47,0.47))
            }
        case "library":
            for x:Float in [-0.55,-0.22,0.11,0.44] {
                box(n,0.23,0.30,0.45,x,1.92,0,color(0.38,0.44+CGFloat(x+0.55)*0.12,0.60),chamfer:0.02)
            }
            box(n,1.85,0.06,1.31,0,2.12,0,brass,metal:0.22)
        default: break
        }
        if level >= 3 { for x:Float in [-0.8,0.8] { sphere(n,0.07,x,1.78,0.52,brass,metal:0.4) } }
    }

    static func finishCamp(_ n:SCNNode,kind:String,level:Int) {
        let gold=color(0.89,0.70,0.37), iron=color(0.32,0.37,0.43)
        switch kind {
        case "forge":
            cylinder(n,0.30,0.08,0,0.11,1.07,iron,metal:0.6)
            cone(n,0.25,0,0.57,0,0.48,1.08,color(1,0.49,0.18))
            box(n,0.66,0.22,0.40,0.72,0.66,0.98,iron,metal:0.67)
            box(n,0.19,0.48,0.18,0.72,0.32,0.98,iron,metal:0.57)
            cylinder(n,0.16,0.9,-0.66,2.03,-0.25,color(0.39,0.33,0.31))
        case "study":
            for x:Float in [-0.76,0.76] { cylinder(n,0.13,2.1,x,1.13,0.86,color(0.58,0.66,0.77),metal:0.28) }
            box(n,1.8,0.14,0.60,0,2.20,0.86,color(0.43,0.54,0.67))
            for x:Float in [-0.39,0,0.39] { box(n,0.29,0.46,0.08,x,1.44,0.89,color(0.36,0.64,0.83),metal:0.21) }
            sphere(n,0.16,0,2.70,0,color(0.56,0.84,1),metal:0.35)
        case "stable":
            for x:Float in [-0.80,-0.27,0.27,0.80] { cylinder(n,0.055,0.68,x,0.43,1.02,color(0.53,0.36,0.23)) }
            box(n,1.92,0.09,0.08,0,0.67,1.02,color(0.65,0.47,0.28))
            box(n,1.92,0.09,0.08,0,0.28,1.02,color(0.65,0.47,0.28))
            for x:Float in [-0.43,0.43] { sphere(n,0.21,x,1.91,0.77,color(0.95,0.81,0.49)) }
        case "altar":
            for x:Float in [-0.77,0.77] { cylinder(n,0.14,1.42,x,1.14,0.80,iron,metal:0.35) }
            box(n,1.86,0.18,0.74,0,1.95,0.80,iron,metal:0.45)
            let ring=SCNTorus(ringRadius:0.48,pipeRadius:0.07)
            ring.materials=[mat(gold,metal:0.65)]
            let node=SCNNode(geometry:ring); node.position=SCNVector3(0,2.52,0); node.eulerAngles.x=0.36; n.addChildNode(node)
        default: break
        }
        if level >= 3 { for x:Float in [-0.55,0.55] { sphere(n,0.07,x,2.47,0.48,gold,metal:0.45) } }
    }

    static func finishBattleGround(_ root:SCNNode,stage:Int) {
        let stone=color(0.45,0.43,0.40), gold=color(0.78,0.59,0.36)
        // Staggered cobbles break up the blank arena without obscuring click targets.
        for row in -4...4 { for col in -7...7 where (row + col) % 2 == 0 {
            let x=Float(col)*0.94 + Float(row%2)*0.32, z=Float(row)*0.88
            let tile=box(root,0.77,0.027,0.69,x,-0.205,z,
                         (row*7+col)%3 == 0 ? color(0.58,0.54,0.47) : stone,chamfer:0.08)
            tile.eulerAngles.y=CGFloat((row*col)%3)*0.04
        } }
        for x:Float in [-3.5,3.5] {
            let ring=SCNTorus(ringRadius:1.30,pipeRadius:0.045)
            ring.materials=[mat(gold,metal:0.35)]
            let marker=SCNNode(geometry:ring)
            marker.position=SCNVector3(x,-0.16,0)
            root.addChildNode(marker)
            for i in 0..<8 {
                let a=Float(i)*Float.pi/4
                sphere(root,0.055,x+sin(a)*1.30,-0.11,cos(a)*1.30,gold,metal:0.28)
            }
        }
        for x:Float in [-7.0,7.0] {
            box(root,0.17,2.24,0.13,x,1.15,0,color(0.41,0.34,0.31))
            let banner=box(root,0.06,1.12,0.68,x,1.63,0.16,
                           stage%2 == 0 ? color(0.61,0.24,0.31) : color(0.29,0.40,0.62))
            banner.eulerAngles.z=x<0 ? -0.06 : 0.06
            sphere(root,0.12,x,2.33,0,gold,metal:0.26)
        }
    }

    @discardableResult private static func coneNode(_ parent:SCNNode,_ bottom:CGFloat,_ top:CGFloat,_ h:CGFloat,
                                                      _ x:Float,_ y:Float,_ z:Float,_ c:NSColor) -> SCNNode {
        let g=SCNCone(topRadius:top,bottomRadius:bottom,height:h); g.materials=[mat(c)]
        let node=SCNNode(geometry:g); node.position=SCNVector3(x,y,z); parent.addChildNode(node); return node
    }
}
