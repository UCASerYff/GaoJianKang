import SwiftUI

/// Paging bounds the number of live row views; complete business records remain available.
struct GQHistoryPager:View {
    @Binding var page:Int
    let count:Int
    var size=100
    private var last:Int { max(0,(count-1)/size) }
    var body:some View {
        HStack {
            Text("共 \(count) 条 · 每页 \(size) 条").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("上一页") { page=max(0,page-1) }.disabled(page<=0)
            Text("\(min(page,last)+1) / \(last+1)").monospacedDigit().font(.caption)
            Button("下一页") { page=min(last,page+1) }.disabled(page>=last)
        }.padding(.vertical,8)
            .onChange(of:count) { _,_ in page=min(page,last) }
    }
}
