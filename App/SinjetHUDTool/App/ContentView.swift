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
                    Label("车辆", systemImage: "car.fill")
                }
                .tag(1)

            HUDControlView()
                .tabItem {
                    Label("操控", systemImage: "slider.horizontal.3")
                }
                .tag(2)

            FirmwareUpgradeView()
                .tabItem {
                    Label("刷机", systemImage: "arrow.up.doc.fill")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { _ in
            guard store.connectionState.isConnected, !store.upgradePhase.isBusy else { return }
            // 原厂 MeterViewController 使用 0x04 (homeGeneral) 保持实时仪表帧 0x03/0x10 推送
            store.setAppPage(.homeGeneral)
        }
    }
}
