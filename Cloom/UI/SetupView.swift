import SwiftUI

struct SetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                permissionSection

                if model.isReadyToConfigure {
                    recordingSection
                    overlaySection
                    footer
                } else {
                    permissionHint
                }
            }
            .padding(28)
        }
        .frame(minWidth: 620, minHeight: 660)
        .task {
            await model.refreshPermissions()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cloom")
                    .font(.largeTitle.bold())
                Text("Screen recording, with you in the frame.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Permissions", subtitle: "Cloom keeps every recording on your Mac.")

            ForEach(CapturePermission.allCases, id: \.self) { permission in
                PermissionRow(
                    permission: permission,
                    state: model.permissions[permission] ?? .notDetermined,
                    onRequest: {
                        Task { await model.request(permission) }
                    },
                    onOpenSettings: {
                        model.openSettings(for: permission)
                    }
                )
            }

            Button("Refresh permissions") {
                Task { await model.refreshPermissions() }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recording", subtitle: "Choose what Cloom should capture.")

            unavailableSelector(title: "Screen or window", icon: "rectangle.dashed")
            unavailableSelector(title: "Camera", icon: "video")
            unavailableSelector(title: "Microphone", icon: "mic")

            Toggle("Include Mac system audio", isOn: systemAudioBinding)
                .toggleStyle(.switch)
                .padding(.top, 4)
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Face overlay", subtitle: "These choices are saved automatically.")

            Picker("Shape", selection: shapeBinding) {
                Text("Circle").tag(OverlayShape.circle)
                Text("Rounded Square").tag(OverlayShape.roundedSquare)
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: sizeBinding) {
                Text("Small").tag(OverlaySize.small)
                Text("Medium").tag(OverlaySize.medium)
                Text("Large").tag(OverlaySize.large)
            }
            .pickerStyle(.segmented)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                RecordingStatusView(coordinator: model.recordingCoordinator)
                Spacer()
                Button {
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(true)
                .help("Choose a screen or window before recording")
            }
        }
    }

    private var permissionHint: some View {
        Label(
            "Allow all three permissions to configure a recording.",
            systemImage: "lock.shield"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func unavailableSelector(title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("Available in capture milestone")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private var systemAudioBinding: Binding<Bool> {
        Binding(
            get: { model.settings.includeSystemAudio },
            set: { model.settings.includeSystemAudio = $0 }
        )
    }

    private var shapeBinding: Binding<OverlayShape> {
        Binding(
            get: { model.settings.overlayShape },
            set: { model.settings.overlayShape = $0 }
        )
    }

    private var sizeBinding: Binding<OverlaySize> {
        Binding(
            get: { model.settings.overlaySize },
            set: { model.settings.overlaySize = $0 }
        )
    }
}
