import AppKit

final class PostureHistoryView: NSView {
    var statesProvider: (() -> [PostureHistoryState])?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Posture history for the last hour")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        "Posture — last hour".draw(
            at: NSPoint(x: 10, y: 5),
            withAttributes: titleAttributes
        )

        let plotRect = NSRect(x: 10, y: 24, width: bounds.width - 20, height: 38)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: plotRect, xRadius: 4, yRadius: 4).fill()

        let states = statesProvider?() ?? []
        if !states.isEmpty {
            let columnWidth = plotRect.width / CGFloat(states.count)
            for (index, state) in states.enumerated() {
                color(for: state).setFill()
                NSRect(
                    x: plotRect.minX + (CGFloat(index) * columnWidth),
                    y: plotRect.minY,
                    width: max(1, columnWidth - 0.45),
                    height: plotRect.height
                ).fill()
            }
        }

        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        "60m ago".draw(
            at: NSPoint(x: plotRect.minX, y: 66),
            withAttributes: captionAttributes
        )

        let nowText = NSAttributedString(string: "now", attributes: captionAttributes)
        nowText.draw(at: NSPoint(
            x: plotRect.maxX - nowText.size().width,
            y: 66
        ))
    }

    private func color(for state: PostureHistoryState) -> NSColor {
        switch state {
        case .good:
            return .systemGreen
        case .bad:
            return .systemRed
        case .noRecording:
            return NSColor.systemGray.withAlphaComponent(0.5)
        }
    }
}
