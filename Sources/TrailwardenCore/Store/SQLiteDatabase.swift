// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation
import SQLite3

/// Errors raised by the storage layer. Messages are for humans, never for parsing.
public enum StoreError: Error, CustomStringConvertible, Sendable {
    case open(String)
    case sql(String)

    public var description: String {
        switch self {
        case let .open(message): "sqlite open failed: \(message)"
        case let .sql(message): "sqlite error: \(message)"
        }
    }
}

/// The value types SQLite accepts from this code base.
enum SQLValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null
}

/// Thin wrapper over the system SQLite C API. No ORM, no dependency: the audit
/// trail database has to stay inspectable with the stock `sqlite3` binary.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(path: String) throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let pointer {
                sqlite3_close_v2(pointer)
            }
            throw StoreError.open(message)
        }
        handle = pointer
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw StoreError.sql("\(message) [\(sql.prefix(80))]")
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw StoreError.sql("\(lastErrorMessage) [\(sql.prefix(80))]")
        }
        return SQLiteStatement(statement: statement, database: handle)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

/// One prepared statement. Values are bound with the transient destructor so a
/// Swift string does not have to outlive the call that bound it.
final class SQLiteStatement {
    private let statement: OpaquePointer
    private let database: OpaquePointer

    init(statement: OpaquePointer, database: OpaquePointer) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func bind(_ values: [SQLValue]) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32 = switch value {
            case let .text(text):
                sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let .int(number):
                sqlite3_bind_int64(statement, index, Int64(number))
            case let .double(number):
                sqlite3_bind_double(statement, index, number)
            case .null:
                sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else {
                throw StoreError.sql(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    /// Runs the statement; returns `true` when a row is available.
    @discardableResult
    func step() throws -> Bool {
        let status = sqlite3_step(statement)
        switch status {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.sql(String(cString: sqlite3_errmsg(database)))
        }
    }

    var columnCount: Int32 {
        sqlite3_column_count(statement)
    }

    func text(_ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    func int(_ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(
            statement,
            index))
    }

    func double(_ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }
}
