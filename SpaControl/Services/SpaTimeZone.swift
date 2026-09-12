import Foundation

/// Converts the phone's timezone into the POSIX `TZ` form the spa controller
/// needs, so a tub learns where it is from whoever sets it up.
///
/// Why not just send `TimeZone.current.identifier`? Because the controller is an
/// ESP32 and newlib there carries no timezone database — it would accept
/// "America/New_York" without complaint and then ignore it, leaving a clock that
/// is confidently wrong. POSIX `TZ` strings carry the rules inline:
///
///     EST5EDT,M3.2.0,M11.1.0
///     │  │ │  └ DST ends: month 11, week 1, Sunday
///     │  │ └── DST abbreviation
///     │  └──── hours to ADD to local to reach UTC — the sign is inverted
///     └─────── standard abbreviation
///
/// The rules are derived from Foundation's own transition data rather than a
/// lookup table, so anywhere iOS knows about is handled, including zones that do
/// not observe DST and those on half-hour offsets.
enum SpaTimeZone {

    /// The POSIX `TZ` string for a timezone, e.g. `EST5EDT,M3.2.0,M11.1.0`.
    static func posixString(for tz: TimeZone = .current, now: Date = Date()) -> String {
        let stdNow = tz.secondsFromGMT(for: now)

        // No upcoming transition means the zone does not observe DST (or has
        // stopped). One fixed offset is the whole story.
        guard let t1 = tz.nextDaylightSavingTimeTransition(after: now),
              let t2 = tz.nextDaylightSavingTimeTransition(after: t1) else {
            return abbreviation(tz, now) + offset(stdNow)
        }

        // Which of the two transitions starts DST, and which ends it.
        let startsDSTFirst = tz.isDaylightSavingTime(for: t1.addingTimeInterval(3600))
        let stdRef = startsDSTFirst ? t1.addingTimeInterval(-3600) : t1.addingTimeInterval(3600)
        let dstRef = startsDSTFirst ? t1.addingTimeInterval(3600) : t1.addingTimeInterval(-3600)

        let stdOff = tz.secondsFromGMT(for: stdRef)
        let dstOff = tz.secondsFromGMT(for: dstRef)

        // A zone can have transitions that are not DST at all (a permanent
        // offset change). Treat equal offsets as "no DST" rather than emitting a
        // rule that means nothing.
        guard stdOff != dstOff else {
            return abbreviation(tz, now) + offset(stdNow)
        }

        let dstStart = startsDSTFirst ? t1 : t2
        let dstEnd   = startsDSTFirst ? t2 : t1

        // POSIX omits the DST offset when it is exactly one hour ahead, which is
        // the overwhelmingly common case and keeps the string short.
        let dstOffsetText = (dstOff - stdOff == 3600) ? "" : offset(dstOff)

        return abbreviation(tz, stdRef) + offset(stdOff)
             + abbreviation(tz, dstRef) + dstOffsetText
             + "," + rule(for: dstStart, wallOffset: stdOff)
             + "," + rule(for: dstEnd, wallOffset: dstOff)
    }

    // MARK: - Pieces

    /// POSIX writes the offset as the time to ADD to local to get UTC, so the
    /// sign is the opposite of `secondsFromGMT`. Minutes appear only when the
    /// zone actually uses them.
    private static func offset(_ secondsFromGMT: Int) -> String {
        let inverted = -secondsFromGMT
        let sign = inverted < 0 ? "-" : ""
        let total = abs(inverted)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if s != 0 { return "\(sign)\(h):\(pad(m)):\(pad(s))" }
        if m != 0 { return "\(sign)\(h):\(pad(m))" }
        return "\(sign)\(h)"
    }

    /// An abbreviation POSIX will accept. Foundation hands back things like
    /// "EST", but also "GMT+5:30" for zones with no letters of their own — and
    /// that is not a legal bare abbreviation, so it goes in the quoted numeric
    /// form instead.
    private static func abbreviation(_ tz: TimeZone, _ date: Date) -> String {
        let raw = tz.abbreviation(for: date) ?? ""
        if raw.count >= 3, raw.allSatisfy({ $0.isLetter }) {
            return raw
        }
        let off = tz.secondsFromGMT(for: date)
        let sign = off < 0 ? "-" : "+"
        let total = abs(off)
        let h = total / 3600, m = (total % 3600) / 60
        return m == 0 ? "<\(sign)\(pad(h))>" : "<\(sign)\(pad(h))\(pad(m))>"
    }

    /// `Mmonth.week.weekday/hour` — week 5 means "the last one in the month".
    ///
    /// The hour is the local wall-clock reading at which the change happens,
    /// expressed in the offset that was in effect *before* it. Shifting the
    /// instant by that offset and reading it in UTC is what produces the 2:00
    /// everyone expects, rather than the 3:00 the clock jumps to.
    private static func rule(for transition: Date, wallOffset: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        let wall = transition.addingTimeInterval(TimeInterval(wallOffset))
        let c = utc.dateComponents([.month, .day, .weekday, .hour, .minute], from: wall)
        guard let month = c.month, let day = c.day, let weekday = c.weekday else {
            return "M3.2.0"      // unreachable; a sane US-style default
        }

        // Foundation counts weekdays from 1 = Sunday; POSIX from 0 = Sunday.
        let d = weekday - 1

        var week = (day - 1) / 7 + 1
        if let range = utc.range(of: .day, in: .month, for: wall), day + 7 >= range.upperBound {
            week = 5             // the last such weekday of the month
        }

        let hour = c.hour ?? 2
        let minute = c.minute ?? 0
        let time = minute == 0 ? "\(hour)" : "\(hour):\(pad(minute))"
        return "M\(month).\(week).\(d)" + (time == "2" ? "" : "/\(time)")
    }

    private static func pad(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
}
