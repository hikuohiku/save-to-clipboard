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

func configureExtensionID(_ extensionID: String) {
    let browserDirs = [
        "Chrome": NSHomeDirectory() + "/Library/Application Support/Google/Chrome/NativeMessagingHosts",
        "Edge": NSHomeDirectory() + "/Library/Application Support/Microsoft Edge/NativeMessagingHosts",
        "Brave": NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
        "Arc": NSHomeDirectory() + "/Library/Application Support/Arc/User Data/NativeMessagingHosts"
    ]

    let binaryPath = "/usr/local/bin/SaveToClipboard"
    var updatedCount = 0

    print("🔧 Configuring extension ID: \(extensionID)")
    print()

    for (browser, dir) in browserDirs {
        let manifestPath = dir + "/com.example.save_to_clipboard.json"

        // Check if manifest exists
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            continue
        }

        let manifestContent = """
{
  "name": "com.example.save_to_clipboard",
  "description": "Native messaging host for Save to Clipboard extension",
  "path": "\(binaryPath)",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://\(extensionID)/"
  ]
}
"""

        do {
            try manifestContent.write(toFile: manifestPath, atomically: true, encoding: .utf8)
            print("   ✅ Updated \(browser)")
            updatedCount += 1
        } catch {
            print("   ❌ Failed to update \(browser): \(error.localizedDescription)")
        }
    }

    print()
    if updatedCount > 0 {
        print("✅ Updated \(updatedCount) browser manifest(s)")
        print()
        print("🔄 Next steps:")
        print("   1. Reload the extension in your browser")
        print("   2. Test by copying a PDF")
    } else {
        print("⚠️  No manifests found to update")
        print("   Make sure SaveToClipboard.pkg was installed first")
    }
}

// MARK: - Entry Point

@main
struct SaveToClipboardHost {
    static func main() async {
        // Check for command-line arguments
        let args = CommandLine.arguments

        // Handle --configure command
        if args.count == 3 && args[1] == "--configure" {
            let extensionID = args[2]

            // Validate extension ID format (32 lowercase letters)
            let pattern = "^[a-z]{32}$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: extensionID, range: NSRange(extensionID.startIndex..., in: extensionID)) != nil {
                configureExtensionID(extensionID)
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
            print("  SaveToClipboard --configure EXTENSION_ID")
            print("    Configure Chrome extension ID in all browser manifests")
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
