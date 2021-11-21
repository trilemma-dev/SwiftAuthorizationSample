//
//  DiagnosticSigningInfo.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-11-21
//

import Foundation

// You should not ship this as part of your app, this exists only to provide diagnostic information to assist in
// diagnosing code signing related issues

private enum DiagnosticSigningInfoError: Error {
    case appInfoNotDeterminable
    case helperToolNotFound
    case commonNameNotRetrievable(OSStatus)
    case organizationalUnitNotRetrievable
}

enum DiagnosticSigningInfo {
    static func printDiagnosticInfo() {
        print("\n==============This App=============")
        do {
            print(try infoForThisApp())
        } catch {
            print(error)
        }
        
        print("\n========Bundled Helper Tool========")
        do {
            let constants = try SharedConstants(caller: .app)
            print(try infoForHelperTool(location: constants.bundledLocation))
        } catch {
            print(error)
        }
        
        print("\n=======Installed Helper Tool=======")
        do {
            let constants = try SharedConstants(caller: .app)
            print(try infoForHelperTool(location: constants.blessedLocation))
        } catch DiagnosticSigningInfoError.helperToolNotFound {
            print("Helper tool is not installed")
        }
        catch {
            print(error)
        }
    }

    private static func infoForThisApp() throws -> String {
        guard let infoDictionary = Bundle.main.infoDictionary,
              let identifier = infoDictionary[kCFBundleIdentifierKey as String],
              let version = infoDictionary[kCFBundleVersionKey as String] else {
            throw DiagnosticSigningInfoError.appInfoNotDeterminable
        }
        let staticCodeInfo = try infoForStaticCode(CodeInfo.copyCurrentStaticCode())
        let info = "\(kCFBundleIdentifierKey as String): \(identifier)\n" +
                   "\(kCFBundleVersionKey as String): \(version)\n" +
                   staticCodeInfo
        
        return info
    }

    private static func infoForHelperTool(location: URL?) throws -> String {
        guard let location = location,
              FileManager.default.fileExists(atPath: location.path) else {
            throw DiagnosticSigningInfoError.helperToolNotFound
        }
        
        let infoPropertyList = try HelperToolInfoPropertyList.init(from: location)
        let staticCodeInfo = try infoForStaticCode(CodeInfo.createStaticCode(forExecutable: location))
        let info = "\(kCFBundleIdentifierKey as String): \(infoPropertyList.bundleIdentifier)\n" +
                   "\(kCFBundleVersionKey as String): \(infoPropertyList.version.rawValue)\n" +
                   staticCodeInfo
        
        return info
    }

    private static func infoForStaticCode(_ staticCode: SecStaticCode) throws -> String {
        let leafCertificate = try CodeInfo.copyLeafCertificate(staticCode: staticCode)
        let commonName = try copyCommonName(leafCertificate)
        let organizationalUnit = try copyOrganizationalUnit(leafCertificate)
        let info = "Common Name: \(commonName)\n" +
                   "Organizational Unit: \(organizationalUnit)"
        
        return info
    }

    /// Wrapper around public function `SecCertificateCopyCommonName`.
    private static func copyCommonName(_ certificate: SecCertificate) throws -> String {
        var commonName: CFString?
        let errorCode = SecCertificateCopyCommonName(certificate, &commonName)
        guard let commonName = commonName as String?, errorCode == errSecSuccess else {
            throw DiagnosticSigningInfoError.commonNameNotRetrievable(errorCode)
        }
        
        return commonName
    }

    /// Calls private function `SecCertificateCopyOrganizationalUnit`.
    ///
    /// In practice when called for a Developer ID app this is expected to return the team id.
    private static func copyOrganizationalUnit(_ certificate: SecCertificate) throws -> String {
        // Attempt to dynamically load the function
        if let handle = dlopen(nil, RTLD_LAZY) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "SecCertificateCopyOrganizationalUnit") {
                typealias functionSignature = @convention(c) (SecCertificate) -> CFArray
                let function = unsafeBitCast(sym, to: functionSignature.self)
                
                // Call the function
                if let result = function(certificate) as? [String],
                   result.count == 1,
                   let firstValue = result.first {
                    return firstValue
                }
            }
        }
        
        throw DiagnosticSigningInfoError.organizationalUnitNotRetrievable
    }
}
