import SwiftUI
import AppKit

enum Theme {
    static let blue = Color(red:0.20,green:0.45,blue:0.82)
    static let teal = Color(red:0.16,green:0.63,blue:0.53)
    static let green = Color(red:0.24,green:0.62,blue:0.36)
    static let orange = Color(red:0.92,green:0.53,blue:0.20)
    static let purple = Color(red:0.48,green:0.36,blue:0.78)
    static func color(_ kind: RecordKind) -> Color { switch kind { case .water: blue; case .meal: orange; case .exercise: green; case .weight: purple } }
    static func background(_ dark: Bool,_ hex: String) -> Color {
        let base = dark ? NSColor(srgbRed:0.075,green:0.082,blue:0.095,alpha:1) : NSColor(srgbRed:0.975,green:0.98,blue:0.985,alpha:1)
        guard let v=UInt32(hex.replacingOccurrences(of:"#",with:""),radix:16),hex.count==7 else { return Color(nsColor:base) }
        let tint=NSColor(srgbRed:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255,alpha:1)
        return Color(nsColor:base.blended(withFraction:0.28,of:tint) ?? base)
    }
}
extension View {
    func card(_ padding: CGFloat = 20) -> some View {
        self.padding(padding).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).stroke(Color.primary.opacity(0.07)))
    }
}
struct SymbolTile: View {
    var symbol: String; var color: Color
    var body: some View { Image(systemName:symbol).font(.system(size:17,weight:.semibold)).foregroundStyle(color).frame(width:40,height:40).background(color.opacity(0.1),in:RoundedRectangle(cornerRadius:11)) }
}
struct SectionTitle: View {
    var title: String; var subtitle: String
    var body: some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:25,weight:.semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary) }.padding(.bottom,6) }
}
struct EmptyCard: View {
    var symbol: String; var title: String; var detail: String
    var body: some View { VStack(spacing:12) { Image(systemName:symbol).font(.system(size:28)).foregroundStyle(Theme.teal).padding(18).background(Theme.teal.opacity(0.08),in:RoundedRectangle(cornerRadius:18)); Text(title).font(.headline); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity,minHeight:190).padding(20) }
}
func number(_ value: Double) -> String { value.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
