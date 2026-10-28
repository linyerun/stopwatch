import Foundation
import Combine

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Date
    var end: Date
    var seconds: Int
    /// 佛号声数, 0 when the seat was timed without tapping.
    var count: Int

    init(id: UUID = UUID(), start: Date, end: Date, seconds: Int, count: Int = 0) {
        self.id = id
        self.start = start
        self.end = end
        self.seconds = seconds
        self.count = count
    }

    private enum CodingKeys: String, CodingKey { case id, start, end, seconds, count }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        seconds = try container.decode(Int.self, forKey: .seconds)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

struct ActiveState: Codable, Equatable {
    /// When the seat was first begun; stays put across pause/resume.
    var seatStart: Date
    /// Start of the currently running segment, used to accrue chanted seconds.
    var segmentStart: Date
    var bankedSeconds: Int
    var isRunning: Bool
    var count: Int

    private enum CodingKeys: String, CodingKey {
        case seatStart, segmentStart, bankedSeconds, isRunning, count
    }

    init(seatStart: Date, segmentStart: Date, bankedSeconds: Int, isRunning: Bool, count: Int = 0) {
        self.seatStart = seatStart
        self.segmentStart = segmentStart
        self.bankedSeconds = bankedSeconds
        self.isRunning = isRunning
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seatStart = try container.decode(Date.self, forKey: .seatStart)
        segmentStart = try container.decode(Date.self, forKey: .segmentStart)
        bankedSeconds = try container.decode(Int.self, forKey: .bankedSeconds)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

/// Sessions shorter than this are treated as mis-taps and not recorded — unless
/// the seat carries counted 佛号, which is never thrown away.
let minRecordedSeconds = 10

/// Where records live; overridable with NIANFO_DATA_DIR for tests and demos.
enum Store {
    static func applicationDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Stopwatch", isDirectory: true)
    }
}

// MARK: - Aggregation

struct DayStat: Identifiable {
    let day: Date
    let seconds: Int
    let count: Int
    let sessions: [Session]
    var id: Date { day }
}

enum Stats {
    static func dayStats(_ sessions: [Session], calendar: Calendar = .current) -> [DayStat] {
        var grouped: [Date: [Session]] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.start)
            grouped[day, default: []].append(s)
        }
        return grouped.map { day, items in
            DayStat(day: day,
                    seconds: items.reduce(0) { $0 + $1.seconds },
                    count: items.reduce(0) { $0 + $1.count },
                    sessions: items.sorted { $0.start < $1.start })
        }
        .sorted { $0.day > $1.day }
    }

    static func seconds(_ sessions: [Session], from: Date, through: Date,
                        calendar: Calendar = .current) -> Int {
        inRange(sessions, from: from, through: through, calendar: calendar)
            .reduce(0) { $0 + $1.seconds }
    }

    static func count(_ sessions: [Session], from: Date, through: Date,
                      calendar: Calendar = .current) -> Int {
        inRange(sessions, from: from, through: through, calendar: calendar)
            .reduce(0) { $0 + $1.count }
    }

    /// Consecutive days with at least one recorded session. A day with no practice
    /// yet does not break the streak as long as yesterday was practiced.
    static func streak(_ sessions: [Session], now: Date = .now,
                       calendar: Calendar = .current) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func inRange(_ sessions: [Session], from: Date, through: Date,
                                calendar: Calendar) -> [Session] {
        sessions.filter {
            calendar.startOfDay(for: $0.start) >= calendar.startOfDay(for: from)
                && calendar.startOfDay(for: $0.start) <= calendar.startOfDay(for: through)
        }
    }
}

// MARK: - Model

final class TimerModel: ObservableObject {
    static let shared = TimerModel(directory: TimerModel.defaultDirectory())

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var active: ActiveState?
    /// Non-nil when a write failed, so the UI can warn instead of losing records quietly.
    @Published private(set) var storageError: String?
    /// Bumped once a second while a seat is in progress; views read the clock live.
    @Published private var tick = Date()

    let database: Database
    private var ticker: AnyCancellable?
    /// Injectable clock so the seat arithmetic is testable without waiting in real time.
    var nowProvider: () -> Date = Date.init

    init(directory: URL) {
        do {
            database = try Database(path: directory.appendingPathComponent("stopwatch.sqlite3").path)
        } catch {
            fatalError("念佛计时无法打开数据库：\(error.localizedDescription)")
        }
        sessions = (try? database.allSessions()) ?? []
        active = repair(try? database.activeSeat())
        importLegacyJSONIfNeeded(directory: directory)
        if active?.isRunning == true {
            ensureTicking()
        }
    }

    static func defaultDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["NIANFO_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Store.applicationDirectory()
    }

    var isRunning: Bool { active?.isRunning ?? false }
    var isPaused: Bool { active != nil && active?.isRunning == false }
    var hasActiveSession: Bool { active != nil }

    var elapsedSeconds: Int {
        guard let active else { return 0 }
        let extra = active.isRunning ? max(0, Int(nowProvider().timeIntervalSince(active.segmentStart))) : 0
        return active.bankedSeconds + extra
    }

    var todaySeconds: Int {
        let now = nowProvider()
        return Stats.seconds(sessions, from: now, through: now)
            + (active != nil ? elapsedSeconds : 0)
    }

    /// 佛号 counted in the current seat.
    var seatCount: Int { active?.count ?? 0 }

    var todayCount: Int {
        let now = nowProvider()
        return Stats.count(sessions, from: now, through: now) + seatCount
    }

    var totalCount: Int { sessions.reduce(0) { $0 + $1.count } }

    /// Recorded 佛号 plus whatever the current seat has tapped so far.
    var lifetimeCount: Int { totalCount + seatCount }

    var totalSeconds: Int { sessions.reduce(0) { $0 + $1.seconds } }
    var streakDays: Int { Stats.streak(sessions, now: nowProvider()) }

    var dayStats: [DayStat] { Stats.dayStats(sessions) }

    var recentSessions: [Session] {
        sessions.sorted { $0.start > $1.start }.prefix(8).map { $0 }
    }

    // MARK: lifecycle

    func start() {
        guard active == nil else { return }
        let now = nowProvider()
        active = ActiveState(seatStart: now, segmentStart: now, bankedSeconds: 0, isRunning: true)
        saveActive()
        ensureTicking()
    }

    func pause() {
        guard let active, active.isRunning else { return }
        var updated = active
        updated.bankedSeconds += max(0, Int(nowProvider().timeIntervalSince(updated.segmentStart)))
        updated.isRunning = false
        self.active = updated
        saveActive()
        stopTicking()
    }

    func resume() {
        guard let active, !active.isRunning else { return }
        var updated = active
        updated.segmentStart = nowProvider()
        updated.isRunning = true
        self.active = updated
        saveActive()
        ensureTicking()
    }

    /// One 南无阿弥陀佛. Begins a seat automatically when idle, so tapping alone is
    /// enough to start a practice record.
    func tap() {
        if active == nil { start() }
        guard var updated = active else { return }
        updated.count += 1
        active = updated
        saveActive()
    }

    /// Ends the current seat and writes it into the history. Returns the recorded
    /// session, or nil when the seat was too short to keep.
    @discardableResult
    func finish() -> Session? {
        guard let active else { return nil }
        let ended = nowProvider()
        let seconds = active.bankedSeconds
            + (active.isRunning ? max(0, Int(ended.timeIntervalSince(active.segmentStart))) : 0)
        self.active = nil
        stopTicking()
        var recorded: Session?
        if seconds >= minRecordedSeconds || active.count > 0 {
            let session = Session(start: active.seatStart, end: ended, seconds: seconds,
                                  count: active.count)
            sessions.append(session)
            recorded = session
            commit { try self.database.insert(session) }
        }
        saveActive()
        return recorded
    }

    /// Abandons the current seat without recording it.
    func discardActive() {
        guard active != nil else { return }
        active = nil
        stopTicking()
        saveActive()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        commit { try self.database.deleteSession(id: session.id) }
    }

    func deleteDay(_ day: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        sessions.removeAll { $0.start >= start && $0.start < end }
        commit { try self.database.deleteSessionsStarted(onOrAfter: start, before: end) }
    }

    func clearAll() {
        sessions = []
        active = nil
        stopTicking()
        commit {
            try self.database.replaceSessions([])
            try self.database.setActive(nil)
        }
    }

    /// Replaces the stored history — used by the demo seed and by tests.
    func seed(_ sessions: [Session]) {
        self.sessions = sessions
        commit { try self.database.replaceSessions(sessions) }
    }

    // MARK: ticking

    /// One-second refresh is only scheduled while a seat is in progress, so an idle
    /// app costs nothing.
    func ensureTicking() {
        guard isRunning else { stopTicking(); return }
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick = Date()
            }
    }

    func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: storage

    private func saveActive() {
        commit { try self.database.setActive(self.active) }
    }

    private func commit(_ write: () throws -> Void) {
        do {
            try write()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
            let line = "念佛计时写入失败：\(error.localizedDescription)\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
    }

    /// An in-progress seat is stored as wall-clock dates, so a clock jump or a
    /// machine sleep can leave the segment starting in the future.
    private func repair(_ state: ActiveState?) -> ActiveState? {
        guard var state, state.segmentStart > nowProvider() else { return state }
        state.segmentStart = nowProvider()
        return state
    }

    /// Builds before SQLite kept everything in sessions.json; move those rows over
    /// once, then remove the file so it is never imported twice.
    private func importLegacyJSONIfNeeded(directory: URL) {
        let legacy = directory.appendingPathComponent("sessions.json")
        guard let data = try? Data(contentsOf: legacy),
              let snapshot = try? JSONDecoder.legacy.decode(LegacySnapshot.self, from: data)
        else { return }
        let fresh = snapshot.sessions.filter { incoming in
            !sessions.contains { $0.id == incoming.id }
        }
        if !fresh.isEmpty {
            sessions.append(contentsOf: fresh)
            commit { try self.database.replaceSessions(self.sessions) }
        }
        if active == nil, let legacyActive = snapshot.active {
            active = repair(legacyActive)
            saveActive()
            if active?.isRunning == true { ensureTicking() }
        }
        try? FileManager.default.removeItem(at: legacy)
    }
}

/// Shape of the pre-SQLite file, kept only so existing records survive the upgrade.
private struct LegacySnapshot: Codable {
    var version: Int
    var sessions: [Session]
    var active: ActiveState?
}

private extension JSONDecoder {
    static let legacy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Formatting

enum TimeFormat {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func compact(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h) 时 \(m) 分" }
        if m > 0 { return "\(m) 分" }
        return "\(s) 秒"
    }

    static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "M月d日 EEE"
        return f
    }()

    static let dateLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }()

    static let timeLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}
