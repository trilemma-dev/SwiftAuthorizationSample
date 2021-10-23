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
        /// Unable to determine the location this code is running from.
        case codeLocationNotRetrievable(OSStatus)
        /// Unable to retrieve the on disk code representation for a specified file URL.
        case externalStaticCodeNotRetrievable(OSStatus)
        /// Unable to retrieve the on disk code representation for this code.
        case helperToolStaticCodeNotRetrievable(OSStatus)
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
        if status == errSecSuccess,
           let path = path as URL? {
            return path
        } else {
            throw CodeInfoError.codeLocationNotRetrievable(status)
        }
    }
    
    /// Determines if the public keys of this helper tool and the executable corresponding to the passed in `URL` match.
    ///
    /// - Parameters:
    ///   - forExecutable: On disk location of an executable.
    /// - Throws: If unable to compare the public keys for the on disk representations of both this helper tool and the executable for the provided URL.
    /// - Returns: If the public keys of their leaf certificates (which is the Developer ID certificate) match.
    static func doesPublicKeyMatch(forExecutable executable: URL) throws -> Bool {
        var matches = false
        
        let currentStaticCode = try copyCurrentStaticCode()
        let otherStaticCode = try createStaticCode(forExecutable: executable)
        
        // Only perform this comparison if the other static code has a valid signature
        let checkFlags = SecCSFlags.init(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        if SecStaticCodeCheckValidity(otherStaticCode, checkFlags, nil) == errSecSuccess {
            let currentKeyData = try copyLeafCertificateKeyData(staticCode: currentStaticCode)
            let otherKeyData = try copyLeafCertificateKeyData(staticCode: otherStaticCode)
            
            matches = (currentKeyData == otherKeyData)
        }
        
        return matches
    }
    
    /// Convenience wrapper around `SecStaticCodeCreateWithPath`.
    ///
    /// - Parameters:
    ///   - forExecutable: On disk location of an executable.
    /// - Throws: If unable to create the static code.
    /// - Returns: Static code instance corresponding to the provided `URL`.
    private static func createStaticCode(forExecutable url: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        if status == errSecSuccess, let staticCode = staticCode {
            return staticCode
        }
        
        throw CodeInfoError.externalStaticCodeNotRetrievable(status)
    }
    
    /// Convenience wrapper around `SecCodeCopySelf` and `SecCodeCopyStaticCode`.
    ///
    /// - Throws: If unable to create a copy of the on disk representation of this code.
    /// - Returns: Static code instance corresponding to the executable running this code.
    private static func copyCurrentStaticCode() throws -> SecStaticCode {
        var currentCode: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &currentCode)
        if status == errSecSuccess, let currentCode = currentCode {
            var currentStaticCode: SecStaticCode?
            let status = SecCodeCopyStaticCode(currentCode, SecCSFlags(), &currentStaticCode)
            if status == errSecSuccess, let currentStaticCode = currentStaticCode {
                return currentStaticCode
            } else {
                throw CodeInfoError.helperToolStaticCodeNotRetrievable(status)
            }
        } else {
            throw CodeInfoError.helperToolStaticCodeNotRetrievable(status)
        }
    }
    
    /// Returns the signing key in data form for the leaf certificate in the certificate chain.
    ///
    /// - Parameters:
    ///  - staticCode: On disk representation of an executable.
    /// - Throws: If unable to copy the data.
    /// - Returns: Signing key in data form for the leaf certificate in the certificate chain.
    private static func copyLeafCertificateKeyData(staticCode: SecStaticCode) throws -> Data {
        // This giant if statement with a bunch of let statements does the following:
        //  - Gets the signing information for the static code which includes the signing certificates
        //  - Finds the leaf certificate which corresponds to a third party Developer ID certificate
        //  - Retrieves the public key from the leaf certificate
        //  - Transforms that public key into a Data instance which can be easily compared
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        if SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
           let info = info as NSDictionary?,
           let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leafCertificate = certificates.first,
           let leafKey = SecCertificateCopyKey(leafCertificate),
           let leafKeyData = SecKeyCopyExternalRepresentation(leafKey, nil) as Data? {
                return leafKeyData
        }
        
        throw CodeInfoError.signingKeyDataNotRetrievable
    }
}
