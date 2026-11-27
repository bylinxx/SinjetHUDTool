import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: HUDStore
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionView()
                .tabItem {
                    Label("连接", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(0)

            CarDataView()
                .tabItem {
                    Label("车辆数据", systemImage: "gauge")
                }
                .tag(1)

            HUDControlView()
                .tabItem {
                    Label("HUD 控制", systemImage: "slider.horizontal.3")
                }
                .tag(2)

            FirmwareUpgradeView()
                .tabItem {
                    Label("固件刷机", systemImage: "arrow.up.doc")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { tab in
            guard store.connectionState.isConnected, !store.upgradePhase.isBusy else { return }
            switch tab {
            case 1:
                store.setAppPage(.realtimeOBD)
            default:
                store.setAppPage(.homeGeneral)
            }
        }
    }
}
