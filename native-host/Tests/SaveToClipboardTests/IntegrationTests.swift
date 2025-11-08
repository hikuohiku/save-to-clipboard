import Testing
import Foundation

@Suite("Native Messaging Integration Tests")
struct IntegrationTests {

    let binaryPath: String

    init() throws {
        // Find the built binary
        let debugPath = ".build/debug/SaveToClipboard"
        let releasePath = ".build/release/SaveToClipboard"

        if FileManager.default.fileExists(atPath: releasePath) {
            binaryPath = releasePath
        } else if FileManager.default.fileExists(atPath: debugPath) {
            binaryPath = debugPath
        } else {
            throw TestError.binaryNotFound
        }
    }

    @Test("Help command should display usage")
    func testHelpCommand() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        #expect(output.contains("SaveToClipboard Native Messaging Host"))
        #expect(output.contains("Usage:"))
        #expect(process.terminationStatus == 0)
    }

    @Test("Invalid extension ID should fail")
    func testInvalidExtensionID() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--configure", "invalid"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)

        // Check both stdout and stderr
        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: stdoutData, encoding: .utf8) ?? "") +
                     (String(data: stderrData, encoding: .utf8) ?? "")
        #expect(output.contains("Invalid extension ID format"))
    }

    @Test("Valid extension ID format should be accepted")
    func testValidExtensionIDFormat() async throws {
        // 32 lowercase letters
        let validID = "abcdefghijklmnopqrstuvwxyzabcdef"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--configure", validID]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Should attempt to configure (might not find manifests, but ID is valid)
        #expect(output.contains("Configuring extension ID") || output.contains("No manifests found"))
    }

    @Test("Native messaging protocol - copyPdf action")
    func testNativeMessagingProtocol() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        // Prepare message
        let message: [String: Any] = [
            "action": "copyPdf",
            "url": "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf",
            "filename": "test.pdf"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)

        // Write message with 4-byte length prefix (little-endian)
        var length = UInt32(jsonData.count).littleEndian
        let lengthData = Data(bytes: &length, count: 4)

        try process.run()

        // Send message
        inputPipe.fileHandleForWriting.write(lengthData)
        inputPipe.fileHandleForWriting.write(jsonData)
        try inputPipe.fileHandleForWriting.close()

        // Read response
        let responseData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        // Parse response (skip 4-byte length prefix)
        guard responseData.count > 4 else {
            throw TestError.invalidResponse
        }

        let responseJSON = responseData.dropFirst(4)
        let response = try JSONSerialization.jsonObject(with: responseJSON) as? [String: Any]

        #expect(response != nil)
        if let success = response?["success"] as? Bool {
            #expect(success == true)
        }
        if let message = response?["message"] as? String {
            #expect(message.contains("clipboard"))
        }
    }

    @Test("Unknown action should return error")
    func testUnknownAction() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        // Message with unknown action
        let message: [String: Any] = [
            "action": "unknownAction",
            "url": "https://example.com/test.pdf"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)

        var length = UInt32(jsonData.count).littleEndian
        let lengthData = Data(bytes: &length, count: 4)

        try process.run()

        inputPipe.fileHandleForWriting.write(lengthData)
        inputPipe.fileHandleForWriting.write(jsonData)
        try inputPipe.fileHandleForWriting.close()

        let responseData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard responseData.count > 4 else {
            throw TestError.invalidResponse
        }

        let responseJSON = responseData.dropFirst(4)
        let response = try JSONSerialization.jsonObject(with: responseJSON) as? [String: Any]

        #expect(response != nil)
        if let success = response?["success"] as? Bool {
            #expect(success == false)
        }
        if let error = response?["error"] as? String {
            #expect(error.contains("Unknown action"))
        }
    }
}

enum TestError: Error {
    case binaryNotFound
    case invalidResponse
}
