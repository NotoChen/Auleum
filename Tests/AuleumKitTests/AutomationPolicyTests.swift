import Foundation
import Testing
@testable import AuleumKit

@Suite("Automation policy")
struct AutomationPolicyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int = 2026,
        month: Int = 11,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    @Test("Idle trigger honors enablement and threshold")
    func idleThreshold() {
        #expect(AuleumAutomationPolicy.shouldStartForIdle(
            enabled: true,
            idleSeconds: 601,
            threshold: 600
        ))
        #expect(!AuleumAutomationPolicy.shouldStartForIdle(
            enabled: false,
            idleSeconds: 601,
            threshold: 600
        ))
        #expect(!AuleumAutomationPolicy.shouldStartForIdle(
            enabled: true,
            idleSeconds: 599,
            threshold: 600
        ))
    }

    @Test("Schedule handles a normal weekday window")
    func normalWindow() {
        // 2026-11-16 is Monday.
        #expect(AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0b0000001,
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            date: date(day: 16, hour: 10),
            calendar: calendar
        ))
        #expect(!AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0b0000001,
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            date: date(day: 16, hour: 18),
            calendar: calendar
        ))
    }

    @Test("Schedule crosses midnight using the previous weekday")
    func crossMidnight() {
        // Monday 23:00 through Tuesday 02:00.
        #expect(AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0b0000001,
            startMinutes: 23 * 60,
            endMinutes: 2 * 60,
            date: date(day: 17, hour: 1),
            calendar: calendar
        ))
        #expect(!AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0b0000010,
            startMinutes: 23 * 60,
            endMinutes: 2 * 60,
            date: date(day: 17, hour: 1),
            calendar: calendar
        ))
    }

    @Test("Equal start and end means the selected day is protected all day")
    func allDay() {
        #expect(AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0b0000001,
            startMinutes: 9 * 60,
            endMinutes: 9 * 60,
            date: date(day: 16, hour: 3),
            calendar: calendar
        ))
    }

    @Test("An empty weekday mask never activates a schedule")
    func emptyWeekdayMask() {
        #expect(!AuleumAutomationPolicy.scheduleContains(
            enabled: true,
            weekdays: 0,
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            date: date(day: 16, hour: 10),
            calendar: calendar
        ))
    }

    @Test("Weekdays are Monday-based bits")
    func weekdayBits() {
        #expect(AuleumAutomationPolicy.weekdayBit(
            for: date(day: 16, hour: 12),
            calendar: calendar
        ) == 0b0000001)
        #expect(AuleumAutomationPolicy.weekdayBit(
            for: date(day: 22, hour: 12),
            calendar: calendar
        ) == 0b1000000)
    }

    @Test("URL commands parse actions and clamp minutes")
    func urlCommands() {
        let on = AuleumURLCommand(url: URL(string: "auleum://on?minutes=90")!)
        #expect(on?.action == .on)
        #expect(on?.minutes == 90)

        let clamped = AuleumURLCommand(
            url: URL(string: "auleum://protect?minutes=9999")!
        )
        #expect(clamped?.action == .protect)
        #expect(clamped?.minutes == 1440)

        #expect(AuleumURLCommand(url: URL(string: "auleum://off")!)?.action == .off)
        #expect(AuleumURLCommand(url: URL(string: "auleum://panic")!) == nil)
        #expect(AuleumURLCommand(url: URL(string: "https://example.com")!) == nil)
        #expect(AuleumURLCommand(url: URL(string: "auleum://unknown")!) == nil)
    }
}
