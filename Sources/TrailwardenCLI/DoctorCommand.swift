// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check directories, database and rule catalogue.")

    @OptionGroup var store: StoreOptions

    @Flag(name: .long, help: "Print a block of counts that is safe to paste into a bug report.")
    var share = false

    @Flag(name: .long, help: "Count the record types and key names in each agent's transcripts.")
    var formats = false

    func run() throws {
        if share {
            let database = try store.open()
            try Output.write(ShareSummary.text(
                store: database,
                version: TrailwardenVersion.current,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString))
            return
        }
        if formats {
            printFormats()
            return
        }
        var healthy = true

        Output.write("Trailwarden \(TrailwardenVersion.current)  schema \(TrailwardenVersion.schema)")
        Output.write("macOS        \(ProcessInfo.processInfo.operatingSystemVersionString)")

        do {
            let rules = try RuleCatalog.builtIn()
            Output.write("rules        \(rules.count) loaded")
        } catch {
            Output.write("rules        FAILED: \(error)")
            healthy = false
        }

        let databaseURL = try store.url
        let exists = FileManager.default.fileExists(atPath: databaseURL.path)
        if exists {
            do {
                let database = try store.open()
                let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
                let size = Output.humanBytes((attributes[.size] as? Int) ?? 0)
                let permissions = String(
                    format: "%03o",
                    (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0)
                let version = try database.schemaVersion()
                let integrity = try database.integrityCheck()
                let sessions = try database.sessions().count
                let events = try database.eventCount()
                Output.write(
                    "database     \(databaseURL.path)  \(size)  schema \(version)  "
                        + "mode \(permissions)  integrity \(integrity)")
                Output.write("index        \(sessions) sessions, \(events) events")
                for agent in Agent.allCases {
                    let count = try database.eventCount(matching: EventQuery(agents: [agent]))
                    guard count > 0 else { continue }
                    let sessionCount = try database.sessions(agents: [agent]).count
                    Output.write("  \(agent.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))"
                        + " \(sessionCount) sessions, \(count) events")
                }
                if integrity != "ok" || version != EventStore.schemaVersion {
                    healthy = false
                }
            } catch {
                Output.write("database     FAILED: \(error)")
                healthy = false
            }
        } else {
            Output.write("database     \(databaseURL.path)  not created yet (run `trailwarden scan`)")
        }

        for source in ScanRoot.standardDatabases() {
            let exists = FileManager.default.fileExists(atPath: source.database.path)
            Output.write("db \(source.agent.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0))"
                + " \(source.database.path)  \(exists ? "readable" : "absent")")
        }

        for root in ScanRoot.standard() {
            var isDirectory: ObjCBool = false
            let present = FileManager.default.fileExists(
                atPath: root.directory.path,
                isDirectory: &isDirectory)
            let label = root.agent.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            if present, isDirectory.boolValue {
                Output
                    .write(
                        "root \(label) \(root.directory.path)  \(transcriptCount(in: root)) transcripts")
            } else {
                Output.write("root \(label) \(root.directory.path)  missing")
            }
        }

        if !healthy {
            throw ExitCode(1)
        }
    }

    private func printFormats() {
        for root in ScanRoot.standard() {
            guard let enumerator = FileManager.default.enumerator(
                at: root.directory, includingPropertiesForKeys: nil) else { continue }
            let files = enumerator.compactMap { $0 as? URL }.filter { root.parser.accepts($0) }
            guard !files.isEmpty else { continue }
            Output.write("\(root.agent.rawValue) (\(files.count) files)")
            Output.write(FormatCensus.text(FormatCensus.census(of: files, agent: root.agent)))
        }
    }

    private func transcriptCount(in root: ScanRoot) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root.directory,
            includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for case let url as URL in enumerator where root.parser.accepts(url) {
            count += 1
        }
        return count
    }
}
