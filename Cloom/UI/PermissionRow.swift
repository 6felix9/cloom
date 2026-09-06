import SwiftUI

struct PermissionRow: View {
    let permission: CapturePermission
    let state: PermissionState
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .fontWeight(.semibold)
                Text(permission.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            action
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .authorized:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .notDetermined:
            Button("Grant Access", action: onRequest)
                .buttonStyle(.bordered)
        case .denied, .restricted:
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.bordered)
        }
    }
}

private extension CapturePermission {
    var title: String {
        switch self {
        case .screen: "Screen Recording"
        case .camera: "Camera"
        case .microphone: "Microphone"
        }
    }

    var explanation: String {
        switch self {
        case .screen: "Capture the display or window you choose."
        case .camera: "Place your face over the recording."
        case .microphone: "Record your narration."
        }
    }

    var systemImage: String {
        switch self {
        case .screen: "rectangle.on.rectangle"
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        }
    }
}
