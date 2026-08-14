import SwiftUI

@main
struct EarTalkApp: App {
    @StateObject private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onOpenURL { session.handleOpenURL($0) }
                .onAppear { session.handleLaunchArguments(ProcessInfo.processInfo.arguments) }
        }
    }
}
