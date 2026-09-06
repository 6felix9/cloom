import SwiftUI

struct RecordingControlVisibility: Equatable {
    let showsCameraToggle: Bool
    let showsOverlayControls: Bool
    let showsMicrophoneMute: Bool

    init(settings: RecordingSettings) {
        showsCameraToggle = settings.includeCamera
        showsOverlayControls = settings.includeCamera
        showsMicrophoneMute = settings.includeMicrophone
    }
}

struct RecordingControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text(timeText).font(.system(.largeTitle, design: .monospaced).bold())
            RecordingStatusView(coordinator: model.recordingCoordinator)

            controls

            Button(role: .destructive) {
                Task { await model.stopRecording() }
            } label: {
                if model.recordingCoordinator.phase == .stopping {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Stopping…")
                    }
                    .frame(minWidth: 150)
                } else {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .frame(minWidth: 150)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.recordingCoordinator.phase != .recording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var controls: some View {
        let visibility = RecordingControlVisibility(settings: model.activeRecordingSettings ?? model.settings)
        VStack(alignment: .leading, spacing: 12) {
            if visibility.showsCameraToggle {
                controlRow("Camera") {
                    Toggle("Show camera", isOn: Binding(
                        get: { model.overlayState.isVisible }, set: { model.setCameraVisible($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            if visibility.showsOverlayControls {
                controlRow("Camera size") {
                    Picker("Camera size", selection: Binding(
                        get: { model.overlayState.size }, set: { model.setOverlaySize($0) }
                    )) {
                        ForEach(OverlaySize.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                controlRow("Camera shape") {
                    Picker("Camera shape", selection: Binding(
                        get: { model.overlayState.shape }, set: { model.setOverlayShape($0) }
                    )) {
                        Text("Circle").tag(OverlayShape.circle)
                        Text("Rounded").tag(OverlayShape.roundedSquare)
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            if visibility.showsMicrophoneMute {
                controlRow("Mute Microphone") {
                    Toggle("Mute microphone", isOn: Binding(
                        get: { model.isMicrophoneMuted }, set: { model.setMicrophoneMuted($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 380)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func controlRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 20)
            control()
        }
        .frame(minHeight: 30)
    }

    private var timeText: String {
        let total = Int(model.elapsedSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private extension OverlaySize {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
