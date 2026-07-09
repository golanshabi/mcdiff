import AppKit

final class SidebarResizeHandle: NSView {
    var widthProvider: (() -> CGFloat)?
    var resizeHandler: ((CGFloat) -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var isDragging = false {
        didSet { needsDisplay = true }
    }
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var activeTrackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        if let activeTrackingArea {
            removeTrackingArea(activeTrackingArea)
        }
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        addTrackingArea(trackingArea)
        activeTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        dragStartX = superview.convert(event.locationInWindow, from: nil).x
        dragStartWidth = widthProvider?() ?? 0
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let x = superview.convert(event.locationInWindow, from: nil).x
        resizeHandler?(dragStartWidth + x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let lineWidth: CGFloat = isDragging || isHovering ? 3 : 2
        let x = floor((bounds.width - lineWidth) / 2)
        let lineRect = NSRect(x: x, y: 0, width: lineWidth, height: bounds.height)
        NSColor.controlAccentColor.withAlphaComponent(isDragging || isHovering ? 0.95 : 0.72).setFill()
        lineRect.fill()
    }
}
