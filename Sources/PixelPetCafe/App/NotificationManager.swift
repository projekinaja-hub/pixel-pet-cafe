import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for "come back and check"
/// moments (holidays, fresh goals, streak about to lapse).
///
/// IMPORTANT: `UNUserNotificationCenter.current()` CRASHES when the process
/// is not a real app bundle — and this game also runs as a bare debug binary
/// for offscreen screenshot dev-hooks (PPC_SNAPSHOT etc.). So every touch of
/// the notification center is (a) guarded by `available` (bundle identifier
/// present) and (b) reached lazily from method bodies only — never from
/// static/init-time code paths.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// True while the popover is open: the user is already looking at the
    /// game, so posting a system notification would just be noise.
    var suppressed = false

    /// Unbundled (bare `swift run` / debug binary) execution: every method
    /// no-ops so UNUserNotificationCenter is never touched.
    private let available = Bundle.main.bundleIdentifier != nil

    private let promptedDefaultsKey = "ppc.notifications.prompted"

    private init() {}

    /// Requests `.alert, .sound` authorization exactly once per install
    /// (tracked in UserDefaults so we never re-prompt).
    func requestPermissionIfNeeded() {
        guard available else { return }
        guard !UserDefaults.standard.bool(forKey: promptedDefaultsKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedDefaultsKey)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts an immediate notification, replacing any pending one with the
    /// same id. No-ops while `suppressed` (popover open) or unbundled.
    func notify(id: String, title: String, body: String) {
        guard available, !suppressed else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let request = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false))
        center.add(request)
    }
}

/// Pure decision/formatting logic behind the notification triggers — kept
/// free of UserNotifications so it's unit-testable in the bare test runner.
enum NotificationTriggers {
    /// Streak lapse reminder: evenings only (>= 19:00 local), and only when
    /// the player hasn't played *today* (same calendar-day comparison as
    /// `EconomyEngine.updateDailyStreak`) with a streak actually worth saving.
    static func shouldSendStreakReminder(
        now: Date, lastPlayed: Date?, streak: Int, calendar: Calendar = .current
    ) -> Bool {
        guard streak >= 2 else { return false }
        guard calendar.component(.hour, from: now) >= 19 else { return false }
        guard let last = lastPlayed else { return false }  // no streak history — nothing to lose
        return !calendar.isDate(last, inSameDayAs: now)
    }

    /// Streak price bonus as a whole percent, mirroring
    /// `EconomyEngine.dailyStreakMultiplier`.
    static func streakBonusPercent(streak: Int) -> Int {
        let bonus = min(EconomyEngine.dailyStreakBonusCap,
                        EconomyEngine.dailyStreakBonusPerDay * Double(streak))
        return Int((bonus * 100).rounded())
    }

    /// Body line for a holiday-started notification: only mentions the
    /// boosts that are actually active (> 1.0).
    static func holidayBody(_ holiday: Holiday) -> String {
        var parts: [String] = []
        if holiday.priceBoost > 1.0 {
            parts.append("+\(Int(((holiday.priceBoost - 1) * 100).rounded()))% prices")
        }
        if holiday.customerBoost > 1.0 {
            parts.append("+\(Int(((holiday.customerBoost - 1) * 100).rounded()))% customers")
        }
        guard !parts.isEmpty else { return "A special day at the café!" }
        return parts.joined(separator: ", ") + " all day."
    }
}
