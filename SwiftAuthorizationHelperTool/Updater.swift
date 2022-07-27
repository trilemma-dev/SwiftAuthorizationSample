//
//  Updater.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-24
//

import Foundation
import EmbeddedPropertyList

/// An in-place updater for the helper tool.
///
/// To keep things simple, this updater only works if `launchd` property lists do not change between versions.
enum Updater {
    /// Replaces itself with the helper tool located at the provided `URL` so long as security, launchd, and version requirements are met.
    ///
    /// - Parameter helperTool: Path to the helper tool.
    /// - Throws: If the helper tool file can't be read, public keys can't be determined, or `launchd` property lists can't be compared.
    static func updateHelperTool(atPath helperTool: URL) throws {
        guard try CodeInfo.doesPublicKeyMatch(forExecutable: helperTool) else {
            NSLog("update failed: security requirements not met")
            return
        }
        
        guard try launchdPropertyListsMatch(forHelperTool: helperTool) else {
            NSLog("update failed: launchd property list has changed")
            return
        }
        
        let (isNewer, currentVersion, otherVersion) = try isHelperToolNewerVersion(atPath: helperTool)
        guard isNewer else {
            NSLog("update failed: not a newer version. current: \(currentVersion), other: \(otherVersion).")
            return
        }
        
        try Data(contentsOf: helperTool).write(to: CodeInfo.currentCodeLocation(), options: .atomicWrite)
        NSLog("update succeeded: current version \(currentVersion) exiting...")
        exit(0)
    }
    
    /// Determines if the helper tool located at the provided `URL` is actually an update.
    ///
    /// - Parameter helperTool: Path to the helper tool.
    /// - Throws: If unable to read the info property lists of this helper tool or the one located at `helperTool`.
    /// - Returns: If the helper tool at the location specified by `helperTool` is newer than the one running this code and the versions of both.
    private static func isHelperToolNewerVersion(
        atPath helperTool: URL
    ) throws -> (isNewer: Bool, current: BundleVersion, other: BundleVersion) {
        let current = try HelperToolInfoPropertyList.main.version
        let other = try HelperToolInfoPropertyList(from: helperTool).version
        
        return (other > current, current, other)
    }
    
    /// Determines if the `launchd` property list used by this helper tool and the executable located at the provided `URL` are byte-for-byte identical.
    ///
    /// This matters because only the helper tool itself is being updated, the property list generated for `launchd` will not be updated as part of this update
    /// process.
    ///
    /// - Parameter helperTool: Path to the helper tool.
    /// - Throws: If unable to read the `launchd` property lists of this helper tool or the one located at `helperTool`.
    /// - Returns: If the two `launchd` property lists match.
    private static func launchdPropertyListsMatch(forHelperTool helperTool: URL) throws -> Bool {
        try EmbeddedPropertyListReader.launchd.readInternal() ==
        EmbeddedPropertyListReader.launchd.readExternal(from: helperTool)
    }
}
