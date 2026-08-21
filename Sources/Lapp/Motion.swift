import AppKit

/// One place for the feel of every animation, so they all move the same way.
enum Motion {
    /// Decelerating, no overshoot -- the strip should look heavy, not springy.
    static var curve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    }

    static let swipe: TimeInterval = 0.30      // minimising and restoring
    static let travel: TimeInterval = 0.34     // moving to the other edge or screen
    static let overlay: TimeInterval = 0.26    // history and settings sliding in
    static let fade: TimeInterval = 0.18

    static func run(_ duration: TimeInterval,
                    _ body: () -> Void,
                    then completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = curve
            context.allowsImplicitAnimation = true
            body()
        }, completionHandler: completion)
    }
}
