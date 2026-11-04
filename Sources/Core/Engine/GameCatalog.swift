import SwiftUI

/// A game the app can launch. Built with `.turn`, `.realtime` or `.solo`.
struct GameEntry: Identifiable {
    let info: GameInfo
    var id: String { info.id }
    let make: @MainActor (GameLaunch, RoomSession?) -> AnyView

    /// Deterministic turn-based game. The shell supplies seats, turn banner, results, rematch and networking.
    static func turn<E: TurnEngine, Board: View>(_ engine: E.Type, @ViewBuilder board: @escaping @MainActor (TurnSession<E>) -> Board) -> GameEntry {
        GameEntry(info: E.info) { launch, room in
            AnyView(TurnGameScreen<E, Board>(launch: launch, room: room, board: board))
        }
    }

    /// Real-time game driven by `RealtimeSession`.
    static func realtime<Content: View>(_ info: GameInfo, @ViewBuilder content: @escaping @MainActor (RealtimeSession) -> Content) -> GameEntry {
        GameEntry(info: info) { launch, room in
            AnyView(RealtimeGameScreen(info: info, launch: launch, room: room, content: content))
        }
    }

    /// Single-player game with its own full-screen UI.
    static func solo<Content: View>(_ info: GameInfo, @ViewBuilder content: @escaping @MainActor () -> Content) -> GameEntry {
        GameEntry(info: info) { _, _ in AnyView(SoloGameScreen(info: info, content: content)) }
    }
}

@MainActor
enum GameCatalog {
    static let all: [GameEntry] = [
        .turn(LudoEngine.self) { LudoBoardView(session: $0) },
        .turn(SnakesLaddersEngine.self) { SnakesLaddersBoardView(session: $0) },
        .realtime(CarromView.info) { CarromView(session: $0) },
        .turn(MancalaEngine.self) { MancalaBoardView(session: $0) },
        .turn(GoatsTigersEngine.self) { GoatsTigersBoardView(session: $0) },
        .turn(ChessEngine.self) { ChessBoardView(session: $0) },
        .turn(CheckersEngine.self) { CheckersBoardView(session: $0) },
        .turn(ReversiEngine.self) { ReversiBoardView(session: $0) },
        .turn(ConnectFourEngine.self) { ConnectFourBoardView(session: $0) },
        .turn(GomokuEngine.self) { GomokuBoardView(session: $0) },
        .turn(UltimateTTTEngine.self) { UltimateTTTBoardView(session: $0) },
        .turn(DotsBoxesEngine.self) { DotsBoxesBoardView(session: $0) },
        .turn(MemoryEngine.self) { MemoryBoardView(session: $0) },
        .realtime(AirHockeyView.info) { AirHockeyView(session: $0) },
        .solo(Game2048View.info) { Game2048View() },
        .solo(SnakeView.info) { SnakeView() },
        .solo(BlocksView.info) { BlocksView() },
        .solo(MinesweeperView.info) { MinesweeperView() },
        .solo(SudokuView.info) { SudokuView() },
    ]

    static func entry(_ id: String) -> GameEntry? { all.first { $0.id == id } }
    static func info(_ id: String) -> GameInfo? { entry(id)?.info }

    static func entries(in origin: GameOrigin) -> [GameEntry] { all.filter { $0.info.origin == origin } }
    /// Games that can be played with two or more people (locally or over Wi-Fi).
    static var multiplayer: [GameEntry] { all.filter { $0.info.isMultiplayer } }
}
