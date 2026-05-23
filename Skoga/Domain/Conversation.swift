import Foundation

enum ConversationMessage: Hashable, Identifiable {
    case msg(MsgPayload)
    case tool(ToolPayload)
    case write(WritePayload)
    case question(QuestionPayload)

    var id: UUID {
        switch self {
        case .msg(let m):      m.id
        case .tool(let t):     t.id
        case .write(let w):    w.id
        case .question(let q): q.id
        }
    }

    struct MsgPayload: Hashable, Identifiable {
        let id = UUID()
        let from: String           // "you" or agent.id
        let when: String
        let text: [String]
        let runtimeLabel: String?
        let initialOverride: String?
    }

    struct ToolPayload: Hashable, Identifiable {
        let id = UUID()
        let tool: String           // "read" | "shell" | …
        let path: String?
        let lines: String?
        let cmd: String?
        let result: String?
    }

    struct WritePayload: Hashable, Identifiable {
        let id = UUID()
        let path: String
        let adds: Int
        let rems: Int
    }

    struct QuestionPayload: Hashable, Identifiable {
        let id = UUID()
        let label: String
        let body: [String]
        let opts: [String]
    }
}
