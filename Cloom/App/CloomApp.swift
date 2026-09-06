import SwiftUI

@main
struct CloomApp: App {
    @StateObject private var model = AppModel.live

    var body: some Scene {
        WindowGroup {
            SetupView(model: model)
        }
        .defaultSize(width: 660, height: 720)
        .windowResizability(.contentMinSize)
    }
}
