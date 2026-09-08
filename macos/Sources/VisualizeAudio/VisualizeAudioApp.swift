import SwiftUI

@main
struct VisualizeAudioApp: App {
    var body: some Scene {
        WindowGroup {
            VisualizerView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
    }
}
