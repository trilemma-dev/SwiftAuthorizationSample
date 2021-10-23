//
//  AppDelegate.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-21
//

import Cocoa
import Blessed

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let sharedConstants: SharedConstants
    
    override init() {
        do {
            self.sharedConstants = try SharedConstants(caller: .app)
        } catch {
            print("One or more property list configuration issues exist. Please check the PropertyListModifier.swift " +
                  "script is run as part of the build process for both the app and helper tool targets. This script " +
                  "will automatically create all of the necessary configurations.")
            print("Issue: \(error)")
            exit(-1)
        }
        
        // Setup authorization right
        do {
            let right = SharedConstants.exampleRight
            if !(try right.isDefined()) {
                let description = ProcessInfo.processInfo.processName + " would like to perform a secure action."
                try right.createOrUpdateDefinition(rules: [CannedAuthorizationRightRules.authenticateAsAdmin],
                                                   descriptionKey: description)
            }
        } catch {
            print("Unable to create authorization right: \(SharedConstants.exampleRight.name)")
            print("Issue: \(error)")
            exit(-2)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
