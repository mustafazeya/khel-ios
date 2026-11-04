import SwiftUI

@main
struct KhelApp: App {
    @State private var profile = Profile()
    @State private var settings = AppSettings()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profile)
                .environment(settings)
                .environment(router)
                .environment(StatsStore.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct ActiveGame: Identifiable {
    let id = UUID()
    let launch: GameLaunch
}

@MainActor @Observable
final class Router {
    var setupGame: GameEntry?
    var localGame: ActiveGame?
    var room: RoomSession?
    var tab: AppTab = .play

    func leaveRoom() {
        room?.leave()
        room = nil
    }
}

enum AppTab: Hashable { case play, nearby, me }

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Profile.self) private var profile
    @State private var splash = true

    var body: some View {
        @Bindable var router = router
        ZStack {
            TabView(selection: $router.tab) {
                Tab("Play", systemImage: "gamecontroller.fill", value: AppTab.play) { NavigationStack { HomeView() } }
                Tab("Nearby", systemImage: "wifi", value: AppTab.nearby) { NavigationStack { NearbyView() } }
                Tab("Me", systemImage: "person.crop.circle.fill", value: AppTab.me) { NavigationStack { ProfileView() } }
            }
            .background(Theme.bg)
            .sheet(item: $router.setupGame) { entry in GameSetupView(entry: entry).presentationDetents([.large]) }
            .fullScreenCover(item: $router.localGame) { game in
                GameContainer(launch: game.launch, room: nil) { router.localGame = nil }
            }
            .fullScreenCover(isPresented: Binding(get: { router.room != nil }, set: { if !$0 { router.leaveRoom() } })) {
                if let room = router.room { LobbyView(room: room) }
            }

            if splash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeOut(duration: 0.4)) { splash = false }
            if let launch = DebugLaunch.make(profile: profile) { router.localGame = ActiveGame(launch: launch) }
        }
    }
}

struct SplashView: View {
    @Environment(Profile.self) private var profile
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                AvatarView(spec: profile.avatar, size: 96, square: true)
                Text("KHEL").font(.system(size: 44, weight: .black, design: .rounded)).tracking(8)
                    .foregroundStyle(Theme.gradient([0xFF8A1A, 0xFF4E7A]))
                Text("खेल · games, together").font(.footnote).foregroundStyle(Theme.text2)
            }
        }
    }
}

/// Hosts a running game full-screen and wires the exit action.
struct GameContainer: View {
    let launch: GameLaunch
    let room: RoomSession?
    let onExit: @MainActor @Sendable () -> Void

    var body: some View {
        Group {
            if let entry = GameCatalog.entry(launch.gameID) {
                entry.make(launch, room)
            } else {
                Text("Unknown game").foregroundStyle(.white)
            }
        }
        .environment(\.exitGame, onExit)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }
}
