import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            Tab("Home", systemImage: "server.rack") {
                HomeView(appState: appState)
            }

            Tab("Permissions", systemImage: "heart.text.square") {
                PermissionsView(appState: appState)
            }

            Tab("Token", systemImage: "key.fill") {
                TokenView(appState: appState)
            }

            Tab("Settings", systemImage: "gear") {
                SettingsView(appState: appState)
            }
        }
    }
}
