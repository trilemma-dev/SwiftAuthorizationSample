#!/usr/bin/env xcrun --sdk macosx swift
//
//  PropertyListModifier.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-23
//

// This script generates all of the property list requirements needed by SMJobBless and XPC Mach Services in conjunction
// with user defined variables specified in the xcconfig files. This involves adding/removing entries to:
//  - Apps's Info property list
//  - Helper tools's Info property list
//  - Helper tools's launchd property list
//
// By default, this script is run both at the beginning and end of the build process for both targets. When run at the
// end it undoes all of the property list requirement changes it applied to satisfy SMJobBless.
//
// There are two other functions this script can perform:
//  - Adds a MachServices entry to the helper tool's launchd property list
//      - This allows for the helper tool to be communicated with over XPC
//      - This entry can also be removed at the end of the build process
//  - Auto-increments the helper tools's version number whenever its source code changes
//      - SMJobBless will only successfully install a new helper tool over an existing one if its version is greater
//      - In order to track changes, a BuildHash entry will be added to the helper tool's Info property list
//
// All of these options are configured by passing in command line arguments to this script. See ScriptTask for details.

import Foundation
import CryptoKit

/// Errors raised throughout this script
enum ScriptError: Error {
    case general(String)
    case wrapped(String, Error)
}

// MARK: helper functions to read environment variables

/// Attempts to read an environment variable, throws an error if it is not present
///
/// - Parameters:
///   - name: name of the environment variable
///   - description: a description of what was trying to be read; used in the error message if one is thrown
///   - isUserDefined: whether the environment variable is user defined; used to modify the error message if one is thrown
func readEnvironmentVariable(name: String, description: String, isUserDefined: Bool) throws -> String {
    if let value = ProcessInfo.processInfo.environment[name] {
        return value
    } else {
        var message = "Unable to determine \(description), missing \(name) environment variable."
        if isUserDefined {
            message += " This is a user-defined variable. Please check that the xcconfig files are present and " +
                       "configured in the project settings."
        }
        
        throw ScriptError.general(message)
    }
}

/// Attempts to read an environment variable as a URL
func readEnvironmentVariableAsURL(name: String, description: String, isUserDefined: Bool) throws -> URL {
    let value = try readEnvironmentVariable(name: name, description: description, isUserDefined: isUserDefined)
    
    return URL(fileURLWithPath: value)
}

// MARK: property list keys

/// Key for entry in helper tool's launchd property list
let LabelKey = "Label"

/// Key for entry in app's info property list
let SMPrivilegedExecutablesKey = "SMPrivilegedExecutables"

/// Key for entry in helper tool's info property list
let SMAuthorizedClientsKey = "SMAuthorizedClients"

/// Key for bundle identifier
let CFBundleIdentifierKey = kCFBundleIdentifierKey as String

/// Key for bundle version
let CFBundleVersionKey = kCFBundleVersionKey as String

/// Key for XPC mach service used by the helper tool
let MachServicesKey = "MachServices"

/// Custom key for an entry in the helper tool's info plist that contains a hash of source files. Used to detect when the build changes.
let BuildHashKey = "BuildHash"

// MARK: Object Identifiers (OID) describing code signing certificates and associated certificate representations

/// Certificate used by Mac App Store apps
///
/// Mac App Store Application Software Signing, documented in section "4.11.8. Mac App Store Application Certificates"
/// Apple Inc. Certification Practice Statement Worldwide Developer Relations
/// Version 1.25, Effective Date: August 10, 2021
/// https://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.25.pdf
let oidAppleMacAppStoreApplication = "1.2.840.113635.100.6.1.9"

/// Intermediate certificate used by Developer ID macOS apps (as well as macOS installers)
///
/// Documented in  SecPolicyCreateAppleExternalDeveloper function in SecPolicyPriv.h
/// Found at https://opensource.apple.com/source/Security/Security-57740.51.3/trust/SecPolicyPriv.h
let oidAppleDeveloperIDCA = "1.2.840.113635.100.6.2.6"

/// Development team's leaf certificate used to sign Developer ID macOS apps
///
/// Apple Custom Extension, documented in section "4.11.2.Application Code Signing Certificates"
/// Apple Inc. Certification Practice Statement Developer ID
/// Version 3.2, Effective Date: June 2, 2021
/// https://images.apple.com/certificateauthority/pdf/Apple_Developer_ID_CPS_v3.2.pdf
let oidAppleDeveloperIDApplication = "1.2.840.113635.100.6.1.13"

/// Intermediate certificate used for most Apple development including "Apple Development" and "Mac Development" used when building apps as part of
/// development workflows not intended for distribution
let oidAppleWWDRIntermediate = kSecOIDAPPLE_EXTENSION_WWDR_INTERMEDIATE // 1.2.840.113635.100.6.2.1

// MARK: code signing requirements

let appleDeveloperID = "certificate leaf[field.\(oidAppleMacAppStoreApplication)] /* exists */ " +
                       "or certificate 1[field.\(oidAppleDeveloperIDCA)] /* exists */ " +
                       "and certificate leaf[field.\(oidAppleDeveloperIDApplication)] /* exists */"

let appleMacDeveloper = "certificate 1[field.\(oidAppleWWDRIntermediate)] /* exists */"

let appleGeneric = "anchor apple generic"

func appleDevelopment() throws -> String {
    let appleDevelopmentCN = try readEnvironmentVariable(name: "EXPANDED_CODE_SIGN_IDENTITY_NAME",
                                                         description: "expanded code sign identity name",
                                                         isUserDefined: false)
    let regex = #"^Apple\ Development:\ .*\ \([A-Z0-9]{10}\)$"#
    guard appleDevelopmentCN.range(of: regex, options: .regularExpression) != nil else {
        if appleDevelopmentCN == "-" {
            throw ScriptError.general("Signing Team for Debug is set to None")
        } else {
            throw ScriptError.general("Signing Team for Debug is invalid: \(appleDevelopmentCN)")
        }
    }
    let certificateString = "certificate leaf[subject.CN] = \"\(appleDevelopmentCN)\""
    
    return certificateString
}

func developerID() throws -> String {
    let developmentTeam = try readEnvironmentVariable(name: "DEVELOPMENT_TEAM",
                                                      description: "development team",
                                                      isUserDefined: false)
    guard developmentTeam.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
        if developmentTeam == "-" {
            throw ScriptError.general("Signing Team for Release is set to None")
        } else {
            throw ScriptError.general("Signing Team for Release is invalid: \(developmentTeam)")
        }
    }
    let certificateString = "certificate leaf[subject.OU] = \(developmentTeam)"
    
    return certificateString
}

func identifierApp() throws -> String {
    return "identifier \"\(try TargetType.app.bundleIdentifier())\""
}

func identifierHelperTool() throws -> String {
    return "identifier \"\(try TargetType.helperTool.bundleIdentifier())\""
}

/// Creates a `SMAuthorizedClients` entry representing the app which must go inside the helper tool's info property list
///
/// - Returns: entry with key `SMAuthorizedClients` and value matching output of: `codesign -d -r - <app bundle>`
func SMAuthorizedClientsEntry(forAction action: ActionType) throws -> (key: String, value: [String]) {
    let requirements: [String]
    switch action {
        case .build:
            requirements = [try identifierApp(), appleGeneric, try appleDevelopment(), appleMacDeveloper]
        case .install:
            requirements = [appleGeneric, try identifierApp(), "(\(appleDeveloperID) and \(try developerID()))"]
        default:
            throw ScriptError.general("Unsupported action")
    }
    
    return (key: SMAuthorizedClientsKey, value: [requirements.joined(separator: " and ")])
}

/// Creates a `SMPrivilegedExecutables` entry representing the helper tool which must go inside the app's info property list
///
/// - Returns: entry with key `SMPrivilegedExecutables` and value a dictionary of one element, with the key for helper tool label and the value
///            matching output of: `codesign -d -r - <helper tool>`
func SMPrivilegedExecutablesEntry(forAction action: ActionType) throws -> (key: String, value: [String : String]) {
    let requirements: [String]
    switch action {
        case .build:
            requirements = [try identifierHelperTool(),
                            appleGeneric,
                            try appleDevelopment(),
                            appleMacDeveloper]
        case .install:
            requirements = [appleGeneric,
                            try identifierHelperTool(),
                            "(\(appleDeveloperID) and \(try developerID()))"]
        default:
            throw ScriptError.general("Unsupported action")
    }
    
    return (key: SMPrivilegedExecutablesKey,
            value: [try TargetType.helperTool.bundleIdentifier() : requirements.joined(separator: " and ")])
}

/// Creates a `Label` entry which must go inside the helper tool's launchd property list
///
/// - Returns: entry with key `Label` and value for the helper tool's label
func LabelEntry() throws -> (key: String, value: String) {
    return (key: LabelKey, value: try TargetType.helperTool.bundleIdentifier())
}

// MARK: property list manipulation

/// Reads the property list at the provided path
///
/// - Parameters:
///   - atPath: where the property list is located
/// - Returns: tuple containing entries and the format of the on disk property list
func readPropertyList(atPath path: URL) throws -> (entries: NSMutableDictionary,
                                                   format: PropertyListSerialization.PropertyListFormat) {
    let onDiskPlistData: Data
    do {
        onDiskPlistData = try Data(contentsOf: path)
    } catch {
        throw ScriptError.wrapped("Unable to read property list at: \(path)", error)
    }
    
    do {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: onDiskPlistData,
                                                               options: .mutableContainersAndLeaves,
                                                               format: &format)
        if let entries = plist as? NSMutableDictionary {
            return (entries: entries, format: format)
        }
        else {
            throw ScriptError.general("Unable to cast parsed property list")
        }
    }
    catch {
        throw ScriptError.wrapped("Unable to parse property list", error)
    }
}

/// Writes (or overwrites) a property list at the provided path
///
/// - Parameters:
///   - atPath: where the property list should be written
///   - entries: total of entries to be written to the property list
///   - format: the format to use when writing entries into the Info.plist on disk
func writePropertyList(atPath path: URL,
                       entries: NSDictionary,
                       format: PropertyListSerialization.PropertyListFormat) throws {
    let plistData: Data
    do {
        plistData = try PropertyListSerialization.data(fromPropertyList: entries,
                                                       format: format,
                                                       options: 0)
    } catch {
        throw ScriptError.wrapped("Unable to serialize property list in order to write to path: \(path)", error)
    }
    
    do {
        try plistData.write(to: path)
    }
    catch {
        throw ScriptError.wrapped("Unable to write property list to path: \(path)", error)
    }
}

/// Updates the property list with the provided entries
///
/// If an existing entry exists for the given key it will be overwritten. If the property file does not exist, it will be created.
func updatePropertyListWithEntries(_ newEntries: [String : AnyHashable], atPath path: URL) throws {
    let (entries, format) : (NSMutableDictionary, PropertyListSerialization.PropertyListFormat)
    if FileManager.default.fileExists(atPath: path.path) {
        (entries, format) = try readPropertyList(atPath: path)
    } else {
        (entries, format) = ([:], PropertyListSerialization.PropertyListFormat.xml)
    }
    for (key, value) in newEntries {
        entries.setValue(value, forKey: key)
    }
    try writePropertyList(atPath: path, entries: entries, format: format)
}

/// Updates the property list by removing the provided keys (if present)
func removePropertyListEntries(forKeys keys: [String], atPath path: URL) throws {
    let (entries, format) = try readPropertyList(atPath: path)
    for key in keys {
        entries.removeObject(forKey: key)
    }
    
    try writePropertyList(atPath: path, entries: entries, format: format)
}

/// The path of the info property list (typically has the name Info.plist)
func infoPropertyListPath() throws -> URL {
    return try readEnvironmentVariableAsURL(name: "INFOPLIST_FILE",
                                            description: "info property list path",
                                            isUserDefined: true)
}

/// Finds the path of the launchd property list for the helper tool
///
/// This will not work if called when the target is the app. This function relies on an expected "Other Link Flags" value format.
func launchdPropertyListPath() throws -> URL {
    try readEnvironmentVariableAsURL(name: "LAUNCHDPLIST_FILE",
                                     description: "launchd property list path",
                                     isUserDefined: true)
}

// MARK: automatic bundle version updating

/// Hashes Swift source files in the helper tool's directory as well as shared directories
///
/// - Returns: hash value, hex encoded
func hashSources() throws -> String {
    // Directories to hash source files in
    let sourcePaths: [URL] = [
        try infoPropertyListPath().deletingLastPathComponent(),
        try readEnvironmentVariableAsURL(name: "SHARED_DIRECTORY",
                                         description: "shared source directory path",
                                         isUserDefined: true)
    ]
    
    // Enumerate over and hash Swift source files
    var sha256 = SHA256()
    for sourcePath in sourcePaths {
        if let enumerator = FileManager.default.enumerator(at: sourcePath, includingPropertiesForKeys: []) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    do {
                        sha256.update(data: try Data(contentsOf: fileURL))
                    } catch {
                        throw ScriptError.wrapped("Unable to hash \(fileURL)", error)
                    }
                }
            }
        } else {
            throw ScriptError.general("Could not create enumerator for: \(sourcePath)")
        }
    }
    let digestHex = sha256.finalize().compactMap{ String(format: "%02x", $0) }.joined()
    
    return digestHex
}

/// Represents the value corresponding to the key `CFBundleVersionKey` in the info property list
struct BundleVersion {
    let version: String
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(version: String) {
        self.version = version
        
        let versionParts = version.split(separator: ".")
        if versionParts.count == 1,
           let major = Int(versionParts[0]) {
            self.major = major
            self.minor = 0
            self.patch = 0
        }
        else if versionParts.count == 2,
            let major = Int(versionParts[0]),
            let minor = Int(versionParts[1]) {
            self.major = major
            self.minor = minor
            self.patch = 0
        }
        else if versionParts.count == 3,
            let major = Int(versionParts[0]),
            let minor = Int(versionParts[1]),
            let patch = Int(versionParts[2]) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
        else {
            return nil
        }
    }
    
    private init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
        
        self.version = "\(major).\(minor).\(patch)"
    }
    
    func incrementPatch() -> BundleVersion {
        return BundleVersion(major: self.major, minor: self.minor, patch: self.patch + 1)
    }
}

/// Reads the `CFBundleVersion` value from the passed in dictionary
func readBundleVersion(propertyList: NSMutableDictionary) throws -> BundleVersion {
    if let value = propertyList[CFBundleVersionKey] as? String {
        if let version = BundleVersion(version: value) {
            return version
        } else {
            throw ScriptError.general("Invalid value for \(CFBundleVersionKey) in property list")
        }
    } else {
        throw ScriptError.general("Could not find version, \(CFBundleVersionKey) missing in property list")
    }
}

/// Reads the `BuildHash` value from the passed in dictionary
func readBuildHash(propertyList: NSMutableDictionary) throws -> String? {
    return propertyList[BuildHashKey] as? String
}

/// Reads the information property list, determines if the build has changed based on stored hash values, and increments the build version if it has.
func incrementBundleVersionIfNeeded(infoPropertyListPath: URL) throws {
    let propertyList = try readPropertyList(atPath: infoPropertyListPath)
    let previousBuildHash = try readBuildHash(propertyList: propertyList.entries)
    let currentBuildHash = try hashSources()
    if currentBuildHash != previousBuildHash {
        let version = try readBundleVersion(propertyList: propertyList.entries)
        let newVersion = version.incrementPatch()
        
        propertyList.entries[BuildHashKey] = currentBuildHash
        propertyList.entries[CFBundleVersionKey] = newVersion.version
        
        try writePropertyList(atPath: infoPropertyListPath,
                              entries: propertyList.entries,
                              format: propertyList.format)
    }
}

// MARK: identification of under what conditions this script is being run based on Xcode environment variables

/// The two build targets used as part of `SMJobBless`
///
/// If you rename either of these, you *must* update the values below
enum TargetType: String {
    case app = "APP_BUNDLE_IDENTIFIER"
    case helperTool = "HELPER_TOOL_BUNDLE_IDENTIFIER"
    
    func bundleIdentifier() throws -> String {
        return try readEnvironmentVariable(name: self.rawValue,
                                           description: "bundle identifier for \(self)",
                                           isUserDefined: true)
    }
}

/// Determines whether this script is running for the app or the helper tool
///
/// This relies on the hard coded constants at the top of this file
func determineTargetType() throws -> TargetType {
    let bundleId = try readEnvironmentVariable(name: "PRODUCT_BUNDLE_IDENTIFIER",
                                               description: "bundle id",
                                               isUserDefined: false)
    
    let appBundleIdentifier = try TargetType.app.bundleIdentifier()
    let helperToolBundleIdentifier = try TargetType.helperTool.bundleIdentifier()
    if bundleId == appBundleIdentifier {
        return TargetType.app
    } else if bundleId ==  helperToolBundleIdentifier {
        return TargetType.helperTool
    } else {
        throw ScriptError.general("Unexpected bundle id \(bundleId) encountered. This means you need to update the " +
                                  "user defined variables APP_BUNDLE_IDENTIFIER and/or " +
                                  "HELPER_TOOL_BUNDLE_IDENTIFIER in Config.xcconfig.")
    }
}

/// The type of build action performed to result in this script being run
enum ActionType {
    /// Typically the standard action which occurs when clicking on the "play" button
    case build
    /// Typically triggered when creating an Archive
    case install
    /// Another build case not handled by this script such as `docbuild`
    case other(String)
    
    init(rawValue: String) {
        if rawValue == "build" {
            self = .build
        } else if rawValue == "install" {
            self = .install
        } else {
            self = .other(rawValue)
        }
    }
}

/// Determines whether this script is being run for a "build" (typical during development) or "install" (typical during Archive)
func determineActionType() throws -> ActionType {
    let actionString = try readEnvironmentVariable(name: "ACTION", description: "build action", isUserDefined: false)
    
    return ActionType(rawValue: actionString)
}

// MARK: tasks

/// The tasks this script can perform. They're provided as command line arguments to this script.
typealias ScriptTask = () throws -> Void
let scriptTasks: [String : ScriptTask] = [
    /// Update the plist(s) as needed to satisfy the requirements of SMJobBless
    "satisfyJobBlessRequirements" : satisfyJobBlessRequirements,
    /// Clean up changes made to plist(s) to satisfy the requirements of SMJobBless
    "cleanupJobBlessRequirements" : cleanupJobBlessRequirements,
    /// Specifies mach services in the helper tool's launchd property list to enable XPC
    "specifyMachServices" : specifyMachServices,
    /// Cleans up changes made to mach services in the helper tool's launchd property list to enable XPC
    "cleanupMachServices" : cleanupMachServices,
    /// Auto increment the bundle version number; only intended for the privileged helper
    "autoIncrementVersion" : autoIncrementVersion
]

/// Determines what tasks this script should undertake in based on passed in arguments
func determineScriptTasks() throws -> [ScriptTask] {
    if CommandLine.arguments.count > 1 {
        var matchingTasks = [ScriptTask]()
        for index in 1..<CommandLine.arguments.count {
            let arg = CommandLine.arguments[index]
            if let task = scriptTasks[arg] {
                matchingTasks.append(task)
            } else {
                throw ScriptError.general("Unexpected value provided as argument to script: \(arg)")
            }
        }
        return matchingTasks
    } else {
        throw ScriptError.general("No value(s) provided as argument to script")
    }
}

/// Updates the property lists for the app or helper tool to satisfy SMJobBless requirements
func satisfyJobBlessRequirements() throws {
    let action = try determineActionType()
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
        case .helperTool:
            let clients = try SMAuthorizedClientsEntry(forAction: action)
            let infoEntries: [String : AnyHashable] = [CFBundleIdentifierKey : try target.bundleIdentifier(),
                                                       clients.key : clients.value]
            try updatePropertyListWithEntries(infoEntries, atPath: infoPropertyList)
            
            let launchdPropertyList = try launchdPropertyListPath()
            let label = try LabelEntry()
            try updatePropertyListWithEntries([label.key : label.value], atPath: launchdPropertyList)
        case .app:
            let executables = try SMPrivilegedExecutablesEntry(forAction: action)
            try updatePropertyListWithEntries([executables.key : executables.value], atPath: infoPropertyList)
    }
}

/// Removes the requirements from property lists needed to satisfy SMJobBless requirements
func cleanupJobBlessRequirements() throws {
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
        case .helperTool:
            try removePropertyListEntries(forKeys: [SMAuthorizedClientsKey, CFBundleIdentifierKey],
                                          atPath: infoPropertyList)
            
            let launchdPropertyList = try launchdPropertyListPath()
            try removePropertyListEntries(forKeys: [LabelKey], atPath: launchdPropertyList)
        case .app:
            try removePropertyListEntries(forKeys: [SMPrivilegedExecutablesKey], atPath: infoPropertyList)
    }
}

/// Creates a MachServices entry for the helper tool, fails if called for the app
func specifyMachServices() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            let services = [MachServicesKey: [try TargetType.helperTool.bundleIdentifier() : true]]
            try updatePropertyListWithEntries(services, atPath: try launchdPropertyListPath())
        case .app:
            throw ScriptError.general("specifyMachServices only available for helper tool")
    }
}

/// Removes a MachServices entry for the helper tool, fails if called for the app
func cleanupMachServices() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            try removePropertyListEntries(forKeys: [MachServicesKey], atPath: try launchdPropertyListPath())
        case .app:
            throw ScriptError.general("cleanupMachServices only available for helper tool")
    }
}

/// Increments the helper tool's version, fails if called for the app
func autoIncrementVersion() throws {
    let target = try determineTargetType()
    switch target {
        case .helperTool:
            let infoPropertyList = try infoPropertyListPath()
            try incrementBundleVersionIfNeeded(infoPropertyListPath: infoPropertyList)
        case .app:
            throw ScriptError.general("autoIncrementVersion only available for helper tool")
    }
}

// MARK: script starts here

do {
    if case let .other(action) = try determineActionType() {
        print("warn: Xcode action not supported by JobBless build script: \(action)")
    } else {
        for task in try determineScriptTasks() {
            try task()
        }
    }
}
catch ScriptError.general(let message) {
    print("error: \(message)")
    exit(1)
}
catch ScriptError.wrapped(let message, let wrappedError) {
    print("error: \(message)")
    print("internal error: \(wrappedError)")
    exit(2)
}
