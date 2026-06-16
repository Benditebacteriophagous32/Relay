import Foundation
import SQLite3

// Local, durable message store backed by SQLite with a full-text (FTS5) index.
//
// Why this exists: the JSON cache rewrote the entire history on every save and
// couldn't be searched. SQLite gives us (1) incremental, crash-safe writes
// (WAL), (2) the never-delete guarantee on a real database, and (3) instant
// global full-text search across all history.
//
// Messages are the source of truth here; the FTS index is kept in sync by
// triggers, so callers only ever touch the `messages` table.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class MessageStore {
    private var db: OpaquePointer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("relay.db").path

        if sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                           nil) != SQLITE_OK {
            NSLog("Relay: failed to open SQLite at \(path)")
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        createSchema()
    }

    deinit { if db != nil { sqlite3_close_v2(db) } }

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS messages(
            id            TEXT PRIMARY KEY,
            thread        TEXT NOT NULL,
            sender        TEXT,
            text          TEXT,
            ts            REAL,
            system        INTEGER DEFAULT 0,
            kind          TEXT,
            mediaPath     TEXT,
            mediaURL      TEXT,
            replyToId     TEXT,
            replyToText   TEXT,
            replyToSender TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_msg_thread_ts ON messages(thread, ts);

        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts
            USING fts5(text, content='messages', content_rowid='rowid');

        CREATE TRIGGER IF NOT EXISTS msg_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS msg_ad AFTER DELETE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS msg_au AFTER UPDATE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
        END;
        """)
    }

    // MARK: writes

    /// Insert or update one message (keeps the FTS index in sync via triggers).
    func upsert(_ m: Message) {
        let sql = """
        INSERT INTO messages(id, thread, sender, text, ts, system, kind, mediaPath, mediaURL, replyToId, replyToText, replyToSender)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            text=excluded.text, ts=excluded.ts, kind=excluded.kind,
            mediaPath=excluded.mediaPath, mediaURL=excluded.mediaURL,
            replyToId=excluded.replyToId, replyToText=excluded.replyToText, replyToSender=excluded.replyToSender;
        """
        guard let st = prepare(sql) else { return }
        defer { sqlite3_finalize(st) }
        bind(m, to: st)
        sqlite3_step(st)
    }

    /// Bulk import (used once when migrating the old JSON cache). Wrapped in a
    /// transaction so it's fast and atomic.
    func bulkInsert(_ messagesByThread: [String: [Message]]) {
        exec("BEGIN;")
        for (_, msgs) in messagesByThread { for m in msgs { upsert(m) } }
        exec("COMMIT;")
    }

    func delete(id: String) {
        guard let st = prepare("DELETE FROM messages WHERE id=?;") else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(st)
    }

    /// Drop an entire conversation's messages (when a thread is deleted).
    func deleteThread(_ thread: String) {
        guard let st = prepare("DELETE FROM messages WHERE thread=?;") else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
        sqlite3_step(st)
    }

    // MARK: reads

    var count: Int {
        guard let st = prepare("SELECT count(*) FROM messages;") else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : 0
    }

    /// Everything, grouped by thread and ordered oldest→newest (the shape the UI holds).
    func allMessages() -> [String: [Message]] {
        var out: [String: [Message]] = [:]
        guard let st = prepare("SELECT \(Self.cols) FROM messages ORDER BY thread, ts;") else { return out }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            let m = row(st)
            out[m.thread, default: []].append(m)
        }
        return out
    }

    /// Only the most recent `perThread` messages of EVERY thread (oldest→newest within each).
    /// This is what loads at launch so we never pull a whole multi-thousand-message history
    /// into memory — older messages are paged in on demand (see `earlier`).
    func recentByThread(perThread: Int = 40) -> [String: [Message]] {
        var out: [String: [Message]] = [:]
        let sql = """
        SELECT \(Self.cols) FROM (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY thread ORDER BY ts DESC) AS rn FROM messages
        ) WHERE rn <= ? ORDER BY thread, ts;
        """
        guard let st = prepare(sql) else { return out }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(perThread))
        while sqlite3_step(st) == SQLITE_ROW { let m = row(st); out[m.thread, default: []].append(m) }
        return out
    }

    /// The most recent `limit` messages of one thread (oldest→newest).
    func recentMessages(thread: String, limit: Int = 40) -> [Message] {
        fetch("SELECT \(Self.cols) FROM messages WHERE thread=? ORDER BY ts DESC LIMIT ?;") { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 2, Int32(limit))
        }.reversed()
    }

    /// The `limit` messages immediately older than `beforeTs` in a thread (oldest→newest).
    /// Returns empty when the local DB has no more history (caller then hits the server).
    func earlier(thread: String, beforeTs: Double, limit: Int = 40) -> [Message] {
        fetch("SELECT \(Self.cols) FROM messages WHERE thread=? AND ts<? ORDER BY ts DESC LIMIT ?;") { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 2, beforeTs)
            sqlite3_bind_int(st, 3, Int32(limit))
        }.reversed()
    }

    /// A window of messages around `ts` (for jumping to a search hit), oldest→newest.
    func contextAround(thread: String, ts: Double, before: Int = 30, after: Int = 30) -> [Message] {
        let older = fetch("SELECT \(Self.cols) FROM messages WHERE thread=? AND ts<=? ORDER BY ts DESC LIMIT ?;") { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 2, ts)
            sqlite3_bind_int(st, 3, Int32(before))
        }.reversed()
        let newer = fetch("SELECT \(Self.cols) FROM messages WHERE thread=? AND ts>? ORDER BY ts ASC LIMIT ?;") { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 2, ts)
            sqlite3_bind_int(st, 3, Int32(after))
        }
        return older + newer
    }

    /// A whole thread's history, oldest→newest (used by export — never windowed).
    func allForThread(_ thread: String) -> [Message] {
        fetch("SELECT \(Self.cols) FROM messages WHERE thread=? ORDER BY ts;") { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
        }
    }

    /// True if a message with this id is already in our local history (any thread). Used to
    /// tell a genuinely-new live message from one the server replays on reconnect — the
    /// in-memory window only holds ~30 messages, so a containment check there is not enough.
    func exists(id: String) -> Bool {
        guard let st = prepare("SELECT 1 FROM messages WHERE id=? LIMIT 1;") else { return false }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(st) == SQLITE_ROW
    }

    /// Every local file path still referenced by a message. The housekeeper uses this so it
    /// never deletes a scratch/media file that some message in history still points at.
    func referencedMediaPaths() -> Set<String> {
        var out = Set<String>()
        guard let st = prepare("SELECT DISTINCT mediaPath FROM messages WHERE mediaPath IS NOT NULL;") else { return out }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            if let c = sqlite3_column_text(st, 0) { out.insert(String(cString: c)) }
        }
        return out
    }

    /// Repoint media file paths in bulk (old path → new path). Used to migrate sent
    /// attachments out of the throwaway temp dir into durable storage.
    func remapMediaPaths(_ map: [String: String]) {
        guard !map.isEmpty, let st = prepare("UPDATE messages SET mediaPath=? WHERE mediaPath=?;") else { return }
        defer { sqlite3_finalize(st) }
        for (old, new) in map {
            sqlite3_bind_text(st, 1, new, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, old, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(st)
            sqlite3_reset(st)
        }
    }

    /// Fetch specific messages by id (used by Saved messages, which may not be in any window).
    func byIDs(_ ids: [String]) -> [Message] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return fetch("SELECT \(Self.cols) FROM messages WHERE id IN (\(placeholders));") { st in
            for (i, id) in ids.enumerated() {
                sqlite3_bind_text(st, Int32(i + 1), id, -1, SQLITE_TRANSIENT)
            }
        }
    }

    /// Full-text search within ONE thread, newest first.
    func searchInThread(_ thread: String, _ query: String, limit: Int = 200) -> [Message] {
        let match = Self.ftsQuery(query)
        guard !match.isEmpty else { return [] }
        let mcols = Self.cols.split(separator: ",").map { "m.\($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: ",")
        return fetch("""
        SELECT \(mcols) FROM messages m JOIN messages_fts f ON f.rowid = m.rowid
        WHERE m.thread=? AND messages_fts MATCH ? ORDER BY m.ts DESC LIMIT ?;
        """) { st in
            sqlite3_bind_text(st, 1, thread, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, match, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 3, Int32(limit))
        }
    }

    /// Run a query that returns message rows, binding params via `bindFn`.
    private func fetch(_ sql: String, _ bindFn: (OpaquePointer) -> Void) -> [Message] {
        var out: [Message] = []
        guard let st = prepare(sql) else { return out }
        defer { sqlite3_finalize(st) }
        bindFn(st)
        while sqlite3_step(st) == SQLITE_ROW { out.append(row(st)) }
        return out
    }

    /// Full-text search across all history, newest first.
    func search(_ query: String, limit: Int = 200) -> [Message] {
        let match = Self.ftsQuery(query)
        guard !match.isEmpty else { return [] }
        var out: [Message] = []
        let sql = """
        SELECT \(Self.cols.split(separator: ",").map { "m.\($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: ","))
        FROM messages m JOIN messages_fts f ON f.rowid = m.rowid
        WHERE messages_fts MATCH ? ORDER BY m.ts DESC LIMIT ?;
        """
        guard let st = prepare(sql) else { return out }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(st, 2, Int32(limit))
        while sqlite3_step(st) == SQLITE_ROW { out.append(row(st)) }
        return out
    }

    // MARK: helpers

    private static let cols = "id, thread, sender, text, ts, system, kind, mediaPath, mediaURL, replyToId, replyToText, replyToSender"

    /// Turn a user phrase into a safe FTS5 MATCH query: each word quoted and
    /// prefix-matched, combined with implicit AND. Quotes inside words are escaped.
    private static func ftsQuery(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let terms = words.compactMap { w -> String? in
            let escaped = w.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.isEmpty ? nil : "\"\(escaped)\"*"
        }
        return terms.joined(separator: " ")
    }

    private func bind(_ m: Message, to st: OpaquePointer) {
        sqlite3_bind_text(st, 1, m.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 2, m.thread, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 3, m.sender, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 4, m.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(st, 5, m.ts)
        sqlite3_bind_int(st, 6, m.system ? 1 : 0)
        bindOpt(st, 7, m.kind)
        bindOpt(st, 8, m.mediaPath)
        bindOpt(st, 9, m.mediaURL)
        bindOpt(st, 10, m.replyToId)
        bindOpt(st, 11, m.replyToText)
        bindOpt(st, 12, m.replyToSender)
    }

    private func bindOpt(_ st: OpaquePointer, _ idx: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(st, idx, v, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(st, idx) }
    }

    private func row(_ st: OpaquePointer) -> Message {
        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(st, i) else { return nil }
            return String(cString: c)
        }
        var m = Message(id: text(0) ?? "", thread: text(1) ?? "", sender: text(2) ?? "",
                        text: text(3) ?? "", ts: sqlite3_column_double(st, 4),
                        system: sqlite3_column_int(st, 5) != 0)
        m.kind = text(6); m.mediaPath = text(7); m.mediaURL = text(8)
        m.replyToId = text(9); m.replyToText = text(10); m.replyToSender = text(11)
        return m
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard db != nil else { return nil }
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) != SQLITE_OK {
            NSLog("Relay SQLite prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return st
    }

    private func exec(_ sql: String) {
        guard db != nil else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("Relay SQLite exec failed: \(String(cString: err))")
            sqlite3_free(err)
        }
    }
}
