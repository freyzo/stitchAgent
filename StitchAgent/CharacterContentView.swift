import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?
    private var trackingArea: NSTrackingArea?
    private var hasPushedHandCursor = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
        window?.invalidateCursorRects(for: self)
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !hasPushedHandCursor {
            NSCursor.pointingHand.push()
            hasPushedHandCursor = true
        }
        character?.handleMouseEntered()
    }
    
    override func mouseExited(with event: NSEvent) {
        if hasPushedHandCursor {
            NSCursor.pop()
            hasPushedHandCursor = false
        }
        character?.handleMouseExited()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // AVPlayerLayer is GPU-rendered so layer.render(in:) won't capture video pixels.
        // Use CGWindowListCreateImage to sample actual on-screen alpha at click point.
        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        // Use the full virtual display height for the CG coordinate flip, not just
        // the main screen. NSScreen coordinates have origin at bottom-left of the
        // primary display, while CG uses top-left. The primary screen's height is
        // the correct basis for the flip across all monitors.
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let flippedY = primaryScreen.frame.height - screenPoint.y

        let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
        guard let windowID = window?.windowNumber, windowID > 0 else { return nil }

        if let image = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0]
            if let ctx = CGContext(
                data: &pixel, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if pixel[3] > 30 {
                    return self
                }
                return nil
            }
        }

        // Fallback: accept click if within center 60% of the view
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.15
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragStartLocation = event.locationInWindow
        windowStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        
        if !isDragging && (abs(deltaX) > 5 || abs(deltaY) > 5) {
            isDragging = true
            character?.isPinnedByUser = true
            // Ensure animation keeps playing when dragged
            character?.queuePlayer.play()
        }
        
        if isDragging {
            let newOrigin = NSPoint(
                x: windowStartOrigin.x + deltaX,
                y: windowStartOrigin.y + deltaY
            )
            window.setFrameOrigin(newOrigin)
            character?.updatePopoverPosition()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            character?.handleClick()
        }
        isDragging = false
    }
}
