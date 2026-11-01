import Foundation

struct AttachmentSnapshot: Codable {
    let agentID: String
    let windowID: UInt32
    let ownerPID: Int32
    let prompt: String
    let running: Bool
    let startedAt: Date?
    let snoozedUntil: Date
}
