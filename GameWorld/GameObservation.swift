import SwiftUI

/// Pure presentation: no game actions, settlement, rewards or persistence callbacks.
/// Lazy cards release their SceneKit views when scrolled offscreen.
struct GQGameObservation<Scene:View>:View {
    let status:String
    let detail:String
    var progress:Double? = nil
    @ViewBuilder let scene:()->Scene
    @State private var visible=false
    @AppStorage("gqns.home.compact") private var compact=true
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            Group {
                if visible { scene() } else { Color.primary.opacity(0.04) }
            }.frame(height:compact ? 210 : 300).clipped().allowsHitTesting(false).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:7) {
                Text(status).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let progress { ProgressView(value:min(1,max(0,progress))).tint(.teal) }
            }.padding(16).frame(maxWidth:.infinity,minHeight:76,alignment:.topLeading)
        }
        .onAppear { visible=true }
        .onDisappear { visible=false }
        .allowsHitTesting(false)
    }
}
struct GQGameObservationUnavailable:View {
    var body:some View {
        VStack(spacing:10) {
            Image(systemName:"externaldrive.badge.exclamationmark").font(.title)
            Text(GQNSLanguage.isEnglish ? "Game data unavailable" : "游戏状态暂不可用").font(.headline)
            Text(GQNSLanguage.isEnglish ? "Open the module to inspect the library" : "进入模块检查资料库").font(.caption)
        }.foregroundStyle(.secondary).frame(maxWidth:.infinity).frame(height:392)
    }
}
