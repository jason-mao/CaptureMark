import AppKit

enum EditorTool: Int {
    case select
    case text
    case arrow
}

struct TextAnnotation {
    let id: UUID
    var text: String
    var position: CGPoint
    var color: NSColor
    var fontSize: CGFloat
    var outlineColor: NSColor?
}

struct ArrowAnnotation {
    let id: UUID
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var outlineColor: NSColor?
}

enum Annotation {
    case text(TextAnnotation)
    case arrow(ArrowAnnotation)

    var id: UUID {
        switch self {
        case .text(let annotation): annotation.id
        case .arrow(let annotation): annotation.id
        }
    }
}

struct CapturedScreenshot {
    let image: NSImage
    let pixelSize: CGSize

    init(cgImage: CGImage, pointSize: CGSize) {
        image = NSImage(cgImage: cgImage, size: pointSize)
        pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
    }
}
