//
//  HelperToolMonitor.swift
//  SwiftAuthorizationApp
//
//  Created by Josh Kaplan on 2021-10-23
//

import Foundation
import EmbeddedPropertyList

/// Monitors the on disk location of the helper tool and its launchd property list.
///
/// Whenever those files change, the helper tool's embedded info property list is read and the launchd status is queried (via the public interface to launchctl). This
/// means this monitor has a limitation that if *only* the launchd registration changes then this monitor will not automatically pick up this changed. However, if
/// `determineStatus()` is called it will always reflect the latest state including querying launchd status.
class HelperToolMonitor {
    
    /// Encapsulates the installation status at approximately a moment in time.
    ///
    /// The individual properties of this struct can't be queried all at once, so it is possible for this to reflect a state that never truly existed simultaneously.
    struct InstallationStatus {
        /// The helper tool is registered with launchd (according to launchctl).
        let registeredWithLaunchd: Bool
        /// The property list used by launchd exists on disk.
        let registrationPropertyListExists: Bool
        /// The helper tool run by launchd exists on disk.
        let helperToolExists: Bool
        /// The `CFBundleVersion` of the helper tool on disk. Will be non-nil if `helperToolExists` is `true`.
        let helperToolBundleVersion: Version?
    }
    
    /// Directories containing installed helper tools and their registration property lists.
    private let monitoredDirectories: [URL]
    /// Mapping of monitored directories to corresponding dispatch sources.
    private var dispatchSources = [URL : DispatchSourceFileSystemObject]()
    /// Queue to receive callbacks on.
    private let directoryMonitorQueue = DispatchQueue(label: "directorymonitor", attributes: .concurrent)
    /// Name of the privileged executable being monitored
    private let constants: SharedConstants
    
    init(constants: SharedConstants) {
        self.constants = constants
        self.monitoredDirectories = [constants.blessedLocation.deletingLastPathComponent(),
                                     constants.blessedPropertyListLocation.deletingLastPathComponent()]
    }
    
    /// Starts the monitoring process.
    ///
    /// If it's already been started, this will have no effect. This function is not thread safe.
    /// - Parameter changeOccurred: Called when the helper tool or registration property list file is created, deleted, or modified.
    func start(changeOccurred: @escaping (InstallationStatus) -> Void) {
        if dispatchSources.isEmpty {
            for monitoredDirectory in monitoredDirectories {
                let fileDescriptor = open((monitoredDirectory as NSURL).fileSystemRepresentation, O_EVTONLY)
                let dispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor,
                                                                               eventMask: .write,
                                                                               queue: directoryMonitorQueue)
                dispatchSources[monitoredDirectory] = dispatchSource
                dispatchSource.setEventHandler {
                    changeOccurred(self.determineStatus())
                }
                dispatchSource.setCancelHandler {
                    close(fileDescriptor)
                    self.dispatchSources.removeValue(forKey: monitoredDirectory)
                }
                dispatchSource.resume()
            }
        }
    }

    /// Stops the monitoring process.
    ///
    /// If the process wa never started, this will have no effect. This function is not thread safe.
    func stop() {
        for source in dispatchSources.values {
            source.cancel()
        }
    }
    
    /// Determines the installation status of the helper tool
    /// - Returns: The status of the helper tool installation.
    func determineStatus() -> InstallationStatus {
        // Registered with launchd
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["print", "system/\(constants.helperToolLabel)"]
        process.qualityOfService = QualityOfService.userInitiated
        process.standardOutput = nil
        process.standardError = nil
        process.launch()
        process.waitUntilExit()
        let registeredWithLaunchd = (process.terminationStatus == 0)
        
        // Registration property list exists on disk
        let registrationPropertyListExists = FileManager.default
                                                        .fileExists(atPath: constants.blessedPropertyListLocation.path)
        
        let helperToolBundleVersion: Version?
        let helperToolExists: Bool
        do {
            let infoPropertyList = try HelperToolInfoPropertyList(from: constants.blessedLocation)
            helperToolBundleVersion = infoPropertyList.version
            helperToolExists = true
        } catch {
            helperToolBundleVersion = nil
            helperToolExists = false
        }
        
        return InstallationStatus(registeredWithLaunchd: registeredWithLaunchd,
                                  registrationPropertyListExists: registrationPropertyListExists,
                                  helperToolExists: helperToolExists,
                                  helperToolBundleVersion: helperToolBundleVersion)
    }
}
