import Foundation

/// The CLI a seat belongs to, with the facts machine-config's `seat` script keys on.
enum SeatTool: String, Sendable, CaseIterable {
    case claude, codex

    var displayName: String { self == .claude ? "Claude" : "Codex" }
    /// `~/.claude-<name>` / `~/.codex-<name>`.
    var folderPrefix: String { ".\(rawValue)-" }
    /// The variable that points the CLI at the seat's folder, set for the launched process only.
    var homeVariable: String { self == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME" }
    var loginArguments: [String] { self == .claude ? ["auth", "login"] : ["login"] }
}

/// The file operations a seat needs, injectable so tests never touch the real home folder.
protocol SeatFileSystem: Sendable {
    func entries(inDirectory path: String) throws -> [String]
    func exists(_ path: String) -> Bool
    /// A new folder readable by its owner only (mode 700), failing when it already exists.
    func createPrivateDirectory(_ path: String) throws
    func createEmptyFile(_ path: String) throws
}

struct LocalSeatFileSystem: SeatFileSystem {
    func entries(inDirectory path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createPrivateDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        // `seat add` chmods after mkdir; do the same so the mode never depends on the umask.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    func createEmptyFile(_ path: String) throws {
        guard FileManager.default.createFile(atPath: path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
    }
}

enum SeatError: Error, LocalizedError, Equatable {
    case badName(String)
    case exists(String)

    var errorDescription: String? {
        switch self {
        case .badName(let name): "“\(name)” isn't a valid seat name."
        case .exists(let folder): "\(folder) already exists."
        }
    }
}

/// Seat folders made exactly like machine-config's `seat add` (shared-scripts/seat): `~/.claude-<name>`
/// or `~/.codex-<name>`, mode 700, with an empty `.seat` marker so `seat list` and `seat login` know it.
struct AccountSeats: Sendable {
    let home: String
    var files: SeatFileSystem = LocalSeatFileSystem()

    /// `seat`'s own rule: a-z, 0-9 and '-', starting and ending with a letter or digit.
    static func isValidName(_ name: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard let first = name.first, let last = name.last else { return false }
        return name.allSatisfy(allowed.contains) && first != "-" && last != "-"
    }

    func folder(for tool: SeatTool, name: String) -> String {
        home + "/" + tool.folderPrefix + name
    }

    /// The next `seatN`: one past the highest N that any `~/.claude-seatN` or `~/.codex-seatN` uses, so a
    /// name is never shared across the two tools. A folder counts with or without its marker, because
    /// `seat add` refuses a folder that already exists.
    func nextFreeName() throws -> String {
        let used = try files.entries(inDirectory: home).compactMap { entry -> Int? in
            for tool in SeatTool.allCases {
                let prefix = tool.folderPrefix + "seat"
                guard entry.hasPrefix(prefix) else { continue }
                let digits = entry.dropFirst(prefix.count)
                guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigitCharacter) else { return nil }
                return Int(digits)
            }
            return nil
        }
        return "seat\((used.max() ?? 0) + 1)"
    }

    /// `seat add <name> <tool>`: refuses an existing folder, then makes the folder and its marker.
    func create(_ tool: SeatTool, name: String) throws -> String {
        guard Self.isValidName(name) else { throw SeatError.badName(name) }
        let directory = folder(for: tool, name: name)
        guard !files.exists(directory) else { throw SeatError.exists(directory) }
        try files.createPrivateDirectory(directory)
        try files.createEmptyFile(directory + "/.seat")
        return directory
    }

    /// The Claude seat a signed-out card was last signed in at, when that place is a `~/.claude-<name>`
    /// folder; `nil` for the default home, Claude Desktop, or anywhere else (those sign in to a new seat,
    /// so the login never replaces whatever account holds that place now).
    func claudeSeat(forSignedOutLocation location: String) -> String? {
        let path = location.hasPrefix("~/") ? home + location.dropFirst(1) : location
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().path == URL(fileURLWithPath: home).standardizedFileURL.path else {
            return nil
        }
        let folderName = url.lastPathComponent
        let prefix = SeatTool.claude.folderPrefix
        guard folderName.hasPrefix(prefix), !ClaudeHomeScanner.excludedFolders.contains(folderName) else { return nil }
        let name = String(folderName.dropFirst(prefix.count))
        return Self.isValidName(name) ? name : nil
    }

    /// A folder as the page shows it: the home folder shortened to `~`.
    func shortened(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}
