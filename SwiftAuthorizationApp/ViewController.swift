//
//  ViewController.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-21
//

import Cocoa
import Blessed
import SecureXPC
import EmbeddedPropertyList

class ViewController: NSViewController {
    
    // Defined in the Storyboard
    @IBOutlet weak var installedField: NSTextField!
    @IBOutlet weak var versionField: NSTextField!
    @IBOutlet weak var uninstallButton: NSButton!
    @IBOutlet weak var installOrUpdateButton: NSButton!
    @IBOutlet weak var commandPopup: NSPopUpButton!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var outputText: NSTextView!
    
    /// Monitors the helper tool, if installed.
    private var monitor: HelperToolMonitor?
    /// The version of the helper tool bundled with this app (not necessarily the version installed).
    private var bundledHelperToolVersion: Version?
    /// Used to communicate with the helper tool.
    private var xpcClient: XPCMachClient?
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

        // Create monitor that updates UI for: install, uninstall, update, & version info
        if let sharedConstants = (NSApplication.shared.delegate as? AppDelegate)?.sharedConstants {
            let monitor = HelperToolMonitor(constants: sharedConstants)
            self.updateInstallationStatus(monitor.determineStatus())
            monitor.start(changeOccurred: updateInstallationStatus)
            self.monitor = monitor
            
            self.xpcClient = XPCMachClient(machServiceName: sharedConstants.machServiceName)
            
            if let bundledLocation = sharedConstants.bundledLocation {
                self.bundledHelperToolVersion = try? HelperToolInfoPropertyList(from: bundledLocation).version
            }
        }
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
            let printDiagnosticInfoItem = NSMenuItem(title: "Print Diagnostic Info",
                                                     action: #selector(ViewController.printDiagnosticInfo(_:)),
                                                     keyEquivalent: "")
            let quitItem = NSMenuItem(title: "Quit \(displayName)",
                                      action: #selector(NSApplication.terminate(_:)),
                                      keyEquivalent: "q")
            menuItemOne.submenu?.items = [aboutItem,
                                          NSMenuItem.separator(),
                                          printDiagnosticInfoItem,
                                          NSMenuItem.separator(),
                                          quitItem]
            menu.items = [menuItemOne]
            NSApplication.shared.mainMenu = menu
        }
    }
    
    @objc func openGithubPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/trilemma-dev/SwiftAuthorizationSample") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func printDiagnosticInfo(_ sender: Any?) {
        DiagnosticSigningInfo.printDiagnosticInfo()
    }
    
    /// Updates the Installation section of the UI.
    ///
    /// This gets called by the HelperToolMonitor when changes occur.
    func updateInstallationStatus(_ status: HelperToolMonitor.InstallationStatus) {
        DispatchQueue.main.async {
            // 8 possible combinations of installation status
            if status.registeredWithLaunchd {
                if status.registrationPropertyListExists {
                    // Registered: yes | Registration file: yes | Helper tool: yes
                    if status.helperToolExists {
                        self.installedField.stringValue = "Yes"
                        if let installedVersion = status.helperToolBundleVersion,
                           let bundledVersion = self.bundledHelperToolVersion {
                            if bundledVersion > installedVersion {
                                self.installOrUpdateButton.isEnabled = true
                                self.installOrUpdateButton.title = "Update"
                                self.installOrUpdateButton.action = #selector(ViewController.update)
                                let tooltip = "Update to bundled helper tool version \(bundledVersion.rawValue)"
                                self.installOrUpdateButton.toolTip = tooltip
                            } else {
                                self.installOrUpdateButton.isEnabled = false
                                self.installOrUpdateButton.title = "Update"
                                self.installOrUpdateButton.action = nil
                                let tooltip = "Bundled helper tool version \(bundledVersion.rawValue) is not greater " +
                                              "than installed version"
                                self.installOrUpdateButton.toolTip = tooltip
                            }
                        } else {
                            self.installOrUpdateButton.title = "Install"
                            self.installOrUpdateButton.action = #selector(ViewController.install)
                            self.installOrUpdateButton.toolTip = nil
                        }
                        self.uninstallButton.isEnabled = true
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = true
                    } else { // Registered: yes | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (helper tool missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                } else {
                    // Registered: yes | Registration file: no | Helper tool: yes
                    if status.helperToolExists {
                        self.installedField.stringValue = "No (registration file missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: yes | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No (helper tool and registration file missing)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                }
            } else {
                if status.registrationPropertyListExists {
                    // Registered: no | Registration file: yes | Helper tool: yes
                    if status.helperToolExists {
                        self.installedField.stringValue = "No (helper tool and registration file exist)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (registration file exists)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                } else {
                    // Registered: no | Registration file: no | Helper tool: yes
                    if status.helperToolExists {
                        self.installedField.stringValue = "No (helper tool exists)"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No"
                        self.installOrUpdateButton.isEnabled = true
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.installOrUpdateButton.toolTip = nil
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
            try LaunchdManager.authorizeAndBless(message: "Do you want to install the sample helper tool?")
        } catch AuthorizationError.canceled {
            // No user feedback needed, user canceled
        } catch {
            self.showModal(title: "Install Failed", message: String(describing: error))
        }
    }
    
    /// Attempts to update the helper tool by having the helper tool perform a self update.
    @objc func update(_ sender: NSButton) {
        if let xpcClient = xpcClient,
           let sharedConstants = (NSApplication.shared.delegate as? AppDelegate)?.sharedConstants,
           let bundledLocation = sharedConstants.bundledLocation {
            do {
                try xpcClient.sendMessage(bundledLocation, route: SharedConstants.updateRoute)
            } catch {
                self.showModal(title: "Update Failed", message: String(describing: error))
            }
        } else {
            self.showModal(title: "Update Failed", message: "Could not communicate with helper tool")
        }
    }
    
    /// Attempts to uninstall the helper tool by having the helper tool uninstall itself.
    @IBAction func uninstall(_ sender: NSButton) {
        if let xpcClient = xpcClient {
            do {
                try xpcClient.send(route: SharedConstants.uninstallRoute)
            } catch {
                self.showModal(title: "Uninstall Failed", message: String(describing: error))
            }
        } else {
            self.showModal(title: "Uninstall Failed", message: "Could not communicate with helper tool")
        }
    }
    
    /// Show a modal to the user. In practice used to communicate an error.
    private func showModal(title: String, message: String) {
        if let window = self.view.window {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window, completionHandler: nil)
            _ = NSApp.runModal(for: window)
        }
    }
    
    /// Requests the helper tool to run the command currently selected in the popup.
    @IBAction func run(_ sender: NSButton) {
        self.outputText.string = "" // Immediately clear the output, response to shown will be returned async
        
        if let command = commandPopup.selectedItem?.representedObject as? AllowedCommand,
           let xpcClient = self.xpcClient {
            do {
                if command.requiresAuth && self.authorization == nil {
                    self.authorization = try Authorization()
                }
                try xpcClient.sendMessage(AllowedCommandMessage(command: command, authorization: self.authorization),
                                          route: SharedConstants.allowedCommandRoute,
                                          withReply: displayAllowedCommandResponse(_:))
            } catch {
                DispatchQueue.main.async {
                    self.outputText.textColor = NSColor.systemRed
                    self.outputText.string = String(describing: error)
                }
            }
        } else {
            self.outputText.textColor = NSColor.systemRed
            self.outputText.string = "Unable to communicate with helper tool"
        }
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
                    if case let .remote(description) = error {
                        self.outputText.string = description
                    } else {
                        self.outputText.string = String(describing: error)
                    }
            }
        }
    }
}
