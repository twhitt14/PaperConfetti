import SwiftUI

struct StudyView: View {
    @StateObject private var model = StudyModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                Text("PaperConfetti • Renderer Study").font(.headline)
                Text(model.status).font(.caption.monospaced()).accessibilityIdentifier("study-status")
                if model.visual {
                    Picker("Experiment", selection: $model.visualIndex) {
                        ForEach(model.scenarios.indices, id: \.self) { index in Text(model.scenarios[index].displayName).tag(index) }
                    }.pickerStyle(.menu).accessibilityIdentifier("study-picker")
                        .onChange(of: model.visualIndex) { _ in
                            if !model.scenarios[model.visualIndex].availableCounts.contains(model.visualCount) { model.visualCount = 720 }
                            else { model.replay(size: geometry.size) }
                        }
                    Picker("Particles", selection: $model.visualCount) {
                        ForEach(model.scenarios[model.visualIndex].availableCounts, id: \.self) { count in
                            Text("\(count) pieces").tag(count)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("study-load")
                        .onChange(of: model.visualCount) { _ in model.replay(size: geometry.size) }
                    HStack {
                        Button("Replay") { model.replay(size: geometry.size) }.accessibilityIdentifier("study-replay")
                        Button("Shuffle") { model.shuffle(size: geometry.size) }.accessibilityIdentifier("study-shuffle")
                        Button("Next") {
                            model.visualIndex = (model.visualIndex + 1) % model.scenarios.count
                        }.accessibilityIdentifier("study-next")
                    }.buttonStyle(.bordered)
                    HStack {
                        Button("Stop animation") { model.pauseVisual() }
                            .accessibilityIdentifier("study-stop").disabled(!model.busy)
                        Button("Tap test: \(model.taps)") { model.tap() }.accessibilityIdentifier("study-tap")
                    }.buttonStyle(.bordered)
                    Text("Mix \(String(model.visualSeed)) • Replay keeps this mix")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("study-seed")
                    Text("Taps during flight: \(model.activeTaps)").font(.caption).accessibilityIdentifier("study-active-taps")
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<12) { row in
                                HStack(spacing: 6) {
                                    ForEach(0..<5) { col in
                                        Circle().fill(row == 6 ? .cyan : .gray.opacity(0.25))
                                            .overlay(Text(String(Array("WORDS")[col])).font(.title2.bold()))
                                            .frame(height: 54)
                                    }
                                }.id(row)
                            }
                            Text("End of scroll test").accessibilityIdentifier("study-scroll-end")
                        }
                    }.accessibilityIdentifier("study-scroll")
                        .onChange(of: model.scrollToBottom) { bottom in proxy.scrollTo(bottom ? 7 : 0, anchor: .top) }
                }
                if model.showKeyboard {
                    VStack(spacing: 5) {
                        ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(Array(row).map(String.init), id: \.self) { key in
                                    Text(key).font(.caption.bold()).frame(maxWidth: .infinity).frame(height: 30).background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }.transition(.move(edge: .bottom).combined(with: .opacity))
                } else { Text("Solved in 7 turns!").font(.title2.bold()).frame(height: 100) }
                if model.visual {
                    HStack {
                        ForEach(["Smooth", "Launch hitch", "Flight hitch"], id: \.self) { note in
                            Button(note) { model.note(note) }.buttonStyle(.bordered)
                        }
                    }.font(.caption)
                    Text(model.visualNote.isEmpty ? "Visual observations only • no performance recording" : "Saved: \(model.visualNote)").font(.caption)
                } else {
                    Text(model.complete ? "The Mac is saving the trace. Keep your phone connected." : "Automated trial — please leave this screen open").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.emissionProbe ? 0 : 1)
            .background(model.emissionProbe ? Color.black : Color(uiColor: .systemGroupedBackground))
            .overlay {
                if model.emissionProbe {
                    Color.clear.accessibilityElement().accessibilityLabel("Emission probe surface")
                        .accessibilityIdentifier("probe-surface").allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if model.emissionProbe {
                    Button("Fire probe") { model.replay(size: geometry.size) }
                        .buttonStyle(.plain).foregroundStyle(.white).padding(.top, 24)
                        .accessibilityIdentifier("probe-fire")
                }
            }
            .overlay { StudyRendererHost(view: model.renderer).allowsHitTesting(false).accessibilityHidden(true) }
            .task { await model.run(size: geometry.size) }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { phase in if phase != .active { model.stop() } }
        }
    }
}
