import Foundation

enum SelfTest {
    private static var failures: [String] = []
    private static var checks = 0

    static func run(dataDir: URL) {
        testAggregation()
        testStreak()
        do {
            try testPersistence(dataDir: dataDir)
        } catch {
            expect(false, "database test threw: \(error.localizedDescription)")
        }
        testSeatArithmetic(dataDir: dataDir)
        testCrashRecovery(dataDir: dataDir)
        testCounting(dataDir: dataDir)
        testLegacyRecords(dataDir: dataDir)
        testExportImage()

        print("\(checks) checks, \(failures.count) failures")
        for failure in failures { print("FAIL: \(failure)") }
    }

    static var exitCode: Int32 { failures.isEmpty ? 0 : 1 }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures.append(message) }
    }

    // MARK: cases

    private static func testAggregation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day1 = calendar.startOfDay(for: date("2026-10-01T06:00:00", in: calendar))
        let s1 = Session(start: day1, end: day1.addingTimeInterval(900), seconds: 900)
        let s2 = Session(start: day1.addingTimeInterval(3600),
                         end: day1.addingTimeInterval(5400), seconds: 1800)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day1)!
        let s3 = Session(start: nextDay, end: nextDay.addingTimeInterval(600), seconds: 600)

        let stats = Stats.dayStats([s1, s2, s3], calendar: calendar)
        expect(stats.count == 2, "dayStats should merge same-day seats, got \(stats.count)")
        expect(stats.first?.day == nextDay, "dayStats should be newest-first")
        expect(stats.first?.seconds == 600, "newest day should hold 600s, got \(stats.first?.seconds ?? -1)")
        expect(stats.last?.sessions.count == 2, "oldest day should hold 2 seats")
        expect(stats.last?.seconds == 2700, "oldest day should total 2700s")

        let within = Stats.seconds([s1, s2, s3], from: day1, through: day1, calendar: calendar)
        expect(within == 2700, "single-day sum should be 2700s, got \(within)")
        let span = Stats.seconds([s1, s2, s3], from: day1, through: nextDay, calendar: calendar)
        expect(span == 3300, "two-day sum should be 3300s, got \(span)")
    }

    private static func testStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: date("2026-10-27T12:00:00", in: calendar))
        func seat(_ daysBack: Int) -> Session {
            let start = calendar.date(byAdding: .day, value: -daysBack, to: today)!
            return Session(start: start, end: start.addingTimeInterval(600), seconds: 600)
        }

        expect(Stats.streak([], now: today, calendar: calendar) == 0, "empty history has no streak")
        expect(Stats.streak([seat(0), seat(1), seat(2)], now: today, calendar: calendar) == 3,
               "three back-to-back days should streak 3")
        expect(Stats.streak([seat(0), seat(2)], now: today, calendar: calendar) == 1,
               "a gap should stop the streak at today")
        expect(Stats.streak([seat(1), seat(2)], now: today, calendar: calendar) == 2,
               "today without practice should keep yesterday's streak")
        expect(Stats.streak([seat(5)], now: today, calendar: calendar) == 0,
               "an old session should not streak")
    }

    private static func testPersistence(dataDir: URL) throws {
        let dir = dataDir.appendingPathComponent("persistence", isDirectory: true)
        let database = try Database(path: dir.appendingPathComponent("stopwatch.sqlite3").path)
        expect(try database.allSessions().isEmpty, "a fresh database should be empty")

        let start = date("2026-10-05T07:30:00")
        let session = Session(start: start, end: start.addingTimeInterval(1200), seconds: 1200,
                              count: 160)
        try database.insert(session)
        try database.setActive(ActiveState(seatStart: start, segmentStart: start,
                                           bankedSeconds: 45, isRunning: true, count: 7))

        let reopened = try Database(path: dir.appendingPathComponent("stopwatch.sqlite3").path)
        let loaded = try reopened.allSessions()
        expect(loaded.count == 1, "rows should survive reopening the database")
        expect(loaded.first?.id == session.id, "the session id should roundtrip")
        expect(loaded.first?.seconds == 1200, "duration should roundtrip exactly")
        expect(loaded.first?.count == 160, "佛号 count should roundtrip exactly")
        expect(loaded.first?.start == start, "start date should roundtrip to the second")
        expect(try reopened.activeSeat()?.bankedSeconds == 45, "in-progress seat should roundtrip")
        expect(try reopened.activeSeat()?.count == 7, "in-progress taps should roundtrip")

        try reopened.deleteSession(id: session.id)
        expect(try reopened.allSessions().isEmpty, "delete should remove the row")
        try reopened.setActive(nil)
        expect(try reopened.activeSeat() == nil, "clearing the active seat should delete its row")
    }

    private static func testSeatArithmetic(dataDir: URL) {
        let model = TimerModel(directory: dataDir.appendingPathComponent("seat", isDirectory: true))
        var clock = date("2026-10-27T06:00:00")
        model.nowProvider = { clock }

        model.start()
        expect(model.isRunning, "start should put the model into the running state")
        clock = clock.addingTimeInterval(30)
        expect(model.elapsedSeconds == 30, "30s of chanting should read 30, got \(model.elapsedSeconds)")

        model.pause()
        expect(model.isPaused, "pause should hold the seat without recording it")
        clock = clock.addingTimeInterval(70)
        expect(model.elapsedSeconds == 30, "paused time must not count, got \(model.elapsedSeconds)")

        model.resume()
        clock = clock.addingTimeInterval(60)
        expect(model.elapsedSeconds == 90, "resume should continue from the banked 30s")

        let recorded = model.finish()
        expect(recorded?.seconds == 90, "the seat should record 90 chanted seconds")
        expect(recorded?.start == date("2026-10-27T06:00:00"),
               "the seat should start when 开始 was pressed")
        expect(model.sessions.count == 1, "one seat should be stored")
        expect(!model.hasActiveSession, "finish should clear the active seat")
        expect(model.todaySeconds == 90, "today should show the recorded 90s")

        model.start()
        clock = clock.addingTimeInterval(5)
        expect(model.finish() == nil, "a 5s mis-tap should not be recorded")
        expect(model.sessions.count == 1, "the mis-tap must not add a session")

        model.start()
        clock = clock.addingTimeInterval(20)
        model.discardActive()
        expect(!model.hasActiveSession, "discard should drop the seat")
        expect(model.sessions.count == 1, "discard must not record anything")
    }

    private static func testCrashRecovery(dataDir: URL) {
        let dir = dataDir.appendingPathComponent("recovery", isDirectory: true)
        let first = TimerModel(directory: dir)
        var clock = date("2026-10-27T06:00:00")
        first.nowProvider = { clock }
        first.start()
        clock = clock.addingTimeInterval(120)

        let relaunched = TimerModel(directory: dir)
        relaunched.nowProvider = { clock }
        expect(relaunched.hasActiveSession, "an in-progress seat should reload after a quit")
        expect(relaunched.isRunning, "the running flag should reload")
        expect(relaunched.elapsedSeconds == 120,
               "wall-clock resume should show 120s, got \(relaunched.elapsedSeconds)")

        clock = clock.addingTimeInterval(60)
        let past = TimerModel(directory: dir)
        past.nowProvider = { clock }
        expect(past.elapsedSeconds == 180, "a second reload should keep counting from seat start")

        let recorded = past.finish()
        expect(recorded?.seconds == 180, "the recovered seat should record 180s")
    }

    private static func testExportImage() {
        let start = date("2026-10-27T06:00:00")
        let sessions = [Session(start: start, end: start.addingTimeInterval(900), seconds: 900,
                                count: 120)]
        let card = ExportCardView(sessions: sessions).environment(\.colorScheme, .light)
        guard let image = OffscreenRender.image(of: card, width: 760),
              let png = OffscreenRender.png(image) else {
            expect(false, "the export card should render offscreen")
            return
        }
        expect(png.count > 20_000, "the exported picture should carry real pixels, got \(png.count) bytes")
        expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "export should be a PNG")
        expect(image.size.width == 760, "export width should match the request")
        expect(Exporter.suggestedFileName(date: start).hasPrefix("念佛统计-20261027"),
               "the suggested filename should carry the date")
    }

    private static func testCounting(dataDir: URL) {
        let dir = dataDir.appendingPathComponent("counting", isDirectory: true)
        let model = TimerModel(directory: dir)
        var clock = date("2026-10-27T08:00:00")
        model.nowProvider = { clock }

        for _ in 0..<3 { model.tap() }
        expect(model.hasActiveSession, "tapping while idle should open a seat")
        expect(model.seatCount == 3, "three taps should be three 佛号")
        expect(model.todayCount == 3, "today should include the in-progress taps")

        clock = clock.addingTimeInterval(5)
        let kept = model.finish()
        expect(kept?.count == 3, "the seat should carry its count")
        expect(kept?.seconds == 5, "a counted seat keeps its real duration")
        expect(model.sessions.count == 1, "counted taps must survive the mis-tap rule")

        for _ in 0..<beadsPerCycle { model.tap() }
        expect(model.seatCount == beadsPerCycle, "a full mala should count \(beadsPerCycle) 声")
        expect(model.seatCycles == 1, "a full mala is one 圈")
        expect(model.seatCount % beadsPerCycle == 0, "the 圈 counter should reset after 108")

        let reloaded = TimerModel(directory: dir)
        reloaded.nowProvider = { clock }
        expect(reloaded.seatCount == beadsPerCycle, "taps should persist across a relaunch")
        expect(reloaded.totalCount == 3, "only finished seats count toward history")
        expect(reloaded.todayCount == beadsPerCycle + 3, "today should add taps to history")
    }

    private static func testLegacyRecords(dataDir: URL) {
        let dir = dataDir.appendingPathComponent("legacy", isDirectory: true)
        let raw = """
        {"version":1,"sessions":[{"id":"11111111-1111-1111-1111-111111111111","start":"2026-10-20T06:00:00Z","end":"2026-10-20T06:20:00Z","seconds":1200}],"active":null}
        """
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent("sessions.json")
        try? raw.data(using: .utf8)?.write(to: legacy)

        let model = TimerModel(directory: dir)
        expect(model.sessions.count == 1, "sessions.json should be imported into SQLite")
        expect(model.sessions.first?.seconds == 1200, "imported duration should match")
        expect(model.sessions.first?.count == 0, "a missing count field should read as zero")
        expect(!FileManager.default.fileExists(atPath: legacy.path),
               "the imported JSON file should be retired")
        expect((try? model.database.allSessions().count) == 1, "the import should be persisted")

        let reopened = TimerModel(directory: dir)
        expect(reopened.sessions.count == 1, "the import should not duplicate on next launch")
    }

    /// Parses a wall-clock literal in the given calendar's timezone so the tests do
    /// not depend on the machine zone.
    private static func date(_ iso: String, in calendar: Calendar = .current) -> Date {
        let parts = iso.replacingOccurrences(of: "T", with: "-")
            .split(separator: "-")
            .flatMap { $0.split(separator: ":") }
        var components = DateComponents()
        components.year = Int(parts[0])!
        components.month = Int(parts[1])!
        components.day = Int(parts[2])!
        components.hour = Int(parts[3])!
        components.minute = Int(parts[4])!
        components.second = Int(parts[5])!
        components.calendar = calendar
        guard let date = calendar.date(from: components) else {
            preconditionFailure("bad literal date: \(iso)")
        }
        return date
    }
}
