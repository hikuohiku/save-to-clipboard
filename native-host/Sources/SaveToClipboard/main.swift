import Foundation
import AppKit

// MARK: - Message Types

struct Request: Codable {
    let action: String
    let url: String
    let filename: String?
}

struct Response: Codable {
    let success: Bool
    let message: String?
    let error: String?
    let filename: String?
    let size: Int?
}

// MARK: - Native Messaging Protocol

func readMessage() -> Data? {
    // Read 4-byte message length (little-endian)
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    let lengthRead = fread(&lengthBytes, 1, 4, stdin)

    guard lengthRead == 4 else {
        return nil
    }

    let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) }

    // Read message data
    var messageBytes = [UInt8](repeating: 0, count: Int(length))
    let messageRead = fread(&messageBytes, 1, Int(length), stdin)

    guard messageRead == Int(length) else {
        return nil
    }

    return Data(messageBytes)
}

func sendMessage(_ message: Data) {
    // Send 4-byte message length (little-endian)
    var length = UInt32(message.count)
    _ = withUnsafeBytes(of: &length) { bytes in
        fwrite(bytes.baseAddress, 1, 4, stdout)
    }

    // Send message data
    _ = message.withUnsafeBytes { bytes in
        fwrite(bytes.baseAddress, 1, message.count, stdout)
    }

    fflush(stdout)
}

func sendResponse(_ response: Response) {
    do {
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        sendMessage(data)
    } catch {
        let errorResponse = Response(
            success: false,
            message: nil,
            error: "Failed to encode response: \(error.localizedDescription)",
            filename: nil,
            size: nil
        )
        if let errorData = try? JSONEncoder().encode(errorResponse) {
            sendMessage(errorData)
        }
    }
}

// MARK: - PDF Download and Clipboard

func downloadAndCopyPDF(url: String, filename: String) async throws {
    guard let pdfURL = URL(string: url) else {
        throw NSError(domain: "SaveToClipboard", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid URL: \(url)"
        ])
    }

    // Download PDF
    let (data, response) = try await URLSession.shared.data(from: pdfURL)

    // Verify it's a PDF
    if let httpResponse = response as? HTTPURLResponse {
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "SaveToClipboard", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"
            ])
        }

        // Check content type if available
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           !contentType.contains("pdf") && !contentType.contains("octet-stream") {
            // Warning but don't fail - some servers return wrong content type
            fputs("Warning: Content-Type is not PDF: \(contentType)\n", stderr)
        }
    }

    // Copy to clipboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    // Set PDF data with proper type
    pasteboard.setData(data, forType: .pdf)

    // Also try setting as file promise for better compatibility
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try data.write(to: fileURL)
    pasteboard.writeObjects([fileURL as NSURL])
}

// MARK: - Main

func handleRequest(_ request: Request) async -> Response {
    guard request.action == "copyPdf" else {
        return Response(
            success: false,
            message: nil,
            error: "Unknown action: \(request.action)",
            filename: nil,
            size: nil
        )
    }

    let filename = request.filename ?? "document.pdf"

    do {
        try await downloadAndCopyPDF(url: request.url, filename: filename)

        return Response(
            success: true,
            message: "PDF copied to clipboard successfully",
            error: nil,
            filename: filename,
            size: nil
        )
    } catch {
        return Response(
            success: false,
            message: nil,
            error: error.localizedDescription,
            filename: nil,
            size: nil
        )
    }
}

// MARK: - Configuration

enum BrowserType {
    case chrome
    case firefox
}

struct BrowserInfo {
    let name: String
    let type: BrowserType
    let manifestPath: String
}

/// Get all potential browser manifest locations on macOS
func getBrowserPaths() -> [BrowserInfo] {
    let homeDir = NSHomeDirectory()

    return [
        // Chrome and variants
        BrowserInfo(
            name: "Chrome",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Chrome Beta",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Chrome Dev",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Google/Chrome Dev/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Chrome Canary",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),

        // Microsoft Edge
        BrowserInfo(
            name: "Microsoft Edge",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Microsoft Edge Beta",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Microsoft Edge Beta/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Microsoft Edge Dev",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Microsoft Edge Dev/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Microsoft Edge Canary",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Microsoft Edge Canary/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),

        // Other Chromium-based browsers
        BrowserInfo(
            name: "Brave",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Arc",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Arc/User Data/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Vivaldi",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Vivaldi/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),
        BrowserInfo(
            name: "Chromium",
            type: .chrome,
            manifestPath: "\(homeDir)/Library/Application Support/Chromium/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        ),

        // Firefox
        BrowserInfo(
            name: "Firefox",
            type: .firefox,
            manifestPath: "\(homeDir)/Library/Application Support/Mozilla/NativeMessagingHosts/com.hikuohiku.save_to_clipboard.json"
        )
    ]
}

/// Generate Chrome/Chromium manifest with allowed_origins
func generateChromeManifest(binaryPath: String, extensionIDs: [String]) -> String {
    let origins = extensionIDs.map { "    \"chrome-extension://\($0)/\"" }.joined(separator: ",\n")

    return """
{
  "name": "com.hikuohiku.save_to_clipboard",
  "description": "Native messaging host for Save to Clipboard extension",
  "path": "\(binaryPath)",
  "type": "stdio",
  "allowed_origins": [
\(origins)
  ]
}
"""
}

/// Generate Firefox manifest with allowed_extensions
func generateFirefoxManifest(binaryPath: String, extensionIDs: [String]) -> String {
    let extensions = extensionIDs.map { "    \"\($0)\"" }.joined(separator: ",\n")

    return """
{
  "name": "com.hikuohiku.save_to_clipboard",
  "description": "Native messaging host for Save to Clipboard extension",
  "path": "\(binaryPath)",
  "type": "stdio",
  "allowed_extensions": [
\(extensions)
  ]
}
"""
}

/// Detect unpacked/development extensions from Chrome profiles
/// Scans Chrome profile directories for extensions that use this native messaging host
func detectDevelopmentExtensions() -> [String] {
    let homeDir = NSHomeDirectory()
    let chromeBasePath = "\(homeDir)/Library/Application Support/Google/Chrome"

    var detectedIDs: [String] = []

    // List of common Chrome profile directory names
    let profileNames = ["Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"]

    for profileName in profileNames {
        let extensionsPath = "\(chromeBasePath)/\(profileName)/Extensions"

        // Check if profile exists
        guard FileManager.default.fileExists(atPath: extensionsPath) else {
            continue
        }

        // List all extension directories
        guard let extensionDirs = try? FileManager.default.contentsOfDirectory(atPath: extensionsPath) else {
            continue
        }

        for extensionID in extensionDirs {
            // Skip hidden files and non-extension directories
            guard !extensionID.hasPrefix(".") && extensionID.count == 32 else {
                continue
            }

            let extensionPath = "\(extensionsPath)/\(extensionID)"

            // Find version directories (usually named like "1.0.0_0")
            guard let versionDirs = try? FileManager.default.contentsOfDirectory(atPath: extensionPath) else {
                continue
            }

            // Check each version directory for manifest.json
            for versionDir in versionDirs {
                let manifestPath = "\(extensionPath)/\(versionDir)/manifest.json"

                guard FileManager.default.fileExists(atPath: manifestPath),
                      let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                      let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                    continue
                }

                // Check if this extension uses our native messaging host
                // Look for "com.hikuohiku.save_to_clipboard" in manifest
                if let permissions = manifest["permissions"] as? [String],
                   permissions.contains("nativeMessaging") {

                    // Check optional_permissions too
                    var hasNativeMessaging = true
                    if let optionalPermissions = manifest["optional_permissions"] as? [String] {
                        hasNativeMessaging = hasNativeMessaging || optionalPermissions.contains("nativeMessaging")
                    }

                    // We found a potential match - add this extension ID
                    if hasNativeMessaging && !detectedIDs.contains(extensionID) {
                        detectedIDs.append(extensionID)
                    }
                }
            }
        }
    }

    return detectedIDs
}

func configureExtensionID(_ extensionID: String, devMode: Bool = false) {
    print("🔧 Configuring extension ID: \(extensionID)")
    if devMode {
        print("   [Development mode enabled]")
    }
    print()

    // Collect all extension IDs (provided + auto-detected in dev mode)
    var allExtensionIDs = [extensionID]

    if devMode {
        let detectedIDs = detectDevelopmentExtensions()
        if !detectedIDs.isEmpty {
            print("🔍 Auto-detected development extensions:")
            for id in detectedIDs {
                if !allExtensionIDs.contains(id) {
                    print("   + \(id)")
                    allExtensionIDs.append(id)
                }
            }
            print()
        }
    }

    // Determine binary path - prefer app bundle location
    let appBundlePath = "/Applications/SaveToClipboard.app/Contents/MacOS/SaveToClipboard"
    let fallbackPath = "/usr/local/bin/SaveToClipboard"

    let binaryPath: String
    if FileManager.default.fileExists(atPath: appBundlePath) {
        binaryPath = appBundlePath
        print("📦 Using app bundle binary: \(appBundlePath)")
    } else if FileManager.default.fileExists(atPath: fallbackPath) {
        binaryPath = fallbackPath
        print("📦 Using fallback binary: \(fallbackPath)")
    } else {
        print("❌ Error: Native messaging host binary not found")
        print("   Expected locations:")
        print("   - \(appBundlePath)")
        print("   - \(fallbackPath)")
        return
    }
    print()

    let browsers = getBrowserPaths()
    var successCount = 0
    var createdCount = 0
    var skippedCount = 0

    for browser in browsers {
        let dirPath = (browser.manifestPath as NSString).deletingLastPathComponent

        // Check if browser directory exists (indicates browser is installed)
        let parentDir = (dirPath as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: parentDir) else {
            skippedCount += 1
            continue
        }

        // Create NativeMessagingHosts directory if needed
        if !FileManager.default.fileExists(atPath: dirPath) {
            do {
                try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
                print("   📁 Created directory for \(browser.name)")
            } catch {
                print("   ❌ Failed to create directory for \(browser.name): \(error.localizedDescription)")
                continue
            }
        }

        // Generate manifest based on browser type
        let manifestContent: String
        switch browser.type {
        case .chrome:
            manifestContent = generateChromeManifest(binaryPath: binaryPath, extensionIDs: allExtensionIDs)
        case .firefox:
            manifestContent = generateFirefoxManifest(binaryPath: binaryPath, extensionIDs: allExtensionIDs)
        }

        // Write manifest file
        do {
            let existed = FileManager.default.fileExists(atPath: browser.manifestPath)
            try manifestContent.write(toFile: browser.manifestPath, atomically: true, encoding: .utf8)

            if existed {
                print("   ✅ Updated \(browser.name)")
            } else {
                print("   ✅ Created \(browser.name)")
                createdCount += 1
            }
            successCount += 1
        } catch {
            print("   ❌ Failed to configure \(browser.name): \(error.localizedDescription)")
        }
    }

    print()
    if successCount > 0 {
        print("✅ Configured \(successCount) browser(s)")
        if createdCount > 0 {
            print("   (\(createdCount) new manifest(s) created)")
        }
        print()
        print("🔄 Next steps:")
        print("   1. Reload the extension in your browser")
        print("   2. Test by copying a PDF")
    } else {
        print("⚠️  No browsers found to configure")
        if skippedCount > 0 {
            print("   (\(skippedCount) browser(s) not installed)")
        }
    }
}

// MARK: - Entry Point

@main
struct SaveToClipboardHost {
    static func main() async {
        // Check for command-line arguments
        let args = CommandLine.arguments

        // Handle --configure command (with optional --dev flag)
        if args.count >= 3 && args[1] == "--configure" {
            let extensionID = args[2]
            let devMode = args.contains("--dev")

            // Validate extension ID format (32 lowercase letters)
            let pattern = "^[a-z]{32}$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: extensionID, range: NSRange(extensionID.startIndex..., in: extensionID)) != nil {
                configureExtensionID(extensionID, devMode: devMode)
                exit(0)
            } else {
                print("❌ Invalid extension ID format")
                print("   Expected: 32 lowercase letters (a-z)")
                print("   Received: \(extensionID)")
                exit(1)
            }
        }

        // Handle --help command
        if args.count == 2 && (args[1] == "--help" || args[1] == "-h") {
            print("SaveToClipboard Native Messaging Host")
            print()
            print("Usage:")
            print("  SaveToClipboard --configure EXTENSION_ID [--dev]")
            print("    Configure Chrome extension ID in all browser manifests")
            print("    --dev: Enable development mode (auto-detect unpacked extensions)")
            print()
            print("  SaveToClipboard")
            print("    Run as native messaging host (reads from stdin)")
            print()
            exit(0)
        }

        // Default: Run as native messaging host
        // Read message from stdin
        guard let messageData = readMessage() else {
            let errorResponse = Response(
                success: false,
                message: nil,
                error: "Failed to read message from stdin",
                filename: nil,
                size: nil
            )
            sendResponse(errorResponse)
            exit(1)
        }

        // Decode request
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(Request.self, from: messageData) else {
            let errorResponse = Response(
                success: false,
                message: nil,
                error: "Failed to decode request JSON",
                filename: nil,
                size: nil
            )
            sendResponse(errorResponse)
            exit(1)
        }

        // Handle request
        let response = await handleRequest(request)

        // Send response
        sendResponse(response)

        exit(response.success ? 0 : 1)
    }
}
