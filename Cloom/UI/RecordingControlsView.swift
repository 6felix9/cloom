import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text(timeText).font(.system(.largeTitle, design: .monospaced).bold())
            RecordingStatusView(coordinator: model.recordingCoordinator)

            HStack(spacing: 16) {
                Toggle("Camera", isOn: Binding(
                    get: { model.overlayState.isVisible }, set: { model.setCameraVisible($0) }
                )).toggleStyle(.switch)

                Toggle("Mute Mic", isOn: Binding(
                    get: { model.isMicrophoneMuted }, set: { model.setMicrophoneMuted($0) }
                )).toggleStyle(.switch)

                Picker("Size", selection: Binding(
                    get: { model.overlayState.size }, set: { model.setOverlaySize($0) }
                )) {
                    ForEach(OverlaySize.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 200)

                Picker("Shape", selection: Binding(
                    get: { model.overlayState.shape }, set: { model.setOverlayShape($0) }
                )) {
                    Text("Circle").tag(OverlayShape.circle)
                    Text("Rounded").tag(OverlayShape.roundedSquare)
                }.frame(width: 130)
            }

            Button(role: .destructive) {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.recordingCoordinator.phase != .recording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var timeText: String {
        let total = Int(model.elapsedSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private extension OverlaySize {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
