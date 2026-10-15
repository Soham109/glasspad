import SwiftUI
import UIKit

/// Which way the app may turn. Automatic follows the phone; the other two hold the screen
/// still, which matters on a trackpad you set down on a desk or sofa arm.
enum OrientationChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, portrait, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }

    /// Upside-down portrait is left out: Face ID iPhones do not use it.
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .automatic: .allButUpsideDown
        case .portrait: .portrait
        case .landscape: .landscape
        }
    }
}

/// Answers UIKit's "which orientations?" question from the saved choice. SwiftUI's hosting
/// controller asks the app delegate, so this is the one place the mask comes from.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// Applies orientation changes with the iOS 16 scene geometry API.
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask { PhoneSettings.shared.orientation.mask }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// The orientation the interface is in right now.
    static var current: UIInterfaceOrientation {
        scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    /// Tells UIKit the allowed set changed and turns the screen if it now has to.
    static func apply() {
        guard let scene else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let vc = controller {
                vc.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = vc.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // Refused only when the request conflicts with the app's own Info.plist list,
            // which cannot happen with these three masks.
        }
    }

    /// The quick toggle: hold whatever way the phone is now, or follow it again.
    static func toggle() {
        let settings = PhoneSettings.shared
        if settings.orientation == .automatic {
            settings.orientation = current.isLandscape ? .landscape : .portrait
        } else {
            settings.orientation = .automatic
        }
    }
}
