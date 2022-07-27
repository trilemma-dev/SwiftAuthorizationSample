//
//  CodeInfo.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-24
//

import Foundation

/// Convenience wrappers around Security framework functionality.
enum CodeInfo {
    /// Errors that may occur when trying to determine information about this running helper tool or another on disk executable.
    enum CodeInfoError: Error {
        /// Unable to determine the location of the executable.
        case codeLocationNotRetrievable(OSStatus)
        /// Unable to retrieve the on disk code representation for a specified file URL.
        case externalStaticCodeNotRetrievable(OSStatus)
        /// Unable to retrieve the on disk code representation for this code.
        case helperToolStaticCodeNotRetrievable(OSStatus)
        /// Unable to retrieve the leaf certificate for a code instance.
        case leafCertificateNotRetrievable
        /// Unable to retrieve the signing key information for the provided on disk code representation.
        case signingKeyDataNotRetrievable
    }
    
    /// Returns the on disk location this code is running from.
    ///
    /// - Throws: If unable to determine location.
    /// - Returns: On disk location of this helper tool.
    static func currentCodeLocation() throws -> URL {
        var path: CFURL?
        let status = SecCodeCopyPath(try copyCurrentStaticCode(), SecCSFlags(), &path)
        guard status == errSecSuccess, let path = path as URL? else {
            throw CodeInfoError.codeLocationNotRetrievable(status)
        }
        
        return path
    }
    
    /// Determines if the public keys of this helper tool and the executable corresponding to the passed in `URL` match.
    ///
    /// - Parameter executable: On disk location of an executable.
    /// - Throws: If unable to compare the public keys for the on disk representations of both this helper tool and the executable for the provided URL.
    /// - Returns: If the public keys of their leaf certificates (which is the Developer ID certificate) match.
    static func doesPublicKeyMatch(forExecutable executable: URL) throws -> Bool {
        // Only perform this comparison if the executable's static code has a valid signature
        let executableStaticCode = try createStaticCode(forExecutable: executable)
        let checkFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(executableStaticCode, checkFlags, nil) == errSecSuccess else {
            return false
        }
        
        let currentKeyData = try copyLeafCertificateKeyData(staticCode: try copyCurrentStaticCode())
        let executableKeyData = try copyLeafCertificateKeyData(staticCode: executableStaticCode)
        
        return currentKeyData == executableKeyData
    }
    
    /// Convenience wrapper around `SecStaticCodeCreateWithPath`.
    ///
    /// - Parameter executable: On disk location of an executable.
    /// - Throws: If unable to create the static code.
    /// - Returns: Static code instance corresponding to the provided `URL`.
    static func createStaticCode(forExecutable executable: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(executable as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let staticCode = staticCode else {
            throw CodeInfoError.externalStaticCodeNotRetrievable(status)
        }
        
        return staticCode
    }
    
    /// Convenience wrapper around `SecCodeCopySelf` and `SecCodeCopyStaticCode`.
    ///
    /// - Throws: If unable to create a copy of the on disk representation of this code.
    /// - Returns: Static code instance corresponding to the executable running this code.
    static func copyCurrentStaticCode() throws -> SecStaticCode {
        var currentCode: SecCode?
        let copySelfStatus = SecCodeCopySelf(SecCSFlags(), &currentCode)
        guard copySelfStatus == errSecSuccess, let currentCode = currentCode else {
            throw CodeInfoError.helperToolStaticCodeNotRetrievable(copySelfStatus)
        }
        
        var currentStaticCode: SecStaticCode?
        let staticCodeStatus = SecCodeCopyStaticCode(currentCode, SecCSFlags(), &currentStaticCode)
        guard staticCodeStatus == errSecSuccess, let currentStaticCode = currentStaticCode else {
            throw CodeInfoError.helperToolStaticCodeNotRetrievable(staticCodeStatus)
        }
        
        return currentStaticCode
    }
    
    /// Returns the leaf certificate in the code's certificate chain.
    ///
    /// For a Developer ID signed app, this practice this corresponds to the Developer ID certificate.
    ///
    /// - Parameter staticCode: On disk representation.
    /// - Throws: If unable to determine the certificate.
    /// - Returns: The leaf certificate.
    static func copyLeafCertificate(staticCode: SecStaticCode) throws -> SecCertificate {
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
           let info = info as NSDictionary?,
           let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leafCertificate = certificates.first else {
            throw CodeInfoError.leafCertificateNotRetrievable
        }
        
        return leafCertificate
    }
    
    /// Returns the signing key in data form for the leaf certificate in the certificate chain.
    ///
    /// - Parameter staticCode: On disk representation.
    /// - Throws: If unable to copy the data.
    /// - Returns: Signing key in data form for the leaf certificate in the certificate chain.
    private static func copyLeafCertificateKeyData(staticCode: SecStaticCode) throws -> Data {
        guard let leafKey = SecCertificateCopyKey(try copyLeafCertificate(staticCode: staticCode)),
              let leafKeyData = SecKeyCopyExternalRepresentation(leafKey, nil) as Data? else {
            throw CodeInfoError.signingKeyDataNotRetrievable
        }
        
        return leafKeyData
    }
}
