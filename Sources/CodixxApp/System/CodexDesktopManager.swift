import AppKit
import Foundation

struct CodexActivation {
    static let bundleIdentifier = "com.openai.codex"

    var activeProcessIdentifier: pid_t?
}

@MainActor
protocol CodexDesktopManaging: AnyObject {
    var isRunning: Bool { get }

    func currentActivation() -> CodexActivation
    func restoreActivationIfNeeded(_ activation: CodexActivation)
    func quitForCleanSwitch()
    func restart() throws
}

@MainActor
final class SystemCodexDesktopManager: CodexDesktopManaging {
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexActivation.bundleIdentifier
        ).isEmpty
    }

    func currentActivation() -> CodexActivation {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexActivation.bundleIdentifier
        )
        let activeApplication = applications.first { $0.isActive }
        return CodexActivation(activeProcessIdentifier: activeApplication?.processIdentifier)
    }

    func restoreActivationIfNeeded(_ activation: CodexActivation) {
        guard let processIdentifier = activation.activeProcessIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let applications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexActivation.bundleIdentifier
            )
            let application = applications.first { $0.processIdentifier == processIdentifier } ?? applications.first
            application?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    func quitForCleanSwitch() {
        var runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexActivation.bundleIdentifier
        )
        runningApplications.forEach { application in
            application.terminate()
        }

        for attempt in 0..<25 {
            runningApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexActivation.bundleIdentifier
            )
            guard !runningApplications.isEmpty else { return }
            if attempt == 15 {
                runningApplications.forEach { $0.forceTerminate() }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func restart() throws {
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CodexActivation.bundleIdentifier
        ) ?? URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true)

        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexActivation.bundleIdentifier
        )
        runningApplications.forEach { application in
            application.terminate()
        }

        guard !runningApplications.isEmpty else {
            openCodexDesktop(at: applicationURL)
            return
        }

        waitForCodexExitThenOpen(applicationURL: applicationURL, remainingAttempts: 25)
    }

    private func waitForCodexExitThenOpen(applicationURL: URL, remainingAttempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let runningApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexActivation.bundleIdentifier
            )
            guard !runningApplications.isEmpty, remainingAttempts > 0 else {
                self.openCodexDesktop(at: applicationURL)
                return
            }

            if remainingAttempts == 15 {
                runningApplications.forEach { $0.forceTerminate() }
            }

            self.waitForCodexExitThenOpen(
                applicationURL: applicationURL,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private func openCodexDesktop(at applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { [weak self] _, error in
            guard let error else {
                Task { @MainActor in
                    self?.verifyCodexLaunchFallback(applicationURL: applicationURL)
                }
                return
            }
            Task { @MainActor in
                self?.launchCodexWithOpenCommand(applicationURL: applicationURL, previousError: error)
            }
        }
    }

    private func verifyCodexLaunchFallback(applicationURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let runningApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexActivation.bundleIdentifier
            )
            guard runningApplications.isEmpty else { return }
            self?.launchCodexWithOpenCommand(applicationURL: applicationURL, previousError: nil)
        }
    }

    private func launchCodexWithOpenCommand(applicationURL: URL, previousError: Error?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", CodexActivation.bundleIdentifier]

        do {
            try process.run()
        } catch {
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallbackProcess.arguments = [applicationURL.path]
            do {
                try fallbackProcess.run()
            } catch {
                let original = previousError.map { "\($0.localizedDescription)\n" } ?? ""
                NSLog("Could not restart Codex: \(original)\(error.localizedDescription)")
            }
        }
    }
}
