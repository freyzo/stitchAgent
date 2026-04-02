import AppKit

class ClaudePetController {
    var characters: [WalkerCharacter] = []
    private var displayLink: CVDisplayLink?
    var debugWindow: NSWindow?
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    static let stitchVisibleKey = "petVisibleStitch"
    static let claudeVisibleKey = "petVisibleClaude"

    func start() {
        // Guard against accidental double-start creating duplicate pets.
        if !characters.isEmpty { return }

        UserDefaults.standard.register(defaults: [
            Self.stitchVisibleKey: true,
            Self.claudeVisibleKey: true
        ])

        // Pet 1 / characters[0]: Stitch (`stitch_*` sprites)
        let stitch = WalkerCharacter(
            videoName: "walk-stitch-01",
            spriteIdleName: "stitch_idle",
            spriteWalk1Name: "stitch_walk1",
            spriteWalk2Name: "stitch_walk2"
        )

        stitch.displayHeight = 200
        stitch.accelStart = 0.5
        stitch.fullSpeedStart = 1.0
        stitch.decelStart = 7.5
        stitch.walkStop = 8.0
        stitch.videoDuration = 8.75
        stitch.walkAmountRange = 0.2...0.4
        stitch.yOffset = 0
        stitch.characterColor = NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        stitch.flipXOffset = 0
        stitch.freeRoamMode = true
        stitch.positionX = 0.35
        stitch.positionY = 0.3
        stitch.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.5...1.5)
        stitch.setup()

        // Pet 2 / characters[1]: Claude (`claude_*` sprites)
        let claude = WalkerCharacter(
            videoName: "walk-claude-01",
            spriteIdleName: "claude_idle",
            spriteWalk1Name: "claude_walk1",
            spriteWalk2Name: "claude_walk2"
        )

        claude.displayHeight = 200
        claude.accelStart = 0.5
        claude.fullSpeedStart = 1.0
        claude.decelStart = 7.5
        claude.walkStop = 8.0
        claude.videoDuration = 8.75
        claude.walkAmountRange = 0.2...0.4
        claude.yOffset = 0
        claude.characterColor = NSColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 1.0)
        claude.flipXOffset = 0
        claude.freeRoamMode = true
        claude.positionX = 0.62
        claude.positionY = 0.28
        claude.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.8...2.2)
        claude.setup()

        characters = [stitch, claude]
        characters.forEach { $0.controller = self }

        applySavedCharacterVisibility()

        setupDebugLine()
        startDisplayLink()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    /// Call after menu loads so checkmarks match windows.
    func syncVisibilityMenuItems(stitchItem: NSMenuItem?, claudeItem: NSMenuItem?) {
        guard characters.count >= 2 else { return }
        stitchItem?.state = characters[0].window.isVisible ? .on : .off
        claudeItem?.state = characters[1].window.isVisible ? .on : .off
    }

    func setCharacterVisible(index: Int, visible: Bool) {
        guard characters.indices.contains(index) else { return }
        let char = characters[index]
        if visible {
            char.window.orderFrontRegardless()
        } else {
            if char.isIdleForPopover { char.closePopover() }
            char.window.orderOut(nil)
            char.pauseSpriteForMenuHide()
        }
        let key = index == 0 ? Self.stitchVisibleKey : Self.claudeVisibleKey
        UserDefaults.standard.set(visible, forKey: key)
    }

    private func applySavedCharacterVisibility() {
        guard characters.count >= 2 else { return }
        if !UserDefaults.standard.bool(forKey: Self.stitchVisibleKey) {
            characters[0].window.orderOut(nil)
            characters[0].pauseSpriteForMenuHide()
        }
        if !UserDefaults.standard.bool(forKey: Self.claudeVisibleKey) {
            characters[1].window.orderOut(nil)
            characters[1].pauseSpriteForMenuHide()
        }
    }

    private func triggerOnboarding() {
        guard let stitch = characters.first else { return }
        stitch.isOnboarding = true
        // Show greeting after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            stitch.currentPhrase = "aloha!"
            stitch.showingCompletion = true
            stitch.completionBubbleExpiry = CACurrentMediaTime() + 600
            stitch.showBubble(text: "aloha!", isCompletion: true)
            stitch.playCompletionSound()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        characters.forEach { $0.isOnboarding = false }
    }

    // MARK: - Debug

    private func setupDebugLine() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 2),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.red
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.orderOut(nil)
        debugWindow = win
    }

    private func updateDebugLine(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        guard let win = debugWindow, win.isVisible else { return }
        win.setFrame(CGRect(x: dockX, y: dockTopY, width: dockWidth, height: 2), display: true)
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screenWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        // Each dock slot is the icon + padding. The padding scales with tile size.
        // At default 48pt: slot ≈ 58pt. At 37pt: slot ≈ 47pt. Roughly tileSize * 1.25.
        let slotWidth = tileSize * 1.25

        let persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        let persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

        // Only count recent apps if show-recents is enabled
        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        // show-recents adds its own divider
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth

        let magnificationEnabled = dockDefaults?.bool(forKey: "magnification") ?? false
        if magnificationEnabled,
           let largeSize = dockDefaults?.object(forKey: "largesize") as? CGFloat {
            // Magnification only affects the hovered area; at rest the dock is normal size.
            // Don't inflate the width — characters should stay within the at-rest bounds.
            _ = largeSize
        }

        // Small fudge factor for dock edge padding
        dockWidth *= 1.1
        let dockX = (screenWidth - dockWidth) / 2.0
        return (dockX, dockWidth)
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<ClaudePetController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        return NSScreen.main
    }

    /// The dock lives on the screen where visibleFrame.origin.y > frame.origin.y (bottom dock)
    /// On screens without the dock, visibleFrame.origin.y == frame.origin.y
    private func screenHasDock(_ screen: NSScreen) -> Bool {
        return screen.visibleFrame.origin.y > screen.frame.origin.y
    }

    func tick() {
        guard let screen = activeScreen else { return }

        let screenWidth = screen.frame.width
        let dockX: CGFloat
        let dockWidth: CGFloat
        let dockTopY: CGFloat

        if screenHasDock(screen) {
            // Dock is on this screen — constrain to dock area
            (dockX, dockWidth) = getDockIconArea(screenWidth: screenWidth)
            dockTopY = screen.visibleFrame.origin.y
        } else {
            // No dock on this screen — use full screen width with small margin
            let margin: CGFloat = 40.0
            dockX = screen.frame.origin.x + margin
            dockWidth = screenWidth - margin * 2
            dockTopY = screen.frame.origin.y
        }

        updateDebugLine(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)

        let activeChars = characters.filter { $0.window.isVisible }

        let now = CACurrentMediaTime()
        let anyWalking = activeChars.contains { $0.isWalking }
        for char in activeChars {
            if char.isIdleForPopover { continue }
            if char.isPaused && now >= char.pauseEndTime && anyWalking {
                char.pauseEndTime = now + Double.random(in: 5.0...10.0)
            }
        }
        for char in activeChars {
            char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
        }

        let sorted = activeChars.sorted { $0.positionX < $1.positionX }
        for (i, char) in sorted.enumerated() {
            char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
