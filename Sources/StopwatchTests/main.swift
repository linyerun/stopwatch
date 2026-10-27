import Foundation

let dataDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("stopwatch-selftest-\(ProcessInfo.processInfo.processIdentifier)",
                            isDirectory: true)
defer { try? FileManager.default.removeItem(at: dataDir) }

SelfTest.run(dataDir: dataDir)
exit(SelfTest.exitCode)
