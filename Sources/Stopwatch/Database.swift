import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the libsqlite3 that ships with macOS. Records are the only thing
/// this app owns, so the schema is two tables and every write is committed at once.
final class Database {
    let path: String
    private var handle: OpaquePointer?

    enum Error: LocalizedError {
        case openFailed(String)
        case prepareFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let detail): return "无法打开数据库：\(detail)"
            case .prepareFailed(let sql, let detail): return "SQL 准备失败（\(sql)）：\(detail)"
            }
        }
    }

    init(path: String) throws {
        self.path = path
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw Error.openFailed(message)
        }
        try execute("""
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=FULL;
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY NOT NULL,
          started_at REAL NOT NULL,
          ended_at REAL NOT NULL,
          seconds INTEGER NOT NULL,
          name_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS active_seat (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          seat_start REAL NOT NULL,
          segment_start REAL NOT NULL,
          banked_seconds INTEGER NOT NULL,
          is_running INTEGER NOT NULL,
          name_count INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS sessions_started_at ON sessions(started_at);
        """)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw Error.prepareFailed(sql.prefix(60) + "", detail)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error.prepareFailed(sql, String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    /// Runs a statement with positional bindings and discards any rows.
    private func run(_ sql: String, _ bindings: [Any?]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw Error.prepareFailed(sql, String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func bind(_ values: [Any?], in statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case let date as Date: sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
            case let int as Int: sqlite3_bind_int64(statement, index, Int64(int))
            case let bool as Bool: sqlite3_bind_int(statement, index, bool ? 1 : 0)
            case nil: sqlite3_bind_null(statement, index)
            default: sqlite3_bind_null(statement, index)
            }
        }
    }

    // MARK: sessions

    func allSessions() throws -> [Session] {
        let statement = try prepare("""
        SELECT id, started_at, ended_at, seconds, name_count
        FROM sessions ORDER BY started_at ASC
        """)
        defer { sqlite3_finalize(statement) }
        var result: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: rawID)) else { continue }
            result.append(Session(id: id,
                                  start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                                  end: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                                  seconds: Int(sqlite3_column_int64(statement, 3)),
                                  count: Int(sqlite3_column_int64(statement, 4))))
        }
        return result
    }

    func replaceSessions(_ sessions: [Session]) throws {
        try run("DELETE FROM sessions", [])
        for session in sessions {
            try insert(session)
        }
    }

    func insert(_ session: Session) throws {
        try run("INSERT OR REPLACE INTO sessions VALUES (?, ?, ?, ?, ?)",
                [session.id.uuidString, session.start, session.end, session.seconds, session.count])
    }

    func deleteSession(id: UUID) throws {
        try run("DELETE FROM sessions WHERE id = ?", [id.uuidString])
    }

    func deleteSessionsStarted(onOrAfter from: Date, before: Date) throws {
        try run("DELETE FROM sessions WHERE started_at >= ? AND started_at < ?", [from, before])
    }

    // MARK: in-progress seat

    func activeSeat() throws -> ActiveState? {
        let statement = try prepare("""
        SELECT seat_start, segment_start, banked_seconds, is_running, name_count
        FROM active_seat WHERE id = 1
        """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return ActiveState(seatStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                           segmentStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                           bankedSeconds: Int(sqlite3_column_int64(statement, 2)),
                           isRunning: sqlite3_column_int(statement, 3) != 0,
                           count: Int(sqlite3_column_int64(statement, 4)))
    }

    func setActive(_ state: ActiveState?) throws {
        try run("DELETE FROM active_seat", [])
        guard let state else { return }
        try run("INSERT INTO active_seat VALUES (1, ?, ?, ?, ?, ?)",
                [state.seatStart, state.segmentStart, state.bankedSeconds, state.isRunning, state.count])
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}
