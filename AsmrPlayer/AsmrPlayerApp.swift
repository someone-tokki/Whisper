import SwiftUI

@main
struct WhisperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var player: PlayerViewModel

    init() {
        let settings = AppSettings.shared
        _settings = StateObject(wrappedValue: settings)
        _player = StateObject(wrappedValue: PlayerViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
