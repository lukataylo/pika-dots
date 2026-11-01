import SwiftUI
import UserNotifications

enum NotificationCopy {
    static func short(_ message: String) -> String {
        let all = message.split(whereSeparator: { $0.isWhitespace })
        let words = all.prefix(14).joined(separator: " ")
        guard words.count > 100 else { return all.count > 14 ? words + "…" : words }
        return String(words.prefix(97)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

@MainActor
final class NudgePresenter {
    private let center = UNUserNotificationCenter.current()
    private let delegate = BannerDelegate()
    private var panel: CompanionPanel?
    private var task: Task<Void, Never>?
    init() { center.delegate = delegate }
    func dismiss() {
        task?.cancel(); panel?.close(); panel = nil
        center.removePendingNotificationRequests(withIdentifiers: ["pika.current"])
        center.removeDeliveredNotifications(withIdentifiers: ["pika.current"])
    }
    func show(_ message: String, agent: AgentDefinition) {
        dismiss()
        let text = NotificationCopy.short(message)
        task = Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            var allowed = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && settings.alertSetting == .enabled
            if settings.authorizationStatus == .notDetermined { allowed = (try? await center.requestAuthorization(options: [.alert])) ?? false }
            guard !Task.isCancelled else { return }
            if allowed {
                let content = UNMutableNotificationContent()
                content.title = agent.name; content.body = text
                do { try await center.add(UNNotificationRequest(identifier: "pika.current", content: content, trigger: nil)) }
                catch { fallback(text, agent: agent) }
            } else { fallback(text, agent: agent) }
        }
    }
    private func fallback(_ text: String, agent: AgentDefinition) {
        // A short transient banner if system notifications are disabled.
        let panel = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 290, height: 68), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 10) {
                Circle().fill(Color(nsColor: agent.color)).frame(width: 9, height: 9)
                Text(text).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { [weak self] in self?.dismiss() } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain)
            }.padding(12).frame(width: 290, height: 68).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 310, y: screen.visibleFrame.maxY - 88)) }
        self.panel = panel; panel.orderFrontRegardless()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)); try Task.checkCancellation() } catch { return }
            self?.panel?.orderOut(nil)
        }
    }
}
