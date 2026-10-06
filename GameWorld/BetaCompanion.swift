import AppKit
import SceneKit

/// A small floor grid keeps the companion inside the room and away from furniture.
struct BetaFloor {
    struct Cell:Hashable { let x:Int;let z:Int
        var point:SCNVector3 { SCNVector3(Double(x)*0.5,0,Double(z)*0.5) }
    }
    let clear:Set<Cell>
    init(items:[GQWorldItem]) {
        var cells=Set<Cell>()
        let obstacles=items.filter { $0.kind != "__world" && $0.kind != "cat" && !["furniture0","furniture4"].contains($0.kind) }
        for x in -10...10 { for z in -5...6 {
            let px=Double(x)*0.5,pz=Double(z)*0.5
            // Sofa and coffee table are fixed furnishings along the back wall.
            if px > -4.0 && px < -0.4 && pz < -1.35 { continue }
            if obstacles.contains(where:{ hypot($0.x-px,$0.z-pz)<1.35 }) { continue }
            cells.insert(Cell(x:x,z:z))
        } }
        clear=cells
    }
    func nearest(_ p:SCNVector3)->Cell? {
        clear.min { a,b in
            let da=hypot(Double(a.point.x-p.x),Double(a.point.z-p.z)),db=hypot(Double(b.point.x-p.x),Double(b.point.z-p.z))
            if abs(da-db)<0.0001 { return a.x==b.x ? a.z<b.z : a.x<b.x }
            return da<db
        }
    }
    func path(from:Cell,to:Cell)->[Cell] {
        guard clear.contains(from),clear.contains(to) else { return [] }
        var queue=[from],seen:Set<Cell>=[from],previous:[Cell:Cell]=[:],head=0
        while head<queue.count {
            let c=queue[head];head+=1
            if c==to { var result=[c],cursor=c;while let p=previous[cursor] { result.append(p);cursor=p };return result.reversed() }
            for d in [(1,0),(0,1),(-1,0),(0,-1)] {
                let n=Cell(x:c.x+d.0,z:c.z+d.1)
                if clear.contains(n),seen.insert(n).inserted { previous[n]=c;queue.append(n) }
            }
        }
        return []
    }
}

extension GQWorldBuilder {
    static func betaFrames(row:Int)->[NSImage] {
        let counts=[6,8,8,4,5,8,6,6,6,8,8]
        guard counts.indices.contains(row) else { return [] }
        return (0..<counts[row]).compactMap { art("BetaPet",index:row*8+$0,columns:8,rows:11) }
    }
    static func animateBeta(_ node:SCNNode,row:Int) {
        guard let sprite=node.childNode(withName:"cat-sprite",recursively:false),let material=sprite.geometry?.firstMaterial else { return }
        let frames=betaFrames(row:row);guard !frames.isEmpty else { return }
        sprite.removeAction(forKey:"beta-frames")
        material.diffuse.contents=frames[0]
        let duration:Double = row==0 ? 0.20 : row==3 ? 0.18 : 0.12
        let sequence=frames.flatMap { image in [SCNAction.run { _ in material.diffuse.contents=image },SCNAction.wait(duration:duration)] }
        sprite.runAction(.repeatForever(.sequence(sequence)),forKey:"beta-frames")
    }
    static func setBetaMotion(_ root:SCNNode,items:[GQWorldItem],active:Bool,greeting:Bool=false) {
        guard let cat=root.childNode(withName:"item:cat",recursively:true) else { return }
        let current=cat.presentation.position
        cat.removeAction(forKey:"beta-roam");cat.position=current
        animateBeta(cat,row:greeting ? 3 : 0)
        guard active else { return }
        let floor=BetaFloor(items:items)
        guard let start=floor.nearest(current) else { return }
        cat.position=start.point
        var cursor=start,actions:[SCNAction]=[]
        if greeting { actions += [.wait(duration:1.2),.run { n in animateBeta(n,row:0) }] }
        // Each destination is reached through connected, unoccupied floor cells.
        let targets=[SCNVector3(4,0,0),SCNVector3(3,0,3),SCNVector3(-4,0,2.5),SCNVector3(-4,0,-1),SCNVector3(0,0,-1),start.point]
        for target in targets {
            guard let end=floor.nearest(target) else { continue }
            let path=floor.path(from:cursor,to:end)
            guard path.count>1 else { continue }
            actions.append(.run { n in animateBeta(n,row:0) });actions.append(.wait(duration:3.2))
            var index=1
            while index<path.count {
                let origin=path[index-1],dx=path[index].x-origin.x,dz=path[index].z-origin.z
                var last=index
                while last+1<path.count && path[last+1].x-path[last].x==dx && path[last+1].z-path[last].z==dz { last+=1 }
                let endPoint=path[last].point
                let screenDX=Double(dx)*cos(35 * .pi/180)-Double(dz)*sin(35 * .pi/180)
                let row=screenDX>=0 ? 1 : 2
                actions.append(.run { n in animateBeta(n,row:row) })
                actions.append(.move(to:endPoint,duration:Double(last-index+1)*0.5/1.3))
                index=last+1
            }
            cursor=end
        }
        guard !actions.isEmpty else { return }
        actions.append(.run { n in animateBeta(n,row:0) })
        cat.runAction(.repeatForever(.sequence(actions)),forKey:"beta-roam")
    }
}
