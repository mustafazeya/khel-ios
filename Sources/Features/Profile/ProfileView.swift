import SwiftUI

struct ProfileView: View {
    @Environment(Profile.self) private var profile
    @Environment(AppSettings.self) private var settings
    @Environment(StatsStore.self) private var stats
    @State private var showEditor = false
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var profile = profile
        @Bindable var settings = settings
        List {
            Section {
                HStack(spacing: 16) {
                    AvatarView(spec: profile.avatar, size: 84, ring: Theme.accent, square: true)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Your name", text: $profile.name).font(.khHeadline).textInputAutocapitalization(.words)
                            .onChange(of: profile.name) { _, v in if v.count > 24 { profile.name = String(v.prefix(24)) } }
                        Button("Edit avatar") { showEditor = true }.buttonStyle(.bordered).tint(Theme.accent)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Game settings") {
                Toggle("Sound effects", isOn: $settings.sound)
                Toggle("Haptics", isOn: $settings.haptics)
                Picker("Computer level", selection: $settings.aiLevel) { ForEach(AILevel.allCases) { Text($0.title).tag($0) } }
            }

            Section("Your record") {
                ForEach(GameCatalog.all.filter { stats.record($0.id).played > 0 }) { e in
                    let r = stats.record(e.id)
                    HStack {
                        Image(systemName: e.info.symbol).frame(width: 28).foregroundStyle(Theme.color(e.info.palette.last ?? 0))
                        Text(e.info.title)
                        Spacer()
                        Text(e.info.mode == .solo ? "Best \(r.bestScore)" : "\(r.wins)W \(r.losses)L \(r.draws)D")
                            .font(.footnote.monospacedDigit()).foregroundStyle(Theme.text2)
                    }
                }
                if stats.totalPlayed == 0 { Text("Play a game to start your record.").foregroundStyle(Theme.text2) }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Games", value: "\(GameCatalog.all.count)")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Me")
        .sheet(isPresented: $showEditor) { AvatarEditor(spec: $profile.avatar) }
    }
}

struct AvatarEditor: View {
    @Binding var spec: AvatarSpec
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    AvatarView(spec: spec, size: 190, ring: Theme.accent, square: true).padding(.top, 8)
                    HStack {
                        Button { spec = .random(seed: UInt64.random(in: .min ... .max)) } label: { Label("Surprise me", systemImage: "dice.fill") }
                            .buttonStyle(.borderedProminent)
                        if let shareURL { ShareLink(item: shareURL) { Label("Export SVG", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) }
                    }

                    choices("Skin", AvatarSpec.skinTones.count, $spec.skin) { Circle().fill(Color(hexString: AvatarSpec.skinTones[$0])) }
                    names("Face", AvatarSpec.faceNames, $spec.face)
                    names("Hair", AvatarSpec.hairNames, $spec.hair)
                    choices("Hair colour", AvatarSpec.hairColors.count, $spec.hairColor) { Circle().fill(Color(hexString: AvatarSpec.hairColors[$0])) }
                    names("Eyes", AvatarSpec.eyeNames, $spec.eyes)
                    names("Mouth", AvatarSpec.mouthNames, $spec.mouth)
                    names("Facial hair", AvatarSpec.facialHairNames, $spec.facialHair)
                    names("Headwear", AvatarSpec.headwearNames, $spec.headwear)
                    names("Glasses", AvatarSpec.glassesNames, $spec.glasses)
                    names("Clothes", AvatarSpec.clothingNames, $spec.clothing)
                    choices("Clothes colour", AvatarSpec.clothingColors.count, $spec.clothingColor) { Circle().fill(Color(hexString: AvatarSpec.clothingColors[$0])) }
                    choices("Background", AvatarSpec.backgroundPairs.count, $spec.backgroundColor) {
                        Circle().fill(LinearGradient(colors: [Color(hexString: AvatarSpec.backgroundPairs[$0].0), Color(hexString: AvatarSpec.backgroundPairs[$0].1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    names("Pattern", ["Gradient", "Glow", "Stripes", "Dots"], $spec.background)

                    VStack(alignment: .leading, spacing: 8) {
                        Kicker(text: "Extras")
                        Toggle("Bindi", isOn: extra(.bindi))
                        Toggle("Earrings", isOn: extra(.earrings))
                        Toggle("Blush", isOn: extra(.blush))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Avatar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: spec, initial: true) { _, s in shareURL = Self.writeSVG(s) }
        }
        .preferredColorScheme(.dark)
    }

    private func extra(_ e: AvatarSpec.Extra) -> Binding<Bool> {
        Binding(get: { spec.has(e) }, set: { spec.set(e, $0) })
    }

    private func names(_ title: String, _ names: [String], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: title)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(names.indices, id: \.self) { i in
                        Button { value.wrappedValue = i } label: {
                            Text(names[i]).font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(value.wrappedValue == i ? Theme.accent : Theme.surface2, in: Capsule())
                                .foregroundStyle(value.wrappedValue == i ? .black : .white)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choices<S: View>(_ title: String, _ count: Int, _ value: Binding<Int>, @ViewBuilder swatch: @escaping (Int) -> S) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: title)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(0 ..< count, id: \.self) { i in
                        Button { value.wrappedValue = i } label: {
                            swatch(i).frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(.white, lineWidth: value.wrappedValue == i ? 3 : 0).padding(-4))
                        }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func writeSVG(_ spec: AvatarSpec) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("khel-avatar.svg")
        do { try AvatarSVG.document(spec).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

extension Color {
    init(hexString: String) {
        let v = UInt32(hexString.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}
