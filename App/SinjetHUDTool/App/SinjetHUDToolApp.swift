import SwiftUI

@main
struct SinjetHUDToolApp: App {
    @StateObject private var store = HUDStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
