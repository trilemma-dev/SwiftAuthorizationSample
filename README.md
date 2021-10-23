SwiftAuthorizationSample demonstrates how to run privileged operations on macOS using a helper tool managed by launchd.

This sample was created with the expectation that you already have an app and are looking to add a privileged helper
tool in order to perform one or more operations as root. As such this sample is **not** a template and is instead
written in a modular way which should make it easy for you to add portions of this code to your project as desired.

To try out this sample, configure your Developer ID signing certificate and you should be good to go. If you run into
issues it may be because of Xcode compatability issues; this sample was created with Xcode 13.

Read the following sections to learn how you can incorporate portions of this sample into your own project. The source
code of the sample also contains comments throughout.

## macOS Support
This sample targets macOS 10.14.4 and above. If you would like to support pre-10.14.4 versions of macOS, the helper tool
cannot be written in Swift or [Swift 5 Runtime Support for Command Line Tools](https://support.apple.com/kb/DL1998) must
be installed. This is because the helper tool must be a Command Line Tool (not an app bundle) and starting with Swift 5
and Xcode 10.2, Apple made the decision to end support for embedding the Swift runtime into Command Line Tools.

Note: The helper tool, once installed, will **not** be run from inside of your app bundle and so it cannot target any
Swift runtime bundled with your app. (This is unlike XPC Services which may do this.)

All three Swift packages used in this sample target macOS 10.10 and later. The code in the sample itself should
similarly be able to run starting with macOS 10.10. 

## Dependencies
Three Swift frameworks were created specifically for this helper tool use case:

- [Blessed](https://github.com/trilemma-dev/Blessed): Helper tool installation
  - Makes [SMJobBless](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) functionality a
    single function call; no need to directly use Authorization Services
  - Enables advanced use cases with a full implementation of Authorization Services and Service Management
- [SecureXPC](https://github.com/trilemma-dev/SecureXPC): Communication between your app and helper tool
  - Easily send and receive [Codable](https://developer.apple.com/documentation/swift/codable) instances
  - Designed specifically for secure XPC Mach Services communication, which by default has no restrictions
- [EmbeddedPropertyList](https://github.com/trilemma-dev/EmbeddedPropertyList): Embedded property list reader
  - Directly read the info and launchd property lists embedded in the helper tool

Each of these frameworks have their own READMEs as well as full DocC documentation.

##  Installing a Helper Tool
macOS allows apps to indirectly run code as root by installing a privileged helper tool. If you were to directly use
Apple's APIs you'd use the
[Authorization Services](https://developer.apple.com/documentation/security/authorization_services)
framework to have the user authenticate as an admin and then call 
[`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) to perform
the installation. The [Blessed](https://github.com/trilemma-dev/Blessed) framework used by this sample simplifies this
to just one function call.

If this operation succeeds the helper tool will be copied from the `Contents/Library/LaunchServices` directory inside
your app bundle to `/Library/PrivilegedHelperTools/`. Once installed, it managed by
[launchd](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac).

For this operation to succeed, Apple imposes numerous requirements:

1. Your app **must** be signed.
2. The helper tool **must** be signed.
3. The helper tool **must** be located in the `Contents/Library/LaunchServices` directory inside your app's bundle.
4. The filename of the helper tool **should** be reverse-DNS format.
    - If your app has the bundle identifier "com.apple.Mail" then your helper tool **may** have a filename of
      "com.apple.Mail.helper".
5. The helper tool **must** have an embedded launchd property list.
6. The helper tool's embedded launchd property list **must** have an entry with `Label` as the key and the value
   **must** be the filename of the helper tool.
7. The helper tool **must** have an embedded info property list.
8. The helper tool's embedded info property list **must** have an entry with
   [`SMAuthorizedClients`](https://developer.apple.com/documentation/bundleresources/information_property_list/smauthorizedclients)
   as its key and its value **must** be an array of strings. Each string **must** be a
   [code signing requirement](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html).
   Your app **must** satisify at least one of these requirements.
    - Only processes which meet one or more of these requirements may install or update the helper tool. 
    - These requirements are *only* about which processes may install or update the helper tool. They impose no 
      restrictions on which processes can communicate with the helper tool.
9. The helper tool's embedded info property list **must** have an entry with 
   [`CFBundleVersion`](https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleversion)
   as its key and its value **must** be a string matching the format described in `CFBundleVersion`'s documentation.
    - This requirement is *not* documented by Apple, but is enforced.
    - While not documented by Apple, `SMJobBless` will not overwrite an existing installation of a helper tool with one
      that has an equal or lower value for its `CFBundleVersion` entry.
    - Despite Apple requiring the info property list contain a key named `CFBundleVersion`, your helper tool **must**
      be a Command Line Tool and **must not** be a bundle.
10. Your app's Info.plist **must** have an entry with 
      [`SMPrivilegedExecutables`](https://developer.apple.com/documentation/bundleresources/information_property_list/smprivilegedexecutables)
    as its key and its value must be a dictionary. Each dictionary key **must** be a helper tool's filename; for example
    "com.apple.Mail.helper". Each dictionary value **must** be a string representation of a code signing requirement
    that the helper tool satisfies.

### Satisfying These Requirements
While Apple imposes numerous requirements, many of them only need to be configured once. For the remainder, this sample
uses build variables and a custom build script to automate the process. In particular the build script handles:

- The `SMAuthorizedClients` entry differing depending on whether it's a debug or release build
- The `SMPrivilegedExecutables` entry differing depending on whether it's a debug or release build
- Incrementing the helper tool's `CFBundleVersion` so that it can be updated
- Ensuring the `Label` value matches the helper tool's filename

Additionally the build variables, build scripts, and sample code are designed to avoid any duplicative hard coding of
values such. If you follow the pattern used in this sample and ever wanted to change these values, you'd only need to
update them in one place each.

This section walks your through satisfying all of Apple's requirements.

#### 1 & 2. Code Signing
Xcode can automatically code sign for you. If you don't already have an Apple
[Developer ID](https://developer.apple.com/support/developer-id/) you'll need to provision one. If your build process
does not use Xcode for signing as part of the build process you'll likely need to modify the PropertyListModifier.swift
build script.

#### 3. Helper Tool Location

The exact steps for this may differ in future versions of Xcode. As of Xcode 13:

1. Open your project's `xcodeproj` file
2. Select your application's target
3. Switch to the Build Phases tab
4. Create a Copy Files Phase
5. Set the Destination as "Wrapper"
6. Set the Subpath to "Contents/Library/LaunchServices"
7. Add the helper tool product, for example "com.apple.Mail.helper"
8. Make sure "Code Sign on Copy" is checked

#### Build Variables
This sample relies on build variables to satisfy several of these requirements. You will need to set these build
variables in three different places: for the whole project, for the app target, and for the helper tool target.

The sample uses `xcconfig` files; however, you may do this using your `xcodeproj` file's Build Settings sections if you 
prefer. If you would like to use `xcconfig` files, but are unfamiliar with them then read through this
[excellent article by NSHipster](https://nshipster.com/xcconfig/).

For all of the entries needed, see the following `xcconfig` files:

 - Config.xcconfig
 - SwiftAuthorizationApp/AppConfig.xcconfig
 - SwiftAuthorizationHelperTool/HelperToolConfig.xcconfig
 
Note that the setting of identifiers in the project level Config.xcconfig is essential as both build processes needs
access to this information. That is, at build time the app needs to know the identifier for the helper tool and vice
versa.

#### 4. Helper Tool Filename
If you configured the build variables to match the sample, then what you specified as the value for the key
`HELPER_TOOL_BUNDLE_IDENTIFIER` will be used as the filename for the helper tool.

#### 5 & 7. Embedded launchd and Info Property Lists
In the root of the helper tool directory create Info and launchd property list files with no entries. Just creating
these files will *not* result in them being embedded in the helper tool, to do that we need to tell the compiler to
inline the content of these files into the executable. If you configured the build variables to match the sample your
helper tool should have the following build variable configured:
```
OTHER_LDFLAGS = -sectcreate __TEXT __info_plist $(INFOPLIST_FILE) -sectcreate __TEXT __launchd_plist $(LAUNCHDPLIST_FILE)
```

Where `INFOPLIST_FILE` and `LAUNCHDPLIST_FILE` are build variables with values of the paths to the two property list
files you created.

Note: At runtime you can read the info property list as you would from an app bundle, but you cannot do so for the
      launchd property list. Neither of these property lists can be read externally as you would for an app bundle.
      For this reason, the [EmbeddedPropertyList](https://github.com/trilemma-dev/EmbeddedPropertyList) Swift framework
      was created.

#### 6, 8, 9, & 10. Property List Entries
The build script once properly configured will automatically generate these entries for you. The build script relies
on many of the build variables mentioned in the "Build Variables" section above. Make sure those are configured first.

Create a folder for build scripts (or use an existing one) and copy PropertyListModifier.swift to it. In order to be
run as a script the file must have its execute bit set. From a Terminal, running
`chmod 755 PropertyListModifier.swift` on the script will make it world executable.

The following assumes you named that folder "BuildScripts". Now we need to configure your build process to run the
script. The instructions below are applicable for Xcode 13 and may differ in future versions.

In your `xcodeproj` file:

1. Select your app target
2. Switch to the Build Phases tab
3. Add a Run Script Phase which occurs right after Dependencies
4. Set the command to be run as `"${SRCROOT}"/BuildScripts/PropertyListModifier.swift satisfyJobBlessRequirements`

This will add the `SMPrivilegedExecutables` entry to your app's Info.plist each time the app is built either for debug
or release. Because this value will differ depending on the build, you may not want your Info.plist to keep changing and
have these changes committed your repository. To prevent this, you can do the following optional steps:

5. Add a Run Script Phase as the last phase
6. Set the command to be run as `"${SRCROOT}"/BuildScripts/PropertyListModifier.swift cleanupJobBlessRequirements`

This will delete the `SMPrivilegedExecutables` entry from your app's Info.plist at the end of the build process.

Next we'll configure the build script to run for the helper tool:
1. Select your helper tool target
2. Switch to the Build Phases tab
3. Add a Run Script Phase which occurs right after the Dependencies Phase
4. Set the command to be run as
   `"${SRCROOT}"/BuildScripts/PropertyListModifier.swift satisfyJobBlessRequirements autoIncrementVersion`
   
By specifying "satisfyJobBlessRequirements", the script will add the `SMAuthorizedClients` entry to the helper tool's
info property list and the `Label` entry to the launchd property list each time the app is built either for debug or
release. If you do not want these entries to be persisted as part of the Info.plist:

5. Add a Run Script Phase as the last phase
6. Set the command to be run as `"${SRCROOT}"/BuildScripts/PropertyListModifier.swift cleanupJobBlessRequirements`

By specifying "autoIncrementVersion", the script will increment the patch value of the `CFBundleVersion` entry if the 
source code has changed. In order for the script to determine if the source code has changed it creates an entry in your
helper tool's info property list with the `BuildHash` key and a value equal to the SHA256 hash of the helper tool's
source code. In order for the version number to continue autoincrementing you'll need to commit these changes. If you do
not want this autoincrement behavior, do not specify `autoIncrementVersion` as an argument for the build script. 

## Communicating With a Helper Tool
Communication between your app and the helper tool should be thought of as a client server relationship.  Your app
functions as the client and the helper tool as the server. Similarly to communicating with a server over the Internet,
your app does not start or stop the server. While in theory there are multiple ways for your client to communicate with
the server, in practice an XPC Mach Service should be used. Note that while this uses XPC for communication, this does
**not** make the helper tool an XPC Service.

launchd will ensure your helper tool is running if it needs to handle a request. If it was not already running when you
made a request, expect a small amount of initial latency.

Apple provides both C and Objective C APIs for XPC communication. Unfortunately, as of macOS 12 the Objective C API does
not provide a publicly documented way to secure the connection. (See
[this](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac)
Apple Developer Forums discussion on the topic.) Fortunately, since macOS 11 the C API **does** publicly provide this
functionality and there is an undocumented way to achieve the same result on older versions of macOS. The 
[SecureXPC](https://github.com/trilemma-dev/SecureXPC) framework used by this sample is built on top of the C API and 
requires all communication to be secured. It can be automatically configured to use the same code signing requirements
as `SMAuthorizedClients` in the helper tool's info property list. 

Note: While XPC allows for sending certain types of live references such as file descriptors, the SecureXPC framework
does not support this — it only sends serializable data.

### Registering an XPC Mach Server
For the helper tool to be an XPC Mach server, it must register to be one in its launchd property list. The build script
can do this for you automatically be adding the "specifyMachServices" argument. If you want this to be cleaned up at
the end of the build process, then for that Run Script phase add the "cleanupMachServices" argument.

The script will set the service name to be the same as its bundle identifier, which in practice will also be its
filename and the value for `Label`. This is done purely for convenience; there is no requirement the service name use
the  same identifier. Nowhere does the sample app or helper tool code assume they are the same.

### Security in Depth — Limiting Privileged Operations
While SecureXPC is designed to restrict which processes your server handle requests from, there's still the possibility
of exploits. (For example there could be a vulnerability in your app which gets exploited allowing for arbitrary code
execution.) As such it is a best practice to limit what actions your helper tool can do to the absolute bare minimum
required by your app. This way if an exploit exists it limits the damage. In the sample while the helper tool uses
`Process` to run executables as root, it does not honor requests for any arbitrary executable - only those specified in
the `AllowedCommand` enum are run.

## Determining a Helper Tool's Install Status
Apple does not provide an API to determine the install status of a helper tool. However, this can still be achieved. See
SwiftAuthorizationApp/HelperToolMonitor.swift for an example. There are three different components that make up a helper 
tool being installed, it is not purely a yes/no situation. For example the helper tool could be registered with launch
control (the public interface to launchd) and yet the actual helper tool executable may not exist on disk.

## Uninstalling a Helper Tool
Apple does not provide an API to uninstall the helper tool. Their
[stated position](https://developer.apple.com/forums/thread/66821) is, "Users who don’t care won’t notice the leftover
helper." Despite not providing an API, it is *possible* for the helper tool to uninstall itself. See
SwiftAuthorizationHelperTool/Uninstaller.swift for an example of how to do so.

## Updating a Helper Tool
`SMJobBless` and the equivalent convenience version offered by the Blessed framework can with user authorization
manually update an installed helper tool. If your app would like to automatically update the helper tool without
user involvement see SwiftAuthorizationHelperTool/Update.swift for an example of how to do so. Note that this updater
has certain self-imposed restrictions and will not perform an update in all circumstances.

## App Architecture & UI
The sample app's architecture and UI are not meant to serve as examples of how to best build a macOS app. Please
consult other resources for such guidance.

## Other Considerations
While this sample shows one app installing and communicating with one helper tool, the relationship can be many to 
many. An app can install and communicate with arbitrarily many privileged helper tools. A helper tool could be
installed/updated by and communicate with multiple apps.

## Origin
This sample is inspired by Apple's no longer updated
[EvenBetterAuthorizationSample](https://developer.apple.com/library/archive/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html)
written in Objective C. This sample is implemented exclusively in Swift. While Apple's sample has numerous known
[security vulnerabilities](https://theevilbit.github.io/posts/secure_coding_xpc_part1/), this sample has been designed
with security in mind. If you discover a security vulnerability, please open an issue!
