//
//  ViewController.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-21
//

import Cocoa
import Authorized
import Blessed
import EmbeddedPropertyList
import SecureXPC

class ViewController: NSViewController {
    // Defined in the Storyboard
    @IBOutlet weak var installedField: NSTextField!
    @IBOutlet weak var versionField: NSTextField!
    @IBOutlet weak var uninstallButton: NSButton!
    @IBOutlet weak var installOrUpdateButton: NSButton!
    @IBOutlet weak var commandPopup: NSPopUpButton!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var outputText: NSTextView!
    
    // Initialized in viewDidLoad()
    
    /// Monitors the helper tool, if installed.
    private var monitor: HelperToolMonitor!
    /// The location of the helper tool bundlded with this app.
    private var bundledLocation: URL!
    /// The version of the helper tool bundled with this app (not necessarily the version installed).
    private var bundledHelperToolVersion: BundleVersion!
    /// Used to communicate with the helper tool.
    private var xpcClient: XPCClient!
    
    /// Authorization instance used for the run of this app. This needs a persistent scope because once the authorization instance is deinitialized it will no longer be
    /// valid system-wide, including in other processes such as the helper tool.
    private var authorization: Authorization?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Command pop options
        for command in AllowedCommand.allCases {
            let menuItem = NSMenuItem(title: command.displayName, action: nil, keyEquivalent: "")
            menuItem.representedObject = command
            commandPopup.menu?.addItem(menuItem)
        }
        
        // Output text field
        outputText.font = NSFont.userFixedPitchFont(ofSize: 11)
        
        // Have this button call this target when clicked, the specific function called will differ
        self.installOrUpdateButton.target = self

        // Initialize variables using shared constants
        let sharedConstants: SharedConstants
        do {
            sharedConstants = try SharedConstants()
        } catch {
            fatalError("""
            One or more property list configuration issues exist. Please check the PropertyListModifier.swift script \
            is run as part of the build process for both the app and helper tool targets. This script will \
            automatically create all of the necessary configurations.
            Issue: \(error)
            """)
        }
        self.xpcClient = XPCClient.forMachService(named: sharedConstants.machServiceName)
        self.bundledLocation = sharedConstants.bundledLocation
        self.bundledHelperToolVersion = sharedConstants.helperToolVersion
        self.monitor = HelperToolMonitor(constants: sharedConstants)
        self.updateInstallationStatus(self.monitor.determineStatus())
        self.monitor.start(changeOccurred: self.updateInstallationStatus)
    }
    
    override func viewWillAppear() {
        // Have the window title and menu items reflect the display name of the app
        if let displayName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String {
            if let window = self.view.window {
                window.title = displayName
            }
            
            let menu = NSMenu()
            let menuItemOne = NSMenuItem()
            menuItemOne.submenu = NSMenu()
            let aboutItem = NSMenuItem(title: "About \(displayName)",
                                       action: #selector(ViewController.openGithubPage(_:)),
                                       keyEquivalent: "")
            let quitItem = NSMenuItem(title: "Quit \(displayName)",
                                      action: #selector(NSApplication.terminate(_:)),
                                      keyEquivalent: "q")
            menuItemOne.submenu?.items = [aboutItem, NSMenuItem.separator(), quitItem]
            menu.items = [menuItemOne]
            NSApplication.shared.mainMenu = menu
        }
    }
    
    @objc func openGithubPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/trilemma-dev/SwiftAuthorizationSample") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Updates the Installation section of the UI.
    ///
    /// This gets called by the `HelperToolMonitor` when changes occur.
    func updateInstallationStatus(_ status: HelperToolMonitor.InstallationStatus) {
        DispatchQueue.main.async {
            // 8 possible combinations of installation status
            if status.registeredWithLaunchd {
                if status.registrationPropertyListExists {
                    // Registered: yes | Registration file: yes | Helper tool: yes
                    if case .exists(let installedHelperToolVersion) = status.helperToolExecutable {
                        self.installedField.stringValue = "Yes"
                        if self.bundledHelperToolVersion > installedHelperToolVersion {
                            self.installOrUpdateButton.isEnabled = true
                            self.installOrUpdateButton.title = "Update"
                            self.installOrUpdateButton.action = #selector(ViewController.update)
                            let tooltip = "Update helper tool to version \(self.bundledHelperToolVersion.rawValue)"
                            self.installOrUpdateButton.toolTip = tooltip
                        } else {
                            self.installOrUpdateButton.isEnabled = false
                            self.installOrUpdateButton.title = "Update"
                            self.installOrUpdateButton.action = nil
                            let tooltip = "Bundled helper tool version \(self.bundledHelperToolVersion.rawValue) is " +
                                          "not greater than installed version \(installedHelperToolVersion.rawValue)"
                            self.installOrUpdateButton.toolTip = tooltip
                        }
                        self.uninstallButton.isEnabled = true
                        self.versionField.stringValue = installedHelperToolVersion.rawValue
                        self.runButton.isEnabled = true
                    } else { // Registered: yes | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (helper tool missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                } else {
                    // Registered: yes | Registration file: no | Helper tool: yes
                    if case .exists(let installedHelperToolVersion) = status.helperToolExecutable {
                        self.installedField.stringValue = "No (registration file missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = installedHelperToolVersion.rawValue
                        self.runButton.isEnabled = false
                    } else { // Registered: yes | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No (helper tool and registration file missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                }
            } else {
                if status.registrationPropertyListExists {
                    // Registered: no | Registration file: yes | Helper tool: yes
                    if case .exists(let installedHelperToolVersion) = status.helperToolExecutable {
                        self.installedField.stringValue = "No (helper tool and registration file exist)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = installedHelperToolVersion.rawValue
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (registration file exists)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                } else {
                    // Registered: no | Registration file: no | Helper tool: yes
                    if case .exists(let installedHelperToolVersion) = status.helperToolExecutable {
                        self.installedField.stringValue = "No (helper tool exists)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        let tooltip = "Install helper tool version \(self.bundledHelperToolVersion.rawValue)"
                        self.installOrUpdateButton.toolTip = tooltip
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = installedHelperToolVersion.rawValue
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = "Install version \(self.bundledHelperToolVersion.rawValue)"
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                }
            }
        }
    }
    
    /// Attempts to install the helper tool, requiring user authorization.
    @objc func install(_ sender: NSButton) {
        do {
            try PrivilegedHelperManager.shared
                                       .authorizeAndBless(message: "Do you want to install the sample helper tool?")
        } catch AuthorizationError.canceled {
            // No user feedback needed, user canceled
        } catch {
            self.showModal(title: "Install Failed", error: error)
        }
    }
    
    /// Attempts to update the helper tool by having the helper tool perform a self update.
    @objc func update(_ sender: NSButton) {
        self.xpcClient.sendMessage(self.bundledLocation, to: SharedConstants.updateRoute) { response in
            if case .failure(let error) = response {
                switch error {
                    case .connectionInterrupted:
                        break // It's expected the connection is interrupted as part of updating the client
                    default:
                        self.showModal(title: "Update Failed", error: error)
                }
            }
        }
    }
    
    /// Attempts to uninstall the helper tool by having the helper tool uninstall itself.
    @IBAction func uninstall(_ sender: NSButton) {
        self.xpcClient.send(to: SharedConstants.uninstallRoute) { response in
            if case .failure(let error) = response {
                switch error {
                    case .connectionInterrupted:
                        break // It's expected the connection is interrupted as part of uninstalling the client
                    default:
                        self.showModal(title: "Uninstall Failed", error: error)
                }
            }
        }
    }
    
    /// Show a modal to the user. In practice used to communicate an error.
    private func showModal(title: String, error: Error) {
        DispatchQueue.main.async {
            if let window = self.view.window {
                let alert = NSAlert()
                alert.messageText = title
                // Handler error represents an error thrown by a closure registered with the server
                if let error = error as? XPCError, case .handlerError(let handlerError) = error {
                    alert.informativeText = handlerError.localizedDescription
                } else {
                    alert.informativeText = error.localizedDescription
                }
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: window, completionHandler: nil)
                _ = NSApp.runModal(for: window)
            }
        }
    }
    
    /// Requests the helper tool to run the command currently selected in the popup.
    @IBAction func run(_ sender: NSButton) {
        self.outputText.string = "" // Immediately clear the output, response will be returned async
        
        guard let command = commandPopup.selectedItem?.representedObject as? AllowedCommand else {
            fatalError("Command popup contained unexpected item")
        }
        
        let message: AllowedCommandMessage
        if command.requiresAuth {
            // If it hasn't been done yet, define the example right used to self-restrict this command
            do {
                if !(try SharedConstants.exampleRight.isDefined()) {
                    let rules: Set<AuthorizationRightRule> = [CannedAuthorizationRightRules.authenticateAsAdmin]
                    let description = "\(ProcessInfo.processInfo.processName) would like to perform a secure action."
                    try SharedConstants.exampleRight.createOrUpdateDefinition(rules: rules, descriptionKey: description)
                }
            } catch {
                DispatchQueue.main.async {
                    self.outputText.textColor = NSColor.systemRed
                    self.outputText.string = error.localizedDescription
                }
                return
            }
            
            if let authorization = self.authorization {
                message = .authorizedCommand(command, authorization)
            } else {
                do {
                    let authorization = try Authorization()
                    self.authorization = authorization
                    message = .authorizedCommand(command, authorization)
                } catch {
                    DispatchQueue.main.async {
                        self.outputText.textColor = NSColor.systemRed
                        self.outputText.string = error.localizedDescription
                    }
                    return
                }
            }
        } else {
            message = .standardCommand(command)
        }
        
        self.xpcClient.sendMessage(message,
                                   to: SharedConstants.allowedCommandRoute,
                                   withResponse: self.displayAllowedCommandResponse(_:))
    }
    
    /// Displays the response of requesting the helper tool run the command.
    private func displayAllowedCommandResponse(_ result: Result<AllowedCommandReply, XPCError>) {
        DispatchQueue.main.async {
            switch result {
                case let .success(reply):
                    if let standardOutput = reply.standardOutput {
                        self.outputText.textColor = NSColor.textColor
                        self.outputText.string = standardOutput
                    } else if let standardError = reply.standardError {
                        self.outputText.textColor = NSColor.systemRed
                        self.outputText.string = standardError
                    } else {
                        self.outputText.string = ""
                    }
                case let .failure(error):
                    self.outputText.textColor = NSColor.systemRed
                    // Handler error represents an error thrown by a closure registered with the server
                    if case .handlerError(let handlerError) = error {
                        self.outputText.string = handlerError.localizedDescription
                    } else {
                        self.outputText.string = error.localizedDescription
                    }
            }
        }
    }
}
