import Foundation

enum ConversationMessage: Hashable, Identifiable {
    case msg(MsgPayload)
    case tool(ToolPayload)
    case write(WritePayload)
    case question(QuestionPayload)

    var id: String {
        switch self {
        case .msg(let m):      m.id
        case .tool(let t):     t.id
        case .write(let w):    w.id
        case .question(let q): q.id
        }
    }

    /// Ids default to a fresh UUID so mock seeds and one-off constructions
    /// (Dispatch preview, tests) don't have to invent stable identifiers.
    /// The live path overrides the default with the daemon-supplied id
    /// (sourced from the Claude transcript's per-record uuid) so a 5s poll
    /// that re-fetches the same conversation produces the same identity
    /// for SwiftUI — scroll position, animations, and focus survive.
    struct MsgPayload: Hashable, Identifiable {
        let id: String
        let from: String           // "you" or agent.id
        let when: String
        let text: [String]
        let runtimeLabel: String?
        let initialOverride: String?

        init(
            id: String = UUID().uuidString,
            from: String,
            when: String,
            text: [String],
            runtimeLabel: String?,
            initialOverride: String?
        ) {
            self.id = id
            self.from = from
            self.when = when
            self.text = text
            self.runtimeLabel = runtimeLabel
            self.initialOverride = initialOverride
        }
    }

    struct ToolPayload: Hashable, Identifiable {
        let id: String
        let tool: String           // "read" | "shell" | …
        let path: String?
        let lines: String?
        let cmd: String?
        let result: String?

        init(
            id: String = UUID().uuidString,
            tool: String,
            path: String?,
            lines: String?,
            cmd: String?,
            result: String?
        ) {
            self.id = id
            self.tool = tool
            self.path = path
            self.lines = lines
            self.cmd = cmd
            self.result = result
        }
    }

    struct WritePayload: Hashable, Identifiable {
        let id: String
        let path: String
        let adds: Int
        let rems: Int

        init(
            id: String = UUID().uuidString,
            path: String,
            adds: Int,
            rems: Int
        ) {
            self.id = id
            self.path = path
            self.adds = adds
            self.rems = rems
        }
    }

    struct QuestionPayload: Hashable, Identifiable {
        let id: String
        let label: String
        let body: [String]
        let opts: [String]

        init(
            id: String = UUID().uuidString,
            label: String,
            body: [String],
            opts: [String]
        ) {
            self.id = id
            self.label = label
            self.body = body
            self.opts = opts
        }
    }
}
