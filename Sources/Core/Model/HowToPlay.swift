import SwiftUI

/// Short "how to play" text for every game, plus a link to video tutorials.
struct HowToPlay {
    let steps: [String]
    /// What to tap, drag or swipe.
    let controls: String
    /// What to type into YouTube.
    let searchTerm: String

    /// A YouTube search for tutorials, so the link never goes stale.
    var videoURL: URL {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: searchTerm)]
        return c.url!
    }

    static func guide(for id: String) -> HowToPlay? { all[id] }

    static let all: [String: HowToPlay] = [
        "ludo": HowToPlay(
            steps: ["Roll the dice. You need a 6 to bring a token out of its yard.",
                    "Move a token clockwise round the track by the number rolled.",
                    "Landing on an opponent sends it back to its yard, unless it is on a star or a start square.",
                    "A 6, a capture or reaching home gives another roll. Three 6s in a row lose the turn.",
                    "Take all four tokens up your coloured column to the centre. You need the exact number to enter."],
            controls: "Tap Roll dice, then tap a glowing token. If only one move is possible it is played for you.",
            searchTerm: "how to play ludo"),
        "snakes": HowToPlay(
            steps: ["Roll the dice and move from square 1 towards 100.",
                    "Land at the bottom of a ladder to climb it.",
                    "Land on a snake's head and you slide down to its tail.",
                    "You must roll the exact number to land on 100. A 6 gives another roll; three 6s in a row lose the move."],
            controls: "Tap Roll dice. Everything else happens automatically.",
            searchTerm: "how to play snakes and ladders"),
        "carrom": HowToPlay(
            steps: ["Place the striker on your baseline.", "Aim and shoot to pocket your own colour. Pocketing your own piece gives another shot.",
                    "The queen scores more but must be covered by pocketing one of your own pieces next.",
                    "Pocketing the striker is a foul. Clear all your pieces to win."],
            controls: "Slide the striker along your baseline, drag back from it to aim and power up, then release.",
            searchTerm: "how to play carrom"),
        "mancala": HowToPlay(
            steps: ["Pick one of your pits. Its seeds are sown one by one counter-clockwise, including your store but skipping your opponent's.",
                    "If your last seed lands in your store, play again.",
                    "If it lands in an empty pit of yours, you capture it and the seeds in the pit opposite.",
                    "When one side is empty, the other player keeps what is left. Most seeds in the store wins."],
            controls: "Tap one of your glowing pits (the bottom row, or the row nearest you).",
            searchTerm: "how to play mancala kalah"),
        "goats": HowToPlay(
            steps: ["Goats (player 1) move first and place one of their 20 goats per turn on any empty point.",
                    "After all goats are placed, they slide along the lines.",
                    "Tigers slide one step, or jump over an adjacent goat along a line to capture it.",
                    "Tigers win by capturing 5 goats. Goats win by trapping every tiger."],
            controls: "Tap an empty point to place a goat. To move, tap a piece, then a green destination.",
            searchTerm: "how to play bagh chal"),
        "chess": HowToPlay(
            steps: ["Each piece moves in its own way. Tap a piece to see its moves: dots are moves, rings are captures.",
                    "Special moves: castling, en passant and pawn promotion.",
                    "Checkmate wins. Stalemate, insufficient material, fifty moves without progress and threefold repetition are draws."],
            controls: "Tap a piece then a square, or drag the piece. Resign is below the board.",
            searchTerm: "how to play chess for beginners"),
        "checkers": HowToPlay(
            steps: ["Move diagonally forward one square.", "If you can jump an opponent's piece you must, and you keep jumping while you can.",
                    "Reach the far row to become a king, which moves and jumps both ways.",
                    "You win when your opponent has no pieces or no legal move."],
            controls: "Tap a piece (orange outlines show pieces that must jump), then a green square.",
            searchTerm: "how to play checkers draughts"),
        "reversi": HowToPlay(
            steps: ["Place a disc on a dotted square so it traps a straight line of opponent discs against another of yours.",
                    "Trapped discs flip to your colour. With no legal move you pass automatically.",
                    "When neither player can move, whoever has more discs wins. Corners are very strong."],
            controls: "Tap a dotted square.",
            searchTerm: "how to play reversi othello"),
        "connect4": HowToPlay(
            steps: ["Take turns dropping a disc into a column. It falls to the lowest free slot.",
                    "Be first to line up four discs in a row, column or diagonal. A full board is a draw."],
            controls: "Tap anywhere in a column.",
            searchTerm: "how to play connect four"),
        "gomoku": HowToPlay(
            steps: ["Take turns placing stones on the intersections. Black moves first.",
                    "Make an unbroken line of five or more stones in any direction to win.",
                    "Block your opponent's open threes and fours, and try to create two threats at once."],
            controls: "Tap or drag to choose a point (the stone shows above your finger), then press Place stone.",
            searchTerm: "how to play gomoku"),
        "ultimate": HowToPlay(
            steps: ["Each big square holds a small tic-tac-toe board.",
                    "Where you play in a small board decides which small board your opponent must play in next. It glows.",
                    "If you are sent to a board that is already decided, you may play anywhere.",
                    "Win three small boards in a row to win."],
            controls: "Tap a square inside a glowing board.",
            searchTerm: "how to play ultimate tic tac toe"),
        "dots": HowToPlay(
            steps: ["Take turns drawing one line between two neighbouring dots.",
                    "Drawing the fourth side of a box claims it and gives you another turn.",
                    "Avoid drawing a box's third side: it lets your opponent take it. Most boxes wins."],
            controls: "Tap or drag near a gap between two dots; a preview shows the line.",
            searchTerm: "how to play dots and boxes"),
        "memory": HowToPlay(
            steps: ["Turn over two cards. A match is kept and you go again.",
                    "A mismatch flips back and the next player goes. Remember where the cards are.",
                    "Alone, finish in as few tries as you can."],
            controls: "Tap a card to flip it.",
            searchTerm: "how to play memory matching game"),
        "airhockey": HowToPlay(
            steps: ["Hit the puck into your opponent's goal with your mallet.", "First to 7 goals wins.",
                    "On two phones, each player controls their own mallet on their own screen."],
            controls: "Drag your mallet with your finger. Move fast to hit harder.",
            searchTerm: "how to play air hockey"),
        "g2048": HowToPlay(
            steps: ["Slide all tiles in one direction. Equal tiles that collide merge into one with the sum.",
                    "Reach the 2048 tile to win, then keep going for a higher score.",
                    "The game ends when the board is full and nothing can merge."],
            controls: "Swipe up, down, left or right. Undo steps back; the menu changes the board size.",
            searchTerm: "how to play 2048"),
        "snake": HowToPlay(
            steps: ["Steer the snake to the food to grow and score.", "Classic: walls are deadly. Wrap: edges wrap round. Speed: it accelerates fast.",
                    "Never run into yourself."],
            controls: "Swipe anywhere to turn. You can queue two quick turns.",
            searchTerm: "how to play snake game"),
        "blocks": HowToPlay(
            steps: ["Guide falling pieces and fill whole rows to clear them.", "Clearing four rows at once scores the most.",
                    "The game speeds up every ten lines. Use hold to save a piece for later."],
            controls: "Drag sideways to move, tap to rotate, drag down to soft drop, flick down to hard drop, swipe up to hold. Or use the buttons.",
            searchTerm: "how to play tetris"),
        "minesweeper": HowToPlay(
            steps: ["Reveal squares. A number shows how many of the 8 neighbours are mines.",
                    "Flag squares you think are mines. Tap a satisfied number to reveal its other neighbours.",
                    "Reveal every safe square to win. Your first tap is always safe."],
            controls: "Tap to reveal, long-press or use the flag button to flag.",
            searchTerm: "how to play minesweeper"),
        "sudoku": HowToPlay(
            steps: ["Fill the grid so every row, column and 3×3 box has 1 to 9 exactly once.",
                    "Turn on Notes to pencil in candidates. Conflicts are highlighted.",
                    "Every puzzle has exactly one solution. Use Hint if you are stuck."],
            controls: "Tap a cell, then a number on the pad.",
            searchTerm: "how to play sudoku for beginners"),
    ]
}

/// Rules, controls and a video link for one game.
struct HowToPlaySheet: View {
    let info: GameInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: info.symbol).font(.system(size: 28, weight: .bold)).frame(width: 56, height: 56)
                            .background(Theme.gradient(info.palette), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(info.title).font(.khTitle).minimumScaleFactor(0.6).lineLimit(1)
                            Text(info.tagline).font(.subheadline).foregroundStyle(Theme.text2)
                        }
                    }
                    Card { Text(info.rules).font(.callout).foregroundStyle(Theme.text2) }
                    if let guide = HowToPlay.guide(for: info.id) {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Kicker(text: "Step by step")
                                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(i + 1)").font(.system(size: 13, weight: .heavy, design: .rounded)).frame(width: 24, height: 24)
                                            .background(Theme.accent, in: Circle()).foregroundStyle(.black)
                                        Text(step).font(.callout)
                                    }
                                }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Kicker(text: "Controls")
                                Label(guide.controls, systemImage: "hand.tap.fill").font(.callout)
                            }
                        }
                        Button { openURL(guide.videoURL) } label: { Label("Watch how to play on YouTube", systemImage: "play.rectangle.fill") }
                            .buttonStyle(PrimaryButtonStyle(tint: Color(red: 1, green: 0.25, blue: 0.25)))
                        Text("Opens YouTube search results for “\(guide.searchTerm)”. Needs an internet connection; the games themselves work offline.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("How to play").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

/// The small "?" button used in game title bars.
struct HowToPlayButton: View {
    let info: GameInfo
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "questionmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36).background(Theme.surface2, in: Circle())
        }
        .accessibilityLabel("How to play")
        .sheet(isPresented: $show) { HowToPlaySheet(info: info) }
    }
}
