import SwiftUI
import UserNotifications

@MainActor
final class PermissionState: ObservableObject {
    @Published var notificationStatus = "Checking…"
    func refreshNotifications() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationStatus = status == .authorized || status == .provisional ? "Allowed" : status == .denied ? "Off — enable in macOS settings" : "Not requested yet"
        }
    }
    func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            refreshNotifications()
        }
    }
    @Published var screenAllowed = ScreenAccess.available
    @Published var checking = false
    @Published var accessMessage = ""
    func refresh() {
        guard !checking else { return }
        checking = true; refreshNotifications()
        Task {
            screenAllowed = await ScreenAccess.probe()
            accessMessage = screenAllowed ? "Verified with ScreenCaptureKit" : "If already enabled in macOS, restart Pika Dots to refresh access."
            checking = false
            if screenAllowed { NotificationCenter.default.post(name: .pikaScreenAccessRecovered, object: nil) }
        }
    }
    func request() {
        if CGRequestScreenCaptureAccess() { refresh() }
        else { accessMessage = "Enable Pika Dots in macOS settings, then restart."; openSettings() }
    }
    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func restart() {
        do { try AppRelauncher.restart() }
        catch { accessMessage = "Could not restart. Quit and reopen Pika Dots." }
    }
}

struct PermissionsView: View {
    @StateObject private var permissions = PermissionState()
    let manage: () -> Void
    let showShelf: () -> Void
    let testNotification: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Pika Dots settings", systemImage: "gearshape").font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                Button("Show shelf", action: showShelf).font(.caption)
            }
            HStack {
                Image(systemName: permissions.screenAllowed ? "checkmark.circle.fill" : "rectangle.dashed.badge.record").foregroundStyle(permissions.screenAllowed ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Recording").font(.headline)
                    Text(permissions.screenAllowed ? "Allowed on this Mac" : "Needed to understand the attached window").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(permissions.checking ? "Checking…" : "Check again") { permissions.refresh() }.disabled(permissions.checking)
            }
            HStack {
                Button("Request access") { permissions.request() }
                Button("Open macOS settings") { permissions.openSettings() }
            }
            Text(permissions.accessMessage.isEmpty ? "After a denial, enable access in macOS settings and restart. Your attachments will be restored." : permissions.accessMessage).font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Notifications", systemImage: "bell").font(.headline)
                    Text(permissions.notificationStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Test", action: testNotification)
                Button("Enable") { permissions.requestNotifications() }
                Button("Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
            }
            Label("Keyboard activity only — no typed text is recorded.", systemImage: "keyboard").font(.caption)
            Text("Only the attached window is sent to OpenAI when you press Go or enable supervision. No Accessibility or Input Monitoring permission is required.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Companions & API key…", action: manage); Spacer(); Button("Restart Pika Dots") { permissions.restart() } }
        }.padding(24).frame(width: 440)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
}

extension Notification.Name { static let pikaScreenAccessRecovered = Notification.Name("pikaScreenAccessRecovered") }
