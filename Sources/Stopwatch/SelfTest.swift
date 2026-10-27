import Foundation

enum SelfTest {
    private static var failures: [String] = []
    private static var checks = 0

    static func run(dataDir: URL) {
        testAggregation()
        testStreak()
        testPersistence(dataDir: dataDir)
        testSeatArithmetic(dataDir: dataDir)
        testCrashRecovery(dataDir: dataDir)
        testExport()

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

    private static func testPersistence(dataDir: URL) {
        let dir = dataDir.appendingPathComponent("persistence", isDirectory: true)
        let store = Store(directory: dir)
        expect(store.load() == nil, "a fresh directory should have no snapshot")
        let start = date("2026-10-05T07:30:00")
        let snapshot = Snapshot(version: 1,
                               sessions: [Session(start: start, end: start.addingTimeInterval(1200),
                                                  seconds: 1200)],
                               active: ActiveState(seatStart: start, segmentStart: start,
                                                   bankedSeconds: 45, isRunning: true))
        store.save(snapshot)
        let loaded = store.load()
        expect(loaded?.sessions.count == 1, "session should survive a save/load roundtrip")
        expect(loaded?.sessions.first?.seconds == 1200, "duration should roundtrip exactly")
        expect(loaded?.sessions.first?.start == start, "start date should roundtrip exactly")
        expect(loaded?.active?.bankedSeconds == 45, "in-progress seat should roundtrip")
        expect(loaded?.active?.isRunning == true, "running flag should roundtrip")
        store.deleteAll()
        expect(store.load() == nil, "deleteAll should remove the snapshot")
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

    private static func testExport() {
        let start = date("2026-10-27T06:00:00")
        let session = Session(start: start, end: start.addingTimeInterval(90), seconds: 90)
        let csv = Exporter.csv([session])
        expect(csv.hasPrefix("开始时间,结束时间,时长(秒),时长(分),座次"), "csv needs a header")
        expect(csv.contains("90,1.50,1"), "csv should carry seconds, minutes and seat index, got \(csv)")
        let json = (try? Exporter.json([session])) ?? "[]"
        expect(json.contains("\"seconds\" : 90"), "json should round-trip the duration")
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
