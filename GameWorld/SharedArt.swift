import AppKit
import ImageIO

/// Named AppKit images are shared by the seven independently compiled frameworks.
/// Decode authored surface atlases once at a bounded resolution instead of once per tile.
enum GQSharedArt {
    static func image(_ url:URL,maxPixels:Int=2048)->NSImage? {
        let key=NSImage.Name("GQNS.art."+url.lastPathComponent+".\(maxPixels)")
        if let image=NSImage(named:key) { return image }
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixels,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        let image=NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height));image.setName(key);return image
    }
}
