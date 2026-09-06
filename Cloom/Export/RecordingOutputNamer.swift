import Foundation

enum RecordingOutputNamer {
    static func availableURL(
        in directory: URL,
        date: Date = .now,
        fileManager: FileManager = .default
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Cloom \(formatter.string(from: date))"
        var candidate = directory.appending(path: stem).appendingPathExtension("mp4")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem) \(suffix)").appendingPathExtension("mp4")
            suffix += 1
        }
        return candidate
    }
}
