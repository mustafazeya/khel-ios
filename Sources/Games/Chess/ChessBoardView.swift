import SwiftUI

struct ChessBoardView: View {
    let session: TurnSession<ChessEngine>

    private struct Item: Identifiable, Equatable { let id: Int; var piece: Int8; var sq: Int }

    @State private var items: [Item] = []
    @State private var nextID = 100
    @State private var selected: Int?
    @State private var dragFrom: Int?
    @State private var dragPoint: CGPoint?
    @State private var promotion: (from: Int, to: Int)?

    private var state: ChessEngine.State { session.state }
    private var whiteToMove: Bool { state.pos.side == 1 }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }

    /// Black at the bottom when the only human here plays black, or when two people share the phone and it is black's turn.
    private var flipped: Bool {
        if session.mySeats.count > 1 { return !whiteToMove }
        return session.mySeats == [1]
    }

    private var legal: [ChessMove] { canMove ? state.pos.legalMoves() : [] }

    var body: some View {
        VStack(spacing: 8) {
            tray(capturedBy: flipped ? 1 : -1).frame(height: 26)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 8
                ZStack(alignment: .topLeading) {
                    boardCanvas(cell: cell)
                    highlights(cell: cell)
                    ForEach(items) { item in pieceView(item, cell: cell) }
                    if let promotion { promotionPicker(promotion, cell: cell, side: side) }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(boardGesture(cell: cell))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            tray(capturedBy: flipped ? -1 : 1).frame(height: 26)
            if canMove {
                Button { session.submit(ChessEngine.resign) } label: { Label("Resign", systemImage: "flag") }
                    .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 200)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { rebuild() }
        .onChange(of: session.version) { _, _ in sync() }
        .onChange(of: session.isMyTurn) { _, _ in selected = nil; promotion = nil }
    }

    // MARK: Geometry

    private func point(_ sq: Int, cell: CGFloat) -> CGPoint {
        let r = sq / 8, c = sq % 8
        let col = flipped ? 7 - c : c, row = flipped ? 7 - r : r
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    private func square(at p: CGPoint, cell: CGFloat) -> Int? {
        let col = Int(p.x / cell), row = Int(p.y / cell)
        guard (0 ..< 8).contains(col), (0 ..< 8).contains(row) else { return nil }
        return flipped ? (7 - row) * 8 + (7 - col) : row * 8 + col
    }

    // MARK: Drawing

    private func boardCanvas(cell: CGFloat) -> some View {
        Canvas { ctx, size in
            for r in 0 ..< 8 { for c in 0 ..< 8 {
                let light = (r + c) % 2 == 0
                ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                         with: .color(light ? Color(red: 0.93, green: 0.84, blue: 0.70) : Color(red: 0.64, green: 0.44, blue: 0.29)))
            } }
            for i in 0 ..< 8 {
                let file = flipped ? 7 - i : i, rank = flipped ? i + 1 : 8 - i
                let dark = Color(red: 0.64, green: 0.44, blue: 0.29), light = Color(red: 0.93, green: 0.84, blue: 0.70)
                ctx.draw(Text(String(UnicodeScalar(97 + file)!)).font(.system(size: cell * 0.2, weight: .bold, design: .rounded)).foregroundStyle((7 + i) % 2 == 0 ? dark : light),
                         at: CGPoint(x: CGFloat(i) * cell + cell * 0.93, y: size.height - cell * 0.12), anchor: .trailing)
                ctx.draw(Text("\(rank)").font(.system(size: cell * 0.2, weight: .bold, design: .rounded)).foregroundStyle(i % 2 == 0 ? dark : light),
                         at: CGPoint(x: cell * 0.07, y: CGFloat(i) * cell + cell * 0.14), anchor: .leading)
            }
        }
    }

    private func highlights(cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if state.lastFrom >= 0 {
                ForEach([state.lastFrom, state.lastTo], id: \.self) { sq in
                    Rectangle().fill(Color.yellow.opacity(0.38)).frame(width: cell, height: cell).position(point(sq, cell: cell))
                }
            }
            if state.inCheck {
                let k = state.pos.kings[whiteToMove ? 0 : 1]
                Circle().fill(RadialGradient(colors: [.red.opacity(0.9), .red.opacity(0)], center: .center, startRadius: 0, endRadius: cell * 0.62))
                    .frame(width: cell * 1.3, height: cell * 1.3).position(point(k, cell: cell))
            }
            if let selected {
                Rectangle().fill(Color.green.opacity(0.45)).frame(width: cell, height: cell).position(point(selected, cell: cell))
                ForEach(Array(Set(legal.filter { $0.from == selected }.map(\.to))), id: \.self) { to in
                    let capture = state.pos.b[to] != 0 || (abs(state.pos.b[selected]) == 1 && to == state.pos.ep)
                    Group {
                        if capture { Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: cell * 0.09).frame(width: cell * 0.92, height: cell * 0.92) }
                        else { Circle().fill(Color.black.opacity(0.28)).frame(width: cell * 0.3, height: cell * 0.3) }
                    }
                    .position(point(to, cell: cell))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func pieceView(_ item: Item, cell: CGFloat) -> some View {
        let dragging = dragFrom == item.sq && dragPoint != nil
        let pos = dragging ? CGPoint(x: dragPoint!.x, y: dragPoint!.y - cell * 0.35) : point(item.sq, cell: cell)
        return ChessPieceView(piece: item.piece, size: cell * (dragging ? 1.15 : 0.96))
            .position(pos)
            .zIndex(dragging ? 10 : 1)
            .animation(dragging ? nil : .snappy(duration: 0.22), value: item.sq)
            .animation(.snappy(duration: 0.22), value: flipped)
            .allowsHitTesting(false)
    }

    private func promotionPicker(_ p: (from: Int, to: Int), cell: CGFloat, side: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.5)
            HStack(spacing: 6) {
                ForEach([5, 4, 3, 2], id: \.self) { type in
                    Button {
                        promotion = nil; selected = nil
                        session.submit(ChessMove(from: p.from, to: p.to, promo: type))
                    } label: {
                        ChessPieceView(piece: Int8(type) * (whiteToMove ? 1 : -1), size: cell * 1.1)
                            .padding(6).background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .onTapGesture { promotion = nil }
    }

    // MARK: Captured pieces

    private func tray(capturedBy color: Int) -> some View {
        let initial: [Int: Int] = [1: 8, 2: 2, 3: 2, 4: 2, 5: 1]
        // Pieces of the opposite colour that have left the board, captured by `color`.
        var missing: [Int8] = []
        var score = 0
        for t in [5, 4, 3, 2, 1] {
            let present = state.pos.b.filter { Int($0) == -color * t }.count
            let promoted = 0
            for _ in 0 ..< max(0, (initial[t] ?? 0) - present - promoted) { missing.append(Int8(-color * t)) }
        }
        for p in state.pos.b where p != 0 && abs(p) != 6 { score += (p > 0 ? 1 : -1) * color * ChessSearch.values[Int(abs(p))] }
        return HStack(spacing: -8) {
            ForEach(Array(missing.enumerated()), id: \.offset) { _, p in ChessPieceView(piece: p, size: 22) }
            if score > 0 { Text("+\(score / 100)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.text2).padding(.leading, 14) }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    // MARK: Input

    private func boardGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard canMove, promotion == nil else { return }
                if dragFrom == nil, let sq = square(at: v.startLocation, cell: cell), isOwn(sq),
                   legal.contains(where: { $0.from == sq }) {
                    dragFrom = sq
                    selected = sq
                }
                if dragFrom != nil { dragPoint = v.location }
            }
            .onEnded { v in
                let started = dragFrom
                dragFrom = nil; dragPoint = nil
                guard canMove, promotion == nil else { return }
                let start = square(at: v.startLocation, cell: cell), end = square(at: v.location, cell: cell)
                let moved = hypot(v.translation.width, v.translation.height) > cell * 0.35
                if let started {
                    if moved, let end, end != started { attempt(from: started, to: end) }
                    else if selected == started, !moved { /* keep selected for a second tap */ }
                } else if let sel = selected, let end {
                    if end == sel { selected = nil } else { attempt(from: sel, to: end) }
                } else if let start, isOwn(start), legal.contains(where: { $0.from == start }) {
                    selected = start
                }
            }
    }

    private func isOwn(_ sq: Int) -> Bool { let p = state.pos.b[sq]; return p != 0 && (p > 0) == whiteToMove }

    private func attempt(from: Int, to: Int) {
        let options = legal.filter { $0.from == from && $0.to == to }
        if options.isEmpty {
            if isOwn(to), legal.contains(where: { $0.from == to }) { selected = to } else { selected = nil; Feedback.shared.failure() }
            return
        }
        if options.count > 1 { promotion = (from, to); return }
        selected = nil
        if state.pos.b[to] != 0 { Feedback.shared.play(.capture) }
        session.submit(options[0])
    }

    // MARK: Piece identity (for animation)

    private func rebuild() {
        var id = 0
        items = state.pos.b.enumerated().compactMap { sq, p in p == 0 ? nil : { id += 1; return Item(id: id, piece: p, sq: sq) }() }
        nextID = 100
        selected = nil
    }

    private func sync() {
        selected = nil; promotion = nil
        let s = state
        guard s.lastFrom >= 0, let moverIndex = items.firstIndex(where: { $0.sq == s.lastFrom }) else { rebuild(); return }
        var next = items
        let mover = next[moverIndex]
        if let capture = next.firstIndex(where: { $0.sq == s.lastTo }) {
            next.remove(at: capture)
        } else if abs(mover.piece) == 1, s.lastFrom % 8 != s.lastTo % 8,
                  let ep = next.firstIndex(where: { $0.sq == s.lastFrom / 8 * 8 + s.lastTo % 8 }) {
            next.remove(at: ep)
        }
        guard let i = next.firstIndex(where: { $0.id == mover.id }) else { rebuild(); return }
        next[i].sq = s.lastTo
        if s.lastPromo != 0 { next[i].piece = Int8(s.lastPromo) * (mover.piece > 0 ? 1 : -1) }
        if abs(mover.piece) == 6, abs(s.lastTo - s.lastFrom) == 2 {
            let rookFrom = s.lastTo > s.lastFrom ? s.lastTo + 1 : s.lastTo - 2
            let rookTo = s.lastTo > s.lastFrom ? s.lastTo - 1 : s.lastTo + 1
            if let r = next.firstIndex(where: { $0.sq == rookFrom }) { next[r].sq = rookTo }
        }
        var board = [Int8](repeating: 0, count: 64)
        for it in next { board[it.sq] = it.piece }
        guard board == s.pos.b else { rebuild(); return }
        withAnimation(.snappy(duration: 0.22)) { items = next }
    }
}
