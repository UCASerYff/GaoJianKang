import AppKit
import SceneKit

@main struct RewardIslandLayoutTests {
    static func main() {
        let initial = RewardCityGrid.initialPlotIDs
        func layout(_ ids:Set<String>) -> RewardIslandLayout {
            let b = RewardCityGrid.bounds(for:RewardCityGrid.renderedPlotIDs(for:ids))
            return RewardIslandLayout(minRow:b.minRow,maxRow:b.maxRow,minColumn:b.minColumn,maxColumn:b.maxColumn)
        }
        let small = layout(initial)
        assert(abs(small.centerX) < 0.001 && abs(small.centerZ) < 0.001)
        assert(small.width > 15 && small.depth > 15)
        var east = initial
        for c in 5...12 {east.insert(RewardCityGrid.id(row:3,column:c))}
        let wide = layout(east)
        assert(wide.width > small.width && wide.depth == small.depth)
        assert(wide.centerX > small.centerX && wide.centerZ == small.centerZ)
        assert(wide.rockDepth >= small.rockDepth && wide.overviewScale > small.overviewScale)
        var west = initial
        for c in -8...1 {west.insert(RewardCityGrid.id(row:3,column:c))}
        let shifted = layout(west)
        assert(shifted.centerX < 0 && shifted.width > small.width)
        let big = Set((-10...14).flatMap { r in (-12...16).map {RewardCityGrid.id(row:r,column:$0)}})
        let large = layout(big)
        assert(large.depth > wide.depth && large.width > wide.width)
        for ids in [initial,east,west,big] {
            let shape=layout(ids)
            let plots=RewardCityGrid.renderedPlotIDs(for:ids)
            for id in plots {
                let p=RewardCityGrid.components(of:id)!
                let x=CGFloat(p.column*3-9),z=CGFloat(p.row*3-9)
                assert(abs(x-shape.centerX)+1.5 < shape.width/2)
                assert(abs(z-shape.centerZ)+1.5 < shape.depth/2)
            }
            let node=RewardFloatingIsland.make(layout:shape,rock:nil,grass:nil)
            let box=node.boundingBox
            assert(box.min.y < -shape.rockDepth)
            assert(box.max.y <= 0.1)
            assert(node.childNodes.count < 160)
        }
        print("PASS: initial, positive/negative asymmetric expansion, large city, island coverage, depth and camera fit; no user save modified")
    }
}
