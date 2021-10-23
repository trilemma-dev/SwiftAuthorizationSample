//
//  ViewController.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-21
//

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet weak var installedField: NSTextField!
    @IBOutlet weak var versionField: NSTextField!
    @IBOutlet weak var uninstallButton: NSButton!
    @IBOutlet weak var installOrUpdateButton: NSButton!
    @IBOutlet weak var commandPopup: NSPopUpButton!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var outputText: NSTextView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    @IBAction func installOrUpdate(_ sender: NSButton) {
        
    }
    
    @IBAction func uninstall(_ sender: NSButton) {
        
    }
    
    @IBAction func run(_ sender: NSButton) {
        
    }
}
