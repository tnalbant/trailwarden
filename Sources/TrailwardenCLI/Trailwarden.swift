// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

@main
struct Trailwarden: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trailwarden",
        abstract: "Audit trail for coding agents on this Mac.",
        version: TrailwardenVersion.current,
        subcommands: [
            ScanCommand.self,
            WatchCommand.self,
            WhoCommand.self,
            ExportCommand.self,
            RulesCommand.self,
            DoctorCommand.self
        ])

    /// The documented contract is 0 clean, 1 findings, 2 usage. `exit(withError:)`
    /// builds its code from the error itself and ignores `exitCode(for:)`, so the
    /// parsing phase is separated from the run phase here: anything that fails
    /// while parsing arguments is a usage error (2), while a runtime failure keeps
    /// 1 (or whatever `ExitCode` the command throws).
    static func main() {
        var command: ParsableCommand
        do {
            command = try parseAsRoot()
        } catch {
            // A --help/--version request must keep the library's output and exit 0.
            if requestsHelpOrVersion(error) {
                Self.exit(withError: error)
            }
            usageExit()
        }

        do {
            try command.run()
        } catch let code as ExitCode {
            Foundation.exit(code.rawValue)
        } catch let clean as CleanExit {
            Self.exit(withError: clean)
        } catch let validation as ValidationError {
            Output.error("Error: \(validation.message)")
            Foundation.exit(2)
        } catch {
            // `--help` and `--version` arrive as a command in the run phase.
            if requestsHelpOrVersion(error) {
                Self.exit(withError: error)
            }
            Output.error("Error: \(error)")
            Foundation.exit(1)
        }
    }

    /// argument-parser keeps its error types internal, so the description is the
    /// only public signal for "the user asked for help". Those requests have to
    /// reach the library's own renderer; everything else in the parse phase is a
    /// usage error.
    private static func requestsHelpOrVersion(_ error: Error) -> Bool {
        let description = String(describing: error)
        return description.contains("helpRequested") || description.contains("versionRequested")
    }

    private static func usageExit() -> Never {
        Output.error("Error: could not parse the command line.")
        Output.error("Usage: trailwarden <scan|watch|who|export|rules|doctor> [options]")
        Output.error("  Run 'trailwarden --help' for the full syntax.")
        Foundation.exit(2)
    }
}
