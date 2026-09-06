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
            await model.refreshDevices()
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

            sourceSelector
            devicePicker(
                title: "Camera",
                icon: "video",
                devices: model.cameraDevices,
                selection: cameraBinding
            )
            devicePicker(
                title: "Microphone",
                icon: "mic",
                devices: model.microphoneDevices,
                selection: microphoneBinding
            )

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
                .disabled(!model.isReadyToRecord)
                .help("Select a screen or window and recording devices before recording")
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

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    model.selectedCaptureSource?.title ?? "Screen or window",
                    systemImage: "rectangle.dashed"
                )
                Spacer()
                Button("Select Screen or Window") {
                    Task { await model.selectCaptureSource() }
                }
            }

            if let error = model.captureSourceError {
                Label(
                    "Unable to select a capture source: \(error.localizedDescription)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func devicePicker(
        title: String,
        icon: String,
        devices: [CaptureDeviceOption],
        selection: Binding<String?>
    ) -> some View {
        Picker(selection: selection) {
            if devices.isEmpty {
                Text("No \(title.lowercased()) available").tag(Optional<String>.none)
            } else {
                ForEach(devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private var systemAudioBinding: Binding<Bool> {
        Binding(
            get: { model.settings.includeSystemAudio },
            set: { model.settings.includeSystemAudio = $0 }
        )
    }

    private var cameraBinding: Binding<String?> {
        Binding(
            get: { model.settings.cameraDeviceID },
            set: { id in
                if let id {
                    model.selectCamera(id: id)
                }
            }
        )
    }

    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { model.settings.microphoneDeviceID },
            set: { id in
                if let id {
                    model.selectMicrophone(id: id)
                }
            }
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
