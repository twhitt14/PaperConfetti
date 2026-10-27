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
                        ForEach(model.scenarios.indices, id: \.self) { index in Text(model.scenarios[index].id).tag(index) }
                    }.pickerStyle(.menu).accessibilityIdentifier("study-picker")
                    HStack {
                        Button("Replay") { model.replay(size: geometry.size) }.accessibilityIdentifier("study-replay")
                        Button("Next") {
                            model.visualIndex = (model.visualIndex + 1) % model.scenarios.count
                            model.replay(size: geometry.size)
                        }.accessibilityIdentifier("study-next")
                        Button("Tap test: \(model.taps)") { model.tap() }.accessibilityIdentifier("study-tap")
                    }.buttonStyle(.bordered)
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
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay { StudyRendererHost(view: model.renderer).allowsHitTesting(false).accessibilityHidden(true) }
            .task { await model.run(size: geometry.size) }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { phase in if phase != .active { model.stop() } }
        }
    }
}
