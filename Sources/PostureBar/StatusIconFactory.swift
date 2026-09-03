import AppKit

enum StatusIconFactory {
    private static let goodImage = sprout(color: .systemGreen)
    private static let slouchingImage = spiral(color: .systemRed)
    private static let calibratingImage = ring(color: .systemOrange)
    private static let errorImage = ring(color: .systemRed)
    private static let neutralImage = ring(color: .secondaryLabelColor)

    static func image(for state: PostureDisplayState) -> NSImage {
        switch state {
        case .good:
            return goodImage
        case .slouching:
            return slouchingImage
        case .calibrating:
            return calibratingImage
        case .cameraPermissionDenied, .cameraUnavailable, .error:
            return errorImage
        default:
            return neutralImage
        }
    }

    private static func sprout(color: NSColor) -> NSImage {
        drawImage { _ in
            color.setStroke()
            let stem = NSBezierPath()
            stem.lineWidth = 2.1
            stem.lineCapStyle = .round
            stem.move(to: NSPoint(x: 8.8, y: 2.5))
            stem.curve(
                to: NSPoint(x: 9.0, y: 11.0),
                controlPoint1: NSPoint(x: 8.4, y: 5.4),
                controlPoint2: NSPoint(x: 9.4, y: 8.4)
            )
            stem.stroke()

            color.setFill()
            let leftLeaf = NSBezierPath()
            leftLeaf.move(to: NSPoint(x: 8.8, y: 9.3))
            leftLeaf.curve(
                to: NSPoint(x: 2.7, y: 13.9),
                controlPoint1: NSPoint(x: 7.6, y: 12.1),
                controlPoint2: NSPoint(x: 5.4, y: 14.2)
            )
            leftLeaf.curve(
                to: NSPoint(x: 8.8, y: 9.3),
                controlPoint1: NSPoint(x: 3.2, y: 10.8),
                controlPoint2: NSPoint(x: 5.8, y: 8.7)
            )
            leftLeaf.close()
            leftLeaf.fill()

            let rightLeaf = NSBezierPath()
            rightLeaf.move(to: NSPoint(x: 9.0, y: 10.9))
            rightLeaf.curve(
                to: NSPoint(x: 15.4, y: 14.1),
                controlPoint1: NSPoint(x: 10.8, y: 13.8),
                controlPoint2: NSPoint(x: 13.2, y: 15.0)
            )
            rightLeaf.curve(
                to: NSPoint(x: 9.0, y: 10.9),
                controlPoint1: NSPoint(x: 15.0, y: 11.2),
                controlPoint2: NSPoint(x: 12.2, y: 9.6)
            )
            rightLeaf.close()
            rightLeaf.fill()
        }
    }

    private static func spiral(color: NSColor) -> NSImage {
        drawImage { _ in
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            let center = NSPoint(x: 9, y: 9)
            let steps = 54

            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let angle = progress * .pi * 4.6
                let radius = 0.7 + (progress * 6.7)
                let point = NSPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.line(to: point)
                }
            }
            path.stroke()
        }
    }

    private static func ring(color: NSColor) -> NSImage {
        drawImage { _ in
            color.setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private static func drawImage(
        drawing: @escaping (NSRect) -> Void
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawing(rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
