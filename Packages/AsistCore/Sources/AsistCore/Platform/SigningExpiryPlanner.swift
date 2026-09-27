import Foundation

public enum SigningExpiryPlanner {

    /// Bitişten 48 s, 24 s ve 4 s önce uyarı. 22:00–08:00 arasına düşen uyarı önceki akşam 21:00'e alınır.
    /// Geçmişte kalan veya bitişten sonraya düşen zamanlar atılır; sonuç sıralı ve tekildir.
    public static func warningDates(expiration: Date, now: Date, calendar: Calendar) -> [Date] {
        let offsets: [TimeInterval] = [48 * 3600, 24 * 3600, 4 * 3600]
        var result: [Date] = []
        for offset in offsets {
            let shifted = shiftOutOfNight(expiration.addingTimeInterval(-offset), calendar: calendar)
            guard shifted > now.addingTimeInterval(60), shifted < expiration else { continue }
            if !result.contains(shifted) {
                result.append(shifted)
            }
        }
        return result.sorted()
    }

    public static func shiftOutOfNight(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour >= 22 {
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) ?? date
        }
        if hour < 8 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return date }
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: previousDay) ?? date
        }
        return date
    }

    /// "3 gün", "20 saat", "1 saatten az"
    public static func remainingDescription(from start: Date, to end: Date) -> String {
        let hours = Int(max(0, end.timeIntervalSince(start)) / 3600)
        if hours >= 48 { return "\(hours / 24) gün" }
        if hours >= 1 { return "\(hours) saat" }
        return "1 saatten az"
    }
}
