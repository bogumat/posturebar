import AppKit

enum StatusIconFactory {
    private static let goodImage = checkmark(color: .systemGreen)
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

    private static func checkmark(color: NSColor) -> NSImage {
        drawImage { _ in
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2.4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 3.2, y: 9.0))
            path.line(to: NSPoint(x: 7.2, y: 5.0))
            path.line(to: NSPoint(x: 14.8, y: 13.2))
            path.stroke()
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
