//
//  ViewController.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-21
//

import Cocoa
import Blessed

class ViewController: NSViewController {
    
    @IBOutlet weak var installedField: NSTextField!
    @IBOutlet weak var versionField: NSTextField!
    @IBOutlet weak var uninstallButton: NSButton!
    @IBOutlet weak var installOrUpdateButton: NSButton!
    @IBOutlet weak var commandPopup: NSPopUpButton!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var outputText: NSTextView!
    
    private var monitor: HelperToolMonitor?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Output text field
        outputText.font = NSFont.userFixedPitchFont(ofSize: 11)
        
        // Have this button call this target, the function called will differ
        self.installOrUpdateButton.target = self

        // Create monitor that updates UI for: install, uninstall, update, & version info
        if let sharedConstants = (NSApplication.shared.delegate as? AppDelegate)?.sharedConstants {
            let monitor = HelperToolMonitor(constants: sharedConstants)
            self.updateInstallUI(status: monitor.determineStatus())
            monitor.start(changeOccurred: updateInstallUI)
            self.monitor = monitor
        }
    }
    
    func updateInstallUI(status: HelperToolMonitor.InstallationStatus) {
        DispatchQueue.main.async {
            // 8 possible combinations of installation status
            if status.registeredWithLaunchd {
                if status.registrationPropertyListExists {
                    // Registered: yes | Registration file: yes | Helper tool: yes
                    if status.helperToolExists {
                        self.installedField.stringValue = "Yes"
                        // TODO: disable update button when no update is available
                        self.installOrUpdateButton.title = "Update"
                        self.installOrUpdateButton.action = #selector(ViewController.update)
                        self.uninstallButton.isEnabled = true
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = true
                    } else { // Registered: yes | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (helper tool missing)"
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
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: yes | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No (helper tool and registration file missing)"
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
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
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: yes | Helper tool: no
                        self.installedField.stringValue = "No (registration file exists)"
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                } else {
                    // Registered: no | Registration file: no | Helper tool: yes
                    if status.registrationPropertyListExists {
                        self.installedField.stringValue = "No (helper tool exists)"
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = status.helperToolBundleVersion?.rawValue ?? "unknown"
                        self.runButton.isEnabled = false
                    } else { // Registered: no | Registration file: no | Helper tool: no
                        self.installedField.stringValue = "No"
                        self.installOrUpdateButton.title = "Install"
                        self.installOrUpdateButton.action = #selector(ViewController.install)
                        self.uninstallButton.isEnabled = false
                        self.versionField.stringValue = "—"
                        self.runButton.isEnabled = false
                    }
                }
            }
        }
    }
    
    @objc func install(_ sender: NSButton) {
        do {
            try LaunchdManager.authorizeAndBless(message: "Do you want to install the sample helper tool?")
        } catch {
            print("error: \(error)")
        }
    }
    
    @objc func update(_ sender: NSButton) {
        print("update")
    }
    
    @IBAction func uninstall(_ sender: NSButton) {
        
    }
    
    @IBAction func run(_ sender: NSButton) {
        
    }
}
