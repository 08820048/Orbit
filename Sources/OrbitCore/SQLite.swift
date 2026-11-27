import Foundation
import SQLite3

/// Minimal SQLite wrapper. Not thread-safe; confine each instance to one actor/queue.
final class SQLiteDatabase {
    enum Error: Swift.Error, CustomStringConvertible {
        case open(path: String, code: Int32, message: String)
        case prepare(sql: String, message: String)
        case step(message: String)

        var description: String {
            switch self {
            case let .open(path, code, message): String(localized: "无法打开数据库 \(path)（\(code)）：\(message)")
            case let .prepare(sql, message): String(localized: "SQL 预编译失败：\(message)\n\(sql)")
            case let .step(message): String(localized: "SQL 执行失败：\(message)")
            }
        }

        /// SQLITE_AUTH / SQLITE_PERM / SQLITE_CANTOPEN are what we get without Full Disk Access.
        var isPermissionLike: Bool {
            if case let .open(_, code, _) = self {
                return code == SQLITE_CANTOPEN || code == SQLITE_PERM || code == SQLITE_AUTH
            }
            return false
        }
    }

    enum Value {
        case int(Int64), double(Double), text(String), null
    }

    private(set) var handle: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let code = sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_NOMUTEX, nil)
        if code != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw Error.open(path: path, code: code, message: message)
        }
        sqlite3_busy_timeout(handle, 2_000)
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw Error.step(message: message)
        }
    }

    func run(_ sql: String, _ params: [Value] = []) throws {
        try withStatement(sql, params) { stmt in
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw Error.step(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    func query<T>(_ sql: String, _ params: [Value] = [], row: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, params) { stmt in
            var out: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else {
                    throw Error.step(message: String(cString: sqlite3_errmsg(handle)))
                }
                out.append(try row(Row(stmt: stmt)))
            }
            return out
        }
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ params: [Value], _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Error.prepare(sql: sql, message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case let .int(v): sqlite3_bind_int64(stmt, idx, v)
            case let .double(v): sqlite3_bind_double(stmt, idx, v)
            case let .text(v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return try body(stmt)
    }

    struct Row {
        let stmt: OpaquePointer
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
