import SwiftUI

struct DataPrivacyView: View {
    @ObservedObject private var stopWatchBLE: StopWatchBLEService
    @ObservedObject private var permissions: DataAccessPermissionService
    @ObservedObject private var audioPipeline: StopWatchAudioPipelineService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsUnbindConfirmation = false

    private let bg = Color(red: 0.957, green: 0.957, blue: 0.937)

    init(
        stopWatchBLE: StopWatchBLEService,
        permissions: DataAccessPermissionService,
        audioPipeline: StopWatchAudioPipelineService
    ) {
        self.stopWatchBLE = stopWatchBLE
        self.permissions = permissions
        self.audioPipeline = audioPipeline
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section(C.t("dataPrivacy.access.title")) {
                    permissionRow(
                        title: C.t("dataPrivacy.access.health"),
                        note: C.t("dataPrivacy.access.healthNote"),
                        status: permissions.healthStatus,
                        action: { Task { await permissions.requestHealthAccess() } }
                    )
                    divider
                    permissionRow(
                        title: C.t("dataPrivacy.access.microphone"),
                        note: C.t("dataPrivacy.access.microphoneNote"),
                        status: permissions.microphoneStatus,
                        action: { Task { await permissions.requestMicrophoneAccess() } }
                    )
                    divider
                    bluetoothPermissionRow
                }

                section(C.t("dataPrivacy.devices.title")) {
                    stopWatchDeviceCard
                }

                section(C.t("dataPrivacy.privacy.title")) {
                    Text(C.t("dataPrivacy.privacy.body"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppPalette.muted)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle(C.t("dataPrivacy.title"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            C.t("dataPrivacy.stopWatch.unbindConfirmTitle"),
            isPresented: $showsUnbindConfirmation,
            titleVisibility: .visible
        ) {
            Button(C.t("dataPrivacy.stopWatch.unbindConfirmAction"), role: .destructive) {
                stopWatchBLE.unbind()
            }
            Button(C.t("dataPrivacy.common.cancel"), role: .cancel) {}
        } message: {
            Text(C.t("dataPrivacy.stopWatch.unbindConfirmBody"))
        }
        .onAppear {
            permissions.refreshStatuses()
            stopWatchBLE.activateIfBound()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            permissions.refreshStatuses()
            stopWatchBLE.activateIfBound()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(C.t("dataPrivacy.headerTitle"))
                .font(.system(size: 28, weight: .heavy, design: .serif))
                .foregroundStyle(AppPalette.ink)
            Text(C.t("dataPrivacy.headerBody"))
                .font(.system(size: 14))
                .foregroundStyle(AppPalette.muted)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            VStack(spacing: 0) {
                content()
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var divider: some View {
        Divider().padding(.leading, 16)
    }

    private func permissionRow(
        title: String,
        note: String,
        status: DataAccessPermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            switch status {
            case .notRequested:
                action()
            case .denied:
                permissions.openSystemSettings()
            case .allowed, .restricted, .unavailable:
                break
            }
        } label: {
            accessRowContent(
                title: title,
                note: note,
                statusText: C.t(status.copyKey),
                statusColor: permissionColor(status),
                accessory: accessoryText(for: status)
            )
        }
        .buttonStyle(.plain)
        .disabled(status == .allowed || status == .restricted || status == .unavailable)
    }

    private var bluetoothPermissionRow: some View {
        accessRowContent(
            title: C.t("dataPrivacy.access.bluetooth"),
            note: C.t("dataPrivacy.access.bluetoothNote"),
            statusText: C.t(stopWatchBLE.bluetoothSystemStatus.copyKey),
            statusColor: bluetoothColor(stopWatchBLE.bluetoothSystemStatus),
            accessory: stopWatchBLE.bluetoothSystemStatus == .notAuthorized ? C.t("dataPrivacy.common.openSettings") : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if stopWatchBLE.bluetoothSystemStatus == .notAuthorized {
                permissions.openSystemSettings()
            }
        }
    }

    private func accessRowContent(
        title: String,
        note: String,
        statusText: String,
        statusColor: Color,
        accessory: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text(statusText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                if let accessory {
                    Text(accessory)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .padding(16)
    }

    private var stopWatchDeviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stopWatchBLE.discoveredDeviceName ?? C.t("dataPrivacy.stopWatch.name"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(C.t(stopWatchBLE.connectionStatus.copyKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(connectionColor(stopWatchBLE.connectionStatus))
                }
                Spacer()
                Text(C.t(stopWatchBLE.bluetoothSystemStatus.copyKey))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(bluetoothColor(stopWatchBLE.bluetoothSystemStatus))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(AppPalette.background)
                    .clipShape(Capsule())
            }

            if let date = stopWatchBLE.lastConnectionDate {
                labeledValue(C.t("dataPrivacy.stopWatch.lastConnected"), value: date.formatted(date: .abbreviated, time: .shortened))
            } else if stopWatchBLE.boundPeripheralIdentifier != nil {
                labeledValue(C.t("dataPrivacy.stopWatch.lastConnected"), value: C.t("dataPrivacy.stopWatch.noLastConnection"))
            }

            if let status = audioPipeline.statusMessage {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.green)
            }

            if let error = stopWatchBLE.lastErrorMessage ?? audioPipeline.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            actionButtons
        }
        .padding(16)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if stopWatchBLE.boundPeripheralIdentifier == nil {
                Button {
                    stopWatchBLE.connect()
                } label: {
                    Text(C.t("dataPrivacy.stopWatch.connectAction"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(AppPalette.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(stopWatchBLE.connectionStatus == .scanning || stopWatchBLE.connectionStatus == .connecting)
            } else {
                Button {
                    stopWatchBLE.connect()
                } label: {
                    Text(C.t("dataPrivacy.stopWatch.reconnectAction"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(AppPalette.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    showsUnbindConfirmation = true
                } label: {
                    Text(C.t("dataPrivacy.stopWatch.unbindAction"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(AppPalette.background)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.faint)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
        }
    }

    private func accessoryText(for status: DataAccessPermissionStatus) -> String? {
        switch status {
        case .notRequested:
            C.t("dataPrivacy.common.request")
        case .denied:
            C.t("dataPrivacy.common.openSettings")
        case .allowed, .restricted, .unavailable:
            nil
        }
    }

    private func permissionColor(_ status: DataAccessPermissionStatus) -> Color {
        switch status {
        case .allowed:
            AppPalette.green
        case .denied, .restricted:
            .red
        case .notRequested, .unavailable:
            AppPalette.faint
        }
    }

    private func bluetoothColor(_ status: StopWatchBluetoothSystemStatus) -> Color {
        switch status {
        case .authorized:
            AppPalette.green
        case .notAuthorized, .poweredOff, .unsupported:
            AppPalette.faint
        }
    }

    private func connectionColor(_ status: StopWatchConnectionStatus) -> Color {
        switch status {
        case .connected, .receiving:
            AppPalette.green
        case .failed:
            .red
        case .unbound, .scanning, .connecting, .disconnected:
            AppPalette.muted
        }
    }
}
