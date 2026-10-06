import AppKit
import SceneKit
@main struct ExpansionRender {
    static func main() throws {
        _ = NSApplication.shared
        for mode in ["island","train"] {
            var items=[GQWorldItem(id:"__world",title:"",kind:"__world",level:3,x:0,z:0,movable:false)]
            let kinds:[String]
            switch mode {
            case "station": kinds=["compute","archive","studio","habitat"]
            case "island": kinds=["rainCollector","orchard","workshop","windmill","kitchen","teaHouse"]
            case "cat": kinds=["cat","pantry","playroom","greenhouse","observatory","furniture0"]
            default: kinds=["engine","sleeper","dining","observation","garden","library"]
            }
            let sites:[(Double,Double)] = mode == "island" ? [(-3.5,-2.5),(0,-2.5),(3.5,-2.5),(-3.5,2),(0,2),(3.5,2)] : mode == "cat" ? [(0,0),(-4.2,-1.8),(3.5,1.6),(-3.5,2.1),(3.6,-2),(1,2)] : [(-3.4,-3.1),(3.4,-3.1),(-3.4,3.1),(3.4,3.1)]
            for (i,k) in kinds.enumerated() {
                let p=mode == "train" ? (Double(i)*2.25-5.5,0.0) : sites[i%sites.count]
                items.append(GQWorldItem(id:k,title:k,kind:k,level:k == "cat" ? 0 : 4,x:p.0,z:p.1))
            }
            if mode == "station" { for i in 0..<4 { items.append(GQWorldItem(id:"acc\(i)",title:"Account",kind:"account",level:i%3+1,x:sin(Double(i)*1.57)*5.9,z:cos(Double(i)*1.57)*5.9)) } }
            let scene=GQWorldBuilder.scene(mode:mode,items:items,selectedID:nil)
            if mode == "train" { GQWorldBuilder.setTrainMotion(scene.rootNode,active:true) }
            let camera=scene.rootNode.childNode(withName:"camera",recursively:false)!
            let a=Double.pi*(mode == "station" ? 38 : 34)/180
            camera.position=SCNVector3(sin(a)*19,mode == "station" ? 12 : 13,cos(a)*19);camera.look(at:SCNVector3(0,0,0));camera.camera?.orthographicScale=mode == "cat" ? 9.8 : 8.5
            let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=scene;renderer.pointOfView=camera
            renderer.update(atTime:0);renderer.update(atTime:1)
            let im=renderer.snapshot(atTime:1,with:CGSize(width:1400,height:800),antialiasingMode:.multisampling4X)
            let data=NSBitmapImageRep(data:im.tiffRepresentation!)!.representation(using:.png,properties:[:])!
            try data.write(to:URL(fileURLWithPath:"/tmp/gq358-\(mode).png"))
            for item in items where item.kind != "__world" { assert(scene.rootNode.childNode(withName:"item:\(item.id)",recursively:false) != nil) }
            print("Rendered \(mode)")
        }
    }
}
