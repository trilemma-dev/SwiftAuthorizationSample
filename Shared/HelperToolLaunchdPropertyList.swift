//
//  HelperToolLaunchdPropertyList.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-23
//

import Foundation
import EmbeddedPropertyList

/// Read only representation of the helper tool's embedded launchd property list.
struct HelperToolLaunchdPropertyList: Decodable {
    /// Value for `MachServices`.
    let machServices: [String : Bool]
    /// Value for `Label`.
    let label: String
    
    // Used by the decoder to map the names of the entries in the property list to the property names of this struct
    private enum CodingKeys: String, CodingKey {
        case machServices = "MachServices"
        case label = "Label"
    }
    
    /// An immutable in memory representation of the property list by attempting to read it from the helper tool.
    static var main: HelperToolLaunchdPropertyList {
        get throws {
            try PropertyListDecoder().decode(HelperToolLaunchdPropertyList.self,
                                             from: try EmbeddedPropertyListReader.launchd.readInternal())
        }
    }
    
    /// Creates an immutable in memory representation of the property list by attempting to read it from the helper tool.
    ///
    /// - Parameter url: Location of the helper tool on disk.
    init(from url: URL) throws {
        self = try PropertyListDecoder().decode(HelperToolLaunchdPropertyList.self,
                                                from: try EmbeddedPropertyListReader.launchd.readExternal(from: url))
    }
}
