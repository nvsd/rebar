import SwiftUI

@main
struct RebarApp: App {
    @State private var remote = RemoteController()

    var body: some Scene {
        MenuBarExtra("Rebar", systemImage: "av.remote") {
            RemoteView()
                .environment(remote)
        }
        .menuBarExtraStyle(.window)
    }
}
