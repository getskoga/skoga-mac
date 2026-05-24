import Foundation

/// 100 hand-picked Norse names used as friendly aliases for sessions on the
/// Roster. The skogad protocol identifies sessions by 8-char hex id and has
/// no name field, so we deterministically map the id → a name from this list
/// (FNV-1a hash mod count). Same id always renders as the same name — across
/// app launches and across devices.
///
/// Disable via:
///   defaults write dev.getskoga.Skoga skoga.useNordicNames -bool false
///
/// Keep this list in sync with `crates/skoga-cli/src/commands/start.rs`'s
/// `NORSE_NAMES` (used by the daemon when auto-generating a task label).
enum NordicNames {

    static let all: [String] = [
        // Aesir & Vanir
        "Odin", "Thor", "Loki", "Freya", "Freyr", "Frigg", "Tyr", "Heimdall",
        "Bragi", "Idun", "Njord", "Skadi", "Sif", "Vidar", "Vali", "Forseti",
        "Baldur", "Mimir", "Magni", "Modi", "Sigyn", "Nanna", "Fulla", "Gefjon",
        "Eir", "Saga", "Ull", "Gerd", "Embla", "Lofn", "Snotra",

        // Mythological figures & creatures
        "Fenrir", "Sleipnir", "Ratatosk", "Nidhogg", "Surtur", "Ymir", "Bestla",
        "Buri", "Vili", "Hugin", "Munin", "Geri", "Freki", "Andvari", "Brokk",
        "Eitri", "Dvalin", "Alvis", "Fafnir", "Regin",

        // Heroes from the Volsung & Icelandic sagas
        "Sigurd", "Brynhild", "Gunnar", "Hogni", "Gudrun", "Atli", "Helgi",
        "Sigmund", "Signy", "Starkad", "Volund", "Hervor", "Egil", "Gisli",
        "Grettir",

        // Viking-era historical figures
        "Ragnar", "Bjorn", "Ivar", "Ubbe", "Halfdan", "Floki", "Lagertha",
        "Aslaug", "Erik", "Leif", "Harald", "Hakon", "Olaf", "Knut", "Gorm",
        "Magnus", "Ingvar",

        // Common Scandinavian / Old Norse personal names
        "Astrid", "Ingrid", "Sigrid", "Helga", "Solveig", "Tora", "Runa",
        "Frida", "Inga", "Tove", "Signe", "Thyra", "Freydis", "Arne", "Finn",
        "Rolf", "Ulf",
    ]

    /// Toggle key in `UserDefaults`. Default is `true` when absent.
    static let defaultsKey = "skoga.useNordicNames"

    /// Whether to swap session hex prefixes for Norse aliases. Read from
    /// `UserDefaults` so that both `@AppStorage` (SwiftUI Toggle) and static
    /// callers (e.g. `Agent.from(rpc:)`) agree on the same value.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// FNV-1a 32-bit hash → index into `all`. Deterministic and stable;
    /// the same session id renders as the same name forever.
    static func name(forSessionId id: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return all[Int(hash % UInt32(all.count))]
    }

    /// What the Roster (and any other "short blurb" site) should render as
    /// the session's display name. Falls back to the hex prefix when the
    /// user has opted out — that's the daemon's authoritative identifier
    /// and remains useful for support / log lookup.
    static func displayName(forSessionId id: String) -> String {
        enabled ? name(forSessionId: id) : String(id.prefix(6))
    }
}
