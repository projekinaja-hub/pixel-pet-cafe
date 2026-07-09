import SwiftUI

/// Full visual calendar for the current season: a real day-by-day grid
/// (today highlighted, holidays marked) instead of just a "Day 14 of
/// Spring" text readout — elaborates on CafeTab's inline summary, which
/// stays as the quick-glance version.
struct CalendarOverlay: View {
    @ObservedObject var controller: GameController
    let dismiss: () -> Void

    private static let seasonEmoji: [Season: String] = [
        .spring: "🌱", .summer: "☀️", .autumn: "🍂", .winter: "❄️",
    ]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        let season = controller.state.season
        let today = GameCalendar.dayOfSeason(controller.state)
        let holidays = Holidays.forSeason(season)

        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 10) {
                HStack {
                    Text("\(Self.seasonEmoji[season] ?? "") \(season.rawValue.capitalized) Calendar")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(1...GameCalendar.daysPerSeason, id: \.self) { day in
                        dayCell(day: day, today: today, holiday: Holidays.on(dayOfSeason: day, season: season))
                    }
                }

                if !holidays.isEmpty {
                    Divider().background(Theme.dim.opacity(0.3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This season")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.dim)
                        ForEach(holidays, id: \.dayOfSeason) { h in
                            HStack(spacing: 5) {
                                Text("\(h.emoji) Day \(h.dayOfSeason) — \(h.name)")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(h.dayOfSeason == today ? Theme.gold : Theme.cream)
                                Spacer()
                                Text(boostLabel(h))
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundColor(Theme.dim)
                            }
                        }
                    }
                }

                Text("~1 real hour per day · \(GameCalendar.daysPerSeason) days a season")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            .padding(12)
            .frame(width: 320)
            .background(Theme.bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
        .frame(width: 360, height: 544)
        .transition(.opacity)
    }

    private func boostLabel(_ h: Holiday) -> String {
        var parts: [String] = []
        if h.priceBoost > 1.0 { parts.append("+\(Int(((h.priceBoost - 1) * 100).rounded()))% prices") }
        if h.customerBoost > 1.0 { parts.append("+\(Int(((h.customerBoost - 1) * 100).rounded()))% customers") }
        return parts.joined(separator: " · ")
    }

    private func dayCell(day: Int, today: Int, holiday: Holiday?) -> some View {
        let isToday = day == today
        return VStack(spacing: 1) {
            Text(holiday?.emoji ?? "")
                .font(.system(size: 10))
                .frame(height: 12)
            Text("\(day)")
                .font(.system(size: 10, weight: isToday ? .heavy : .semibold, design: .rounded))
                .foregroundColor(isToday ? Theme.bg : (holiday != nil ? Theme.gold : Theme.cream))
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(isToday ? Theme.gold : (holiday != nil ? Theme.gold.opacity(0.18) : Theme.card))
        .cornerRadius(6)
    }
}
