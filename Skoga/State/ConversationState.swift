import Foundation

/// Conversation slice — everything about the open 1:1 surface. Kept
/// separate from `RosterState` so the 5s conversation poll doesn't
/// invalidate roster/modal/sidebar views, and from `ModalState` so the
/// composer's `pendingReply` keystrokes don't redraw modals.
@MainActor
@Observable
final class ConversationState {
    /// Coordinator-set via `openConversation` / `backToRoster`. Reading it
    /// is how `MainWindow` resolves the open agent and how the polling
    /// loop knows whether to refetch the transcript.
    private(set) var openAgentId: String? = nil

    /// Daemon-driven. Populated by the coordinator's `loadConversation`
    /// from `client.conversation`; the in-flight `AskUserQuestion` row
    /// is dropped from here via `dropQuestion(toolUseId:)` so the picker
    /// disappears the moment the user answers.
    private(set) var conversation: [ConversationMessage] = []
    private(set) var timeline: [TimelineEntry] = []

    /// UI-driven (the composer's `TextEditor` binds straight to this).
    /// Cleared on conversation open + send; written nowhere else.
    var pendingReply: String = ""

    /// Set `openAgentId` and, when clearing, drop the transcript +
    /// timeline at the same time — otherwise a fast back/forward would
    /// briefly render the previous agent's messages under the new
    /// agent's chrome.
    func setOpenAgent(_ id: String?) {
        openAgentId = id
        if id == nil {
            conversation = []
            timeline = []
        }
    }

    /// Diff-guarded apply for the conversation/timeline fetch — same
    /// rationale as `RosterState.apply(agents:)`: a polled identity-equal
    /// array would still fire `@Observable`'s tracking notification.
    func apply(messages: [ConversationMessage]) {
        if conversation != messages { conversation = messages }
    }

    func apply(timeline next: [TimelineEntry]) {
        if timeline != next { timeline = next }
    }

    /// Clear conversation/timeline when a load fails so a transient
    /// network drop doesn't leave the previous session's messages on
    /// screen attached to the wrong agent. No-op when already empty so
    /// the empty-state doesn't re-fire `@Observable`.
    func clearTranscript() {
        if !conversation.isEmpty { conversation = [] }
    }

    func clearTimeline() {
        if !timeline.isEmpty { timeline = [] }
    }

    /// Optimistic drop of the pending-question row after the user picks
    /// an option — the daemon will clear it on its next poll, but the
    /// UI shouldn't show a stale picker for the 5s in between.
    func dropQuestion(toolUseId: String) {
        conversation.removeAll {
            if case .question(let q) = $0, q.toolUseId == toolUseId { return true }
            return false
        }
    }
}
