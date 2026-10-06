import AppKit
import SceneKit

extension GQWorldBuilder {
    static func explorerMatteFinish(_ root:SCNNode) {
        root.enumerateChildNodes { node,_ in
            for material in node.geometry?.materials ?? [] {
                material.roughness.contents=max(0.72,(material.roughness.contents as? NSNumber)?.doubleValue ?? 0.72)
                material.metalness.contents=min(0.35,(material.metalness.contents as? NSNumber)?.doubleValue ?? 0)
                material.emission.intensity=min(0.28,material.emission.intensity)
            }
        }
    }
    // Seamless, object-locked terrain shading: no repeating bitmap or low-resolution globe texture.
    static func explorerTerrain(_ kind:Int)->SCNMaterial {
        let material=mat(.white,rough:0.87)
        let common="""
        #pragma declaration
        float surveyHash(float3 p) { return fract(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453); }
        float surveyNoise(float3 p) {
            float3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
            return mix(mix(mix(surveyHash(i),surveyHash(i+float3(1,0,0)),f.x),mix(surveyHash(i+float3(0,1,0)),surveyHash(i+float3(1,1,0)),f.x),f.y),mix(mix(surveyHash(i+float3(0,0,1)),surveyHash(i+float3(1,0,1)),f.x),mix(surveyHash(i+float3(0,1,1)),surveyHash(i+float3(1,1,1)),f.x),f.y),f.z);
        }
        float surveyTerrain(float3 p) {
            float v=0.0,a=0.53;
            for(int i=0;i<5;i++){v+=a*surveyNoise(p);p=p*2.07+float3(7.1,3.7,11.3);a*=0.48;}
            return v;
        }
        #pragma body
        float2 uv=_surface.diffuseTexcoord;
        float3 p=float3(cos(uv.x*6.283185)*sin(uv.y*3.141593),cos(uv.y*3.141593),sin(uv.x*6.283185)*sin(uv.y*3.141593));
        float n=surveyTerrain(p*5.7);
        float fine=surveyTerrain(p*55.0);
        float3 terrain;
        """
        let variants=[
        """
        terrain=mix(float3(0.16,0.20,0.26),float3(0.66,0.67,0.65),smoothstep(0.22,0.70,n));
        terrain*=0.78+fine*0.5;
        """,
        """
        float cracks=pow(1.0-abs(sin(n*35.0+p.y*4.0)),18.0);
        terrain=mix(float3(0.16,0.44,0.62),float3(0.83,0.95,0.96),smoothstep(0.28,0.64,n));
        terrain=mix(terrain,float3(0.10,0.32,0.48),cracks*0.55);terrain*=0.87+fine*0.23;
        """,
        """
        float dunes=sin(p.y*160.0+n*32.0)*0.035;
        terrain=mix(float3(0.32,0.12,0.065),float3(0.89,0.56,0.29),smoothstep(0.24,0.68,n+dunes));
        terrain*=0.81+fine*0.38;
        """,
        """
        float coast=smoothstep(0.49,0.525,n);
        float3 sea=mix(float3(0.015,0.11,0.26),float3(0.05,0.54,0.56),smoothstep(0.25,0.51,n));
        float3 land=mix(float3(0.21,0.49,0.26),float3(0.045,0.21,0.12),smoothstep(0.52,0.70,n));
        terrain=mix(sea,land,coast);
        float clouds=smoothstep(0.58,0.72,surveyTerrain(p*8.0+float3(14,3,9)));
        terrain=mix(terrain,float3(0.91,0.97,1.0),clouds*0.85);
        _surface.roughness=mix(0.68,0.94,coast);
        """,
        """
        float bands=0.5+0.5*sin(p.y*45.0+surveyTerrain(p*9.0)*9.0);
        terrain=mix(float3(0.21,0.14,0.33),float3(0.68,0.49,0.66),bands);
        terrain=mix(terrain,float3(0.79,0.67,0.69),smoothstep(0.58,0.68,n)*0.65);terrain*=0.88+fine*0.24;
        """
        ]
        material.shaderModifiers=[.surface:common+"\n"+variants[min(4,max(0,kind))]+"\n_surface.diffuse.rgb=terrain;\n_surface.emission.rgb=float3(0.05,0.16,0.24)*pow(1.0-abs(dot(normalize(_surface.normal),normalize(_surface.view))),4.0);"]
        return material
    }
    static func explorerPanel(_ parent:SCNNode,_ w:CGFloat,_ h:CGFloat,_ d:CGFloat,_ x:Float,_ y:Float,_ z:Float,_ style:Int) {
        let base=box(parent,w,h,d,x,y,z,color(0.30,0.38,0.46),chamfer:0.06,metal:0.65)
        let dark=color(0.08,0.14,0.20),silver=color(0.55,0.66,0.72)
        for row in 0..<max(1,Int(d/0.7)) {
            let p = -Float(d)*0.5+0.35+Float(row)*0.7
            box(base,w*0.91,0.009,0.016,0,Float(h)/2+0.006,p,dark,chamfer:0)
        }
        for side:Float in [-1,1] {
            box(base,0.025,0.012,d*0.90,side*Float(w)*0.40,Float(h)/2+0.008,0,silver,chamfer:0)
            for end:Float in [-1,1] { cylinder(base,0.034,0.018,side*Float(w)*0.43,Float(h)/2+0.015,end*Float(d)*0.42,dark,metal:0.8) }
        }
    }
    static func explorerStars(_ n:SCNNode) {
        for i in 0..<170 {
            let a=Float(i*137%360)*Float.pi/180,r=Float(16+i%16)
            let star=sphere(n,i%17==0 ? 0.045 : 0.016,sin(a)*r,Float(i*11%25)-9,cos(a)*r,.white)
            star.castsShadow=false;glow(star,i%3==0 ? color(0.54,0.73,1) : .white)
        }
    }
    static func explorerPort(_ n:SCNNode,stage:Int) {
        explorerStars(n)
        let iron=color(0.11,0.18,0.27),silver=color(0.63,0.72,0.81),cyan=color(0.25,0.86,0.98)
        let planet=sphere(n,3.8,-13,-5,-14,color(0.15,0.28,0.43));planet.geometry?.materials=[explorerTerrain(4)];(planet.geometry as? SCNSphere)?.segmentCount=96;planet.scale.y=0.95
        ring(planet,r:5.0,pipe:0.08,y:0,tint:color(0.52,0.41,0.70)).eulerAngles.z=0.3
        // Four cantilevered service decks and one central launch rail.
        explorerPanel(n,4.1,0.45,5.1,0,-0.35,0,0)
        for x:Float in [-3.7,3.7] { for z:Float in [-3.1,2.8] {
            let deck=box(n,3.7,0.34,3.6,x,-0.35,z,iron,chamfer:0.20,metal:0.5)
            for dx:Float in [-1.7,1.7] { glow(box(deck,0.045,0.06,3.2,dx,0.20,0,cyan),cyan) }
            beam(n,from:SCNVector3(0,-0.5,0),to:SCNVector3(x,-0.5,z),radius:0.23,tint:silver)
            for j in 0..<5 { box(deck,0.55,0.02,0.05,Float(j-2)*0.62,0.19,1.6,silver,chamfer:0) }
        } }
        for z:Float in [-1.85,1.85] {
            explorerPanel(n,3.6,0.18,0.28,0,0.03,z,0)
            for i in 0..<9 { glow(box(n,0.12,0.035,0.08,Float(i-4)*0.39,0.14,z,cyan),cyan) }
        }
        let dock=SCNNode();dock.position=SCNVector3(0,0.6,0);n.addChildNode(dock);explorerShip(dock,level:max(1,min(stage,4)))
        dock.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.12,z:0,duration:2),.moveBy(x:0,y:-0.12,z:0,duration:2)])))
        // Gantry crane and exposed pipework make the port read as an operating shipyard.
        for x:Float in [-1.8,1.8] { cylinder(n,0.09,2.1,x,0.75,-2.0,silver,metal:0.6) }
        box(n,3.8,0.16,0.30,0,1.87,-2.0,silver,metal:0.6)
        let hook=SCNNode();n.addChildNode(hook);hook.position=SCNVector3(0,1.4,-2)
        box(hook,0.4,0.6,0.32,0,0,0,iron);glow(sphere(hook,0.07,0,-0.35,0,cyan),cyan)
        hook.runAction(.repeatForever(.sequence([.moveBy(x:1.2,y:0,z:0,duration:3),.moveBy(x:-1.2,y:0,z:0,duration:3)])))
        for x:Float in [-5.7,5.7] { for row in 0..<3 {
            let panel=box(n,1.6,0.05,0.82,x,-0.55,Float(row-1)*0.94,color(0.05,0.15,0.33),metal:0.6)
            for j in 0..<7 { box(panel,0.012,0.008,0.78,Float(j-3)*0.21,0.033,0,silver,chamfer:0) }
        } }
    }
    static func explorerShip(_ n:SCNNode,level:Int) {
        let white=color(0.81,0.86,0.90),dark=color(0.09,0.16,0.23),gold=color(0.90,0.57,0.23),cyan=color(0.22,0.83,1.0)
        let hull=box(n,2.45,0.55,0.85,0,0.43,0,white,chamfer:0.22,metal:0.50);hull.name="probe-hull"
        let nose=SCNCone(topRadius:0,bottomRadius:0.46,height:1.12);nose.materials=[mat(white,metal:0.5)]
        let tip=SCNNode(geometry:nose);tip.position=SCNVector3(1.63,0.43,0);tip.eulerAngles.z = -.pi/2;n.addChildNode(tip)
        let glass=box(n,0.83,0.29,0.65,0.68,0.75,0,color(0.08,0.36,0.49),chamfer:0.15,metal:0.7)
        glass.geometry?.firstMaterial?.emission.contents=color(0.03,0.15,0.21)
        for side:Float in [-1,1] {
            let wing=box(n,1.5,0.09,1.0,-0.35,0.37,side*0.78,white,chamfer:0.045,metal:0.4);wing.eulerAngles.y=CGFloat(side)*0.28
            box(wing,0.18,0.025,0.89,-0.2,0.06,0,gold,chamfer:0)
            let engine=cylinder(n,0.22,0.9,-1.1,0.43,side*0.61,dark,metal:0.7);engine.eulerAngles.z = .pi/2
            for x:Float in [-1.40,-1.18,-0.96] { let collar=ring(n,r:0.23,pipe:0.035,y:0,tint:white);collar.position=SCNVector3(x,0.43,side*0.61);collar.eulerAngles.z = .pi/2 }
            let flame=sphere(n,0.20,-1.68,0.43,side*0.61,cyan);flame.scale=SCNVector3(2.2,0.68,0.68);glow(flame,cyan);flame.name="ion-exhaust"
            flame.runAction(.repeatForever(.sequence([.scale(by:1.16,duration:0.3),.scale(by:1/1.16,duration:0.3)])))
            for i in 0..<4 { box(n,0.19,0.025,0.14,Float(i)*0.3-0.65,0.72,side*0.32,dark,chamfer:0.012) }
            cylinder(n,0.03,0.30,-0.8,0.12,side*0.56,dark)
            box(n,0.4,0.05,0.2,-0.8,-0.03,side*0.56,dark)
        }
        if level>=2 { box(n,0.58,0.22,0.36,-0.48,0.80,0,gold,chamfer:0.05,metal:0.6) }
        if level>=3 { for z:Float in [-1.03,1.03] { glow(box(n,0.75,0.06,0.09,-0.52,0.5,z,cyan),cyan) } }
        if level>=4 { let a=ring(n,r:0.22,pipe:0.04,y:1.0,tint:gold);a.position.x = -0.7;a.eulerAngles.z = .pi/2 }
    }
    static func explorerFacility(_ n:SCNNode,_ item:GQWorldItem) {
        if item.kind=="account" { premiumStationPod(n,item);return }
        let level=max(1,item.level),silver=color(0.70,0.78,0.83),dark=color(0.09,0.17,0.25),cyan=color(0.25,0.83,0.96),gold=color(0.91,0.62,0.28)
        explorerPanel(n,2.7,0.18,2.5,0,0.04,0,0)
        switch item.kind {
        case "compute":
            // A bank of horizontally mounted ion thrusters with radiator fins.
            for i in 0..<min(4,level+1) {
                let z=Float(i)*0.64-Float(min(4,level+1)-1)*0.32
                let engine=cylinder(n,0.32,1.65,0,0.74,z,dark,metal:0.7);engine.eulerAngles.z = .pi/2
                for x:Float in [-0.72,-0.25,0.25,0.72] { let r=ring(n,r:0.34,pipe:0.04,y:0,tint:silver);r.position=SCNVector3(x,0.74,z);r.eulerAngles.z = .pi/2 }
                let core=cylinder(n,0.23,0.05,0.87,0.74,z,cyan);core.eulerAngles.z = .pi/2;glow(core,cyan)
                for j in 0..<5 { box(n,0.045,0.53,0.68,Float(j)*0.15-0.3,0.91,z,silver,chamfer:0.01) }
            }
        case "archive":
            cylinder(n,0.52,0.72,0,0.46,0,dark,metal:0.6)
            let dish=SCNNode();dish.name="survey-dish";dish.position.y=1.2;dish.eulerAngles.z=0.30;n.addChildNode(dish)
            let bowl=sphere(dish,1.02,0,0,0,silver,metal:0.65);bowl.scale.y=0.16
            for r:CGFloat in [0.4,0.7,1.02] { ring(dish,r:r,pipe:0.027,y:0.17,tint:cyan) }
            for i in 0..<8 { let a=Float(i)*Float.pi/4;beam(dish,from:SCNVector3(sin(a)*0.95,0.14,cos(a)*0.95),to:SCNVector3(0,0.75,0),radius:0.02,tint:dark) }
            glow(sphere(dish,0.09,0,0.74,0,cyan),cyan)
            dish.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:24)))
            if level>=2 { for side:Float in [-1,1] { cylinder(n,0.025,1.1,side*1.1,0.72,-0.78,silver);glow(sphere(n,0.05,side*1.1,1.32,-0.78,cyan),cyan) } }
            if level>=3 { explorerPanel(n,0.65,0.75,0.50,0,0.53,0.9,0) }
            if level>=4 { ring(n,r:1.25,pipe:0.045,y:0.19,tint:gold) }
        case "studio":
            explorerPanel(n,1.7,0.43,1.4,0,0.37,0,0)
            for z:Float in [-0.42,0,0.42] { box(n,1.40,0.08,0.25,0,0.65,z,dark);for x:Float in [-0.5,0,0.5] { cylinder(n,0.09,0.15,x,0.74,z,gold,metal:0.5) } }
            for side:Float in (level>=3 ? [-1,1] : [-1]) {
                cylinder(n,0.24,0.3,side*1.05,0.28,-0.6,gold,metal:0.6)
                let arm=SCNNode();arm.position=SCNVector3(side*1.05,0.43,-0.6);n.addChildNode(arm)
                beam(arm,from:SCNVector3(0,0,0),to:SCNVector3(-side*0.2,0.95,0.2),radius:0.12,tint:gold)
                sphere(arm,0.18,-side*0.2,0.95,0.2,dark,metal:0.5)
                beam(arm,from:SCNVector3(-side*0.2,0.95,0.2),to:SCNVector3(-side*0.8,0.58,0.6),radius:0.085,tint:silver)
                glow(sphere(arm,0.05,-side*0.8,0.55,0.6,cyan),cyan)
                arm.runAction(.repeatForever(.sequence([.rotateBy(x:0,y:0.3,z:0,duration:1.5),.rotateBy(x:0,y:-0.3,z:0,duration:1.5)])))
            }
            if level>=2 { for x:Float in [-1.2,1.2] { box(n,0.15,1.7,0.2,x,0.91,0.90,silver) };box(n,2.6,0.18,0.2,0,1.76,0.90,silver) }
            if level>=4 { for i in 0..<3 { explorerPanel(n,0.3,0.35,0.4,Float(i)*0.42-0.4,0.3,1.0,0) } }
        default:
            cylinder(n,0.67,1.5,0,0.93,0,dark,metal:0.65)
            let energy=sphere(n,0.53,0,1.0,0,cyan);glow(energy,cyan)
            for i in 0..<(level+2) {
                let r=ring(n,r:0.9,pipe:0.085,y:0.37+Float(i)*0.38,tint:silver);r.eulerAngles.z=CGFloat(i%2==0 ? 0.16 : -0.16)
                r.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:Double(8+i*3))))
            }
            for i in 0..<4 { let a=Float(i)*Float.pi/2;cylinder(n,0.07,1.8,sin(a)*1.1,1.0,cos(a)*1.1,silver);glow(sphere(n,0.06,sin(a)*1.1,1.92,cos(a)*1.1,gold),gold) }
        }
        // Visible upgrade rails and indicator bars are common, machinery silhouettes are not.
        for i in 0..<level { glow(box(n,0.20,0.06,0.08,Float(i)*0.3-Float(level-1)*0.15,0.19,1.2,gold),gold) }
    }
    static func explorerPlanet(_ n:SCNNode,index:Int) {
        explorerStars(n)
        let palette=[color(0.52,0.57,0.64),color(0.26,0.62,0.79),color(0.69,0.32,0.19),color(0.07,0.37,0.49),color(0.36,0.22,0.53)]
        let tint=palette[min(4,max(0,index))]
        let planet=SCNNode();planet.name="survey-planet";planet.position=SCNVector3(2.0,0,-0.7);n.addChildNode(planet)
        let globe=sphere(planet,3.15,0,0,0,tint);(globe.geometry as? SCNSphere)?.segmentCount=128;globe.geometry?.materials=[explorerTerrain(index)]
        // Tangent-aligned craters, ice spires, mesas and island chains give each world a different surface.
        for i in 0..<66 {
            let y=1-Double(i)*2/66,a=Double(i)*2.39996323,r=sqrt(max(0,1-y*y))
            let detail=SCNNode();detail.position=SCNVector3(r*cos(a)*3.15,y*3.15,r*sin(a)*3.15)
            detail.look(at:SCNVector3(0,0,0));planet.addChildNode(detail)
            let scale=CGFloat(0.10+Double(i%5)*0.05)
            if index==0 {
                let ring=SCNTorus(ringRadius:scale,pipeRadius:0.026);ring.materials=[mat(color(0.37,0.42,0.49))]
                let crater=SCNNode(geometry:ring);crater.eulerAngles.x = .pi/2;detail.addChildNode(crater)
                let pit=sphere(detail,scale*0.86,0,0,0,color(0.43,0.48,0.55));pit.scale.z=0.07
            } else if index==1 {
                let crystal=SCNCone(topRadius:0,bottomRadius:scale,height:scale*2.4);crystal.radialSegmentCount=5;crystal.materials=[mat(color(0.55,0.84,0.91),metal:0.3)]
                let node=SCNNode(geometry:crystal);node.eulerAngles.x = .pi/2;detail.addChildNode(node)
            } else if index==2 {
                let mesa=box(detail,scale*2,scale*1.3,0.1,0,0,0,color(0.82,0.49,0.25),chamfer:scale*0.2);mesa.eulerAngles.z=CGFloat(a)
            } else if index==3 && i%9==0 {
                // Tiny offshore survey beacons, with continents supplied by the terrain material.
                glow(sphere(detail,0.025,0,0,0.06,color(0.33,0.94,0.82)),color(0.25,0.69,0.65))
            }
        }
        if index==4 {
            for i in 0..<6 { let r=ring(planet,r:CGFloat(3.8)+CGFloat(i)*0.16,pipe:0.055,y:0,tint:color(0.62+CGFloat(i)*0.035,0.51,0.74));r.eulerAngles.z=0.36 }
            for i in 0..<12 { let a=Float(i)*0.52;let rock=sphere(planet,0.09+CGFloat(i%3)*0.04,sin(a)*4.5,sin(a)*1.6,cos(a)*4.5,color(0.62,0.54,0.71));rock.scale.y=0.7 }
        }
        planet.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:180)))
        let orbit=ring(n,r:4.1,pipe:0.015,y:-0.7,tint:color(0.14,0.36,0.48));orbit.position.x=2;orbit.eulerAngles.z=0.2
        for i in 0..<7 { let r=ring(n,r:CGFloat(0.08)+CGFloat(i)*0.07,pipe:0.008,y:0,tint:color(0.2,0.65,0.77));r.position=SCNVector3(-0.8,0.2,1.8);r.eulerAngles.z = .pi/2;r.opacity=0.28 }
    }
}
