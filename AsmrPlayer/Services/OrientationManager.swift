import SwiftUI
import UIKit

@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published var supportedOrientations: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]

    private init() {}

    func lockToCurrentOrientation() {
        let orientation = currentInterfaceOrientation()
        switch orientation {
        case .landscapeLeft:
            supportedOrientations = .landscapeLeft
        case .landscapeRight:
            supportedOrientations = .landscapeRight
        case .portraitUpsideDown:
            supportedOrientations = .portraitUpsideDown
        default:
            supportedOrientations = .portrait
        }
        refreshSupportedOrientations()
    }

    func unlock() {
        supportedOrientations = [.portrait, .landscapeLeft, .landscapeRight]
        refreshSupportedOrientations()
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .interfaceOrientation ?? .portrait
    }

    private func refreshSupportedOrientations() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                scene.windows.forEach { window in
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations))
            }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.supportedOrientations
    }
}
