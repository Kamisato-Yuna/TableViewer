import Foundation
@main struct Probe {
 static func main() {
  do {
   let root = Bundle.main.bundleURL
   for (language, expected) in [("en", "Missing connection parameters."), ("zh-Hans", "缺少连接参数。") ] {
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = root.appendingPathComponent("Contents/Helpers/TableViewerShell")
    process.arguments = ["--mongo-shell-worker", "--tableviewer-language", language]
    process.standardInput = input; process.standardOutput = output
    try process.run()
    try input.fileHandleForWriting.write(contentsOf: Data("{\"type\":\"connect\"}\n".utf8))
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard process.terminationStatus == 0, value?["error"] as? String == expected else { throw NSError(domain: "LocalizationProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(language): \(String(decoding: data, as: UTF8.self))"]) }
    print("PASS: signed sandbox worker language \(language)")
   }
  } catch { print("FAIL: \(error)"); exit(1) }
 }
}
