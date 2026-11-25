import AppKit
import AuleumKit

extension AppDelegate {
    // MARK: - 自动化

    func startAutomationScheduler() {
        guard automationTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.tickAutomation()
        }
        RunLoop.main.add(timer, forMode: .common)
        automationTimer = timer
        tickAutomation()
    }

    func tickAutomation(now: Date = Date()) {
        let idleSeconds = InputIdleMonitor.secondsSinceLastInput()
        if idleSeconds < 5 {
            idleTriggerArmed = true
        }

        if !config.scheduleEnabled {
            scheduleWasInside = false
        }
        let scheduleInside = AuleumAutomationPolicy.scheduleContains(
            enabled: config.scheduleEnabled,
            weekdays: config.scheduleWeekdays,
            startMinutes: config.scheduleStartMinutes,
            endMinutes: config.scheduleEndMinutes,
            date: now
        )
        if scheduleInside {
            if !scheduleWasInside,
               state == .idle,
               controlServerReady,
               !presentationPreview.isActive,
               now >= automationRetryAfter {
                scheduleWasInside = true
                if !startAutomationVeil(trigger: .schedule) {
                    scheduleWasInside = false
                }
            } else if !scheduleWasInside {
                if state.isOn || now < automationRetryAfter {
                    scheduleWasInside = true
                }
            }
        } else if scheduleWasInside {
            scheduleWasInside = false
            if config.scheduleAutoExit,
               veilOn,
               sessionTrigger == .schedule {
                audit.write("schedule_window_ended", [:])
                requestExit(trigger: .schedule)
            }
        }

        guard state == .idle,
              controlServerReady,
              !presentationPreview.isActive,
              AuleumAutomationPolicy.shouldStartForIdle(
                enabled: config.idleAutoVeilEnabled,
                idleSeconds: idleSeconds,
                threshold: config.idleAutoVeilSeconds
              ) else {
            return
        }
        guard idleTriggerArmed else { return }
        guard now >= automationRetryAfter else { return }
        if startAutomationVeil(trigger: .idle) {
            idleTriggerArmed = false
        }
    }

    @discardableResult
    func startAutomationVeil(trigger: AuleumTrigger) -> Bool {
        guard state == .idle else { return false }
        let response = turnOn(
            trigger: trigger,
            protectionMinutes: trigger == .schedule
                ? 0
                : config.defaultProtectionMinutes
        )
        if !response.ok {
            audit.write("automation_start_failed", [
                "trigger": trigger.rawValue,
                "reason": response.message,
            ])
            NSLog(
                "Auleum: automatic %@ start failed: %@",
                trigger.rawValue,
                response.message
            )
            automationRetryAfter = Date().addingTimeInterval(30)
        }
        return response.ok
    }

    func resetAutomationState() {
        scheduleWasInside = false
        idleTriggerArmed = true
        automationRetryAfter = .distantPast
    }
}
