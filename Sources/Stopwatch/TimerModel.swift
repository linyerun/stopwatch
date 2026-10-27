import Foundation
import Combine

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Date
    var end: Date
    var seconds: Int

    init(id: UUID = UUID(), start: Date, end: Date, seconds: Int) {
        self.id = id
        self.start = start
        self.end = end
        self.seconds = seconds
    }
}

struct ActiveState: Codable, Equatable {
    /// When the seat was first begun; stays put across pause/resume.
    var seatStart: Date
    /// Start of the currently running segment, used to accrue chanted seconds.
    var segmentStart: Date
    var bankedSeconds: Int
    var isRunning: Bool
}

struct Snapshot: Codable {
    var version: Int = 1
    var sessions: [Session]
    var active: ActiveState?
}

/// Sessions shorter than this are treated as mis-taps and not recorded.
let minRecordedSeconds = 10

final class Store {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("sessions.json") }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: file)
    }

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
                    sessions: items.sorted { $0.start < $1.start })
        }
        .sorted { $0.day > $1.day }
    }

    static func seconds(_ sessions: [Session], from: Date, through: Date,
                        calendar: Calendar = .current) -> Int {
        sessions.filter {
            calendar.startOfDay(for: $0.start) >= calendar.startOfDay(for: from)
                && calendar.startOfDay(for: $0.start) <= calendar.startOfDay(for: through)
        }
        .reduce(0) { $0 + $1.seconds }
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

}

// MARK: - Model

final class TimerModel: ObservableObject {
    static let shared = TimerModel(directory: TimerModel.defaultDirectory())

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var active: ActiveState?
    /// Bumped once a second while a seat is in progress; views read the clock live.
    @Published private var tick = Date()

    private let store: Store
    private var ticker: AnyCancellable?
    /// Injectable clock so the seat arithmetic is testable without waiting in real time.
    var nowProvider: () -> Date = Date.init

    init(directory: URL) {
        store = Store(directory: directory)
        reload()
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

    var hasSavedData: Bool { store.exists }

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
        persist()
        ensureTicking()
    }

    func pause() {
        guard let active, active.isRunning else { return }
        var updated = active
        updated.bankedSeconds += max(0, Int(nowProvider().timeIntervalSince(updated.segmentStart)))
        updated.isRunning = false
        self.active = updated
        persist()
        stopTicking()
    }

    func resume() {
        guard let active, !active.isRunning else { return }
        var updated = active
        updated.segmentStart = nowProvider()
        updated.isRunning = true
        self.active = updated
        persist()
        ensureTicking()
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
        if seconds >= minRecordedSeconds {
            let session = Session(start: active.seatStart, end: ended, seconds: seconds)
            sessions.append(session)
            recorded = session
        }
        persist()
        return recorded
    }

    /// Abandons the current seat without recording it.
    func discardActive() {
        guard active != nil else { return }
        active = nil
        stopTicking()
        persist()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func deleteDay(_ day: Date) {
        let calendar = Calendar.current
        sessions.removeAll { calendar.startOfDay(for: $0.start) == calendar.startOfDay(for: day) }
        persist()
    }

    func clearAll() {
        sessions = []
        active = nil
        stopTicking()
        store.deleteAll()
    }

    func reload() {
        guard let snapshot = store.load() else { return }
        sessions = snapshot.sessions
        active = repair(snapshot.active)
        if active?.isRunning == true {
            ensureTicking()
        }
    }

    func seed(_ sessions: [Session]) {
        self.sessions = sessions
        persist()
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

    /// An in-progress seat is stored as wall-clock dates, so a clock jump or a
    /// machine sleep can leave the segment starting in the future.
    private func repair(_ state: ActiveState?) -> ActiveState? {
        guard var state, state.segmentStart > nowProvider() else { return state }
        state.segmentStart = nowProvider()
        return state
    }

    private func persist() {
        store.save(Snapshot(version: 1, sessions: sessions, active: active))
    }
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

    static let timeLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}
