import Foundation
import MetricKit
import os

/// The app's log, readable in Console.app. Paths and screenshot contents stay out of it.
enum Log {
    private static let subsystem = "local.screenshot.app"
    static let files = Logger(subsystem: subsystem, category: "files")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let memory = Logger(subsystem: subsystem, category: "memory")
}

/// Crash and hang reports from macOS, kept in ~/Library/Logs/ScreenShot on this Mac. Nothing is sent anywhere.
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReports()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/ScreenShot", isDirectory: true)
        save(payloads.map { (Int($0.timeStampEnd.timeIntervalSince1970), $0.jsonRepresentation()) }, to: folder)
    }

    func save(_ reports: [(stamp: Int, json: Data)], to folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (i, r) in reports.enumerated() {
                try r.json.write(to: folder.appendingPathComponent("diagnostic-\(r.stamp)-\(i).json"), options: .atomic)
            }
        } catch {
            Log.files.error("Could not save a diagnostic report: \(error.localizedDescription, privacy: .public)")
        }
    }
}
