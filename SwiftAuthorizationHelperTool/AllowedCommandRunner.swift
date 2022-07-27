//
//  AllowedProcessRunner.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-24
//

import Foundation
import Authorized

/// Runs an allowed command.
enum AllowedCommandRunner {
    /// Runs the allowed command and replies with the results.
    ///
    /// If authorization is needed, the user will be prompted.
    ///
    /// - Parameter message: Message containing the command to run, and if applicable the authorization.
    /// - Returns: The results of running the command.
    static func run(message: AllowedCommandMessage) throws -> AllowedCommandReply {
        // Prompt user to authorize if the client requested it
        if case .authorizedCommand(_, let authorization) = message {
            let rights = try authorization.requestRights([SharedConstants.exampleRight],
                                                         environment: [],
                                                         options: [.interactionAllowed, .extendRights])
            guard rights.contains(where: { $0.name == SharedConstants.exampleRight.name }) else {
                throw AllowedCommandError.authorizationFailed
            }
        } else if message.command.requiresAuth { // Authorization is required, but the client did not request it
            throw AllowedCommandError.authorizationNotRequested
        }
        
        // Launch process and wait for it to finish
        let process = Process()
        process.launchPath = message.command.launchPath
        process.arguments = message.command.arguments
        process.qualityOfService = QualityOfService.userInitiated
        let outputPipe = Pipe()
        defer { outputPipe.fileHandleForReading.closeFile() }
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        defer { errorPipe.fileHandleForReading.closeFile() }
        process.standardError = errorPipe
        process.launch()
        process.waitUntilExit()
        
        // Convert a pipe's data to a string if there was non-whitespace output
        let pipeAsString = { (pipe: Pipe) -> String? in
            let output = String(data: pipe.fileHandleForReading.availableData, encoding: String.Encoding.utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? nil : output
        }
        
        return AllowedCommandReply(terminationStatus: process.terminationStatus,
                                   standardOutput: pipeAsString(outputPipe),
                                   standardError: pipeAsString(errorPipe))
    }
}
