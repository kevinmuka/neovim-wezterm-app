import Cocoa
import Foundation

private enum LauncherError: LocalizedError {
   case wezTermNotFound
   case neovimNotFound
   case yaziNotFound
   case pickerResourceNotFound

   var errorDescription: String? {
      switch self {
      case .wezTermNotFound:
         return "WezTerm non è installato. Installalo nella cartella Applicazioni e riprova."
      case .neovimNotFound:
         return "Neovim non è stato trovato. Installalo con Homebrew (`brew install neovim`) e riprova."
      case .yaziNotFound:
         return "Yazi non è stato trovato."
      case .pickerResourceNotFound:
         return "Il selettore Yazi incluso nell'app non è disponibile."
      }
   }
}

private struct LaunchRequest: Codable {
   let executable: String
   let arguments: [String]
   let workingDirectory: String
}

private enum NeovimLauncher {
   private static var wezTermCandidates: [String] {
      let bundledHelper = Bundle.main.bundleURL
         .appendingPathComponent("Contents/Helpers/NeovimWezTermHelper.app/Contents/MacOS/wezterm-gui")
         .path

      return [
         bundledHelper,
         "/Applications/WezTerm.app/Contents/MacOS/wezterm",
         "/opt/homebrew/bin/wezterm",
         "/usr/local/bin/wezterm"
      ]
   }

   private static let neovimCandidates = [
      "/opt/homebrew/bin/nvim",
      "/usr/local/bin/nvim",
      "/usr/bin/nvim"
   ]

   private static let yaziCandidates = [
      "/opt/homebrew/bin/yazi",
      "/usr/local/bin/yazi"
   ]

   static func makeRequest(paths: [String]) throws -> LaunchRequest {
      guard let wezTerm = firstExecutable(in: wezTermCandidates) else {
         throw LauncherError.wezTermNotFound
      }
      guard let neovim = firstExecutable(in: neovimCandidates) else {
         throw LauncherError.neovimNotFound
      }

      let normalizedPaths = paths.map {
         URL(fileURLWithPath: $0).standardizedFileURL.path
      }
      let workingDirectory = workspaceDirectory(for: normalizedPaths.first)

      if normalizedPaths.isEmpty {
         guard firstExecutable(in: yaziCandidates) != nil else {
            throw LauncherError.yaziNotFound
         }
         guard let pickerScript = Bundle.main.url(forResource: "workspace-picker", withExtension: "zsh")?.path else {
            throw LauncherError.pickerResourceNotFound
         }

         let shellCommand = "exec \(shellQuoted(pickerScript)) \"$@\""
         return LaunchRequest(
            executable: wezTerm,
            arguments: [
               "start", "--cwd", workingDirectory, "--",
               "/bin/zsh", "-lic", shellCommand, "nvim-wezterm-picker", workingDirectory
            ],
            workingDirectory: workingDirectory
         )
      }

      let shellCommand = "exec \(shellQuoted(neovim)) \"$@\""
      return LaunchRequest(
         executable: wezTerm,
         arguments: [
            "start", "--cwd", workingDirectory, "--",
            "/bin/zsh", "-lic", shellCommand, "nvim-wezterm"
         ] + normalizedPaths,
         workingDirectory: workingDirectory
      )
   }

   static func launch(paths: [String], terminationHandler: @escaping (Process) -> Void) throws -> Process {
      let request = try makeRequest(paths: paths)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: request.executable)
      var arguments = request.arguments
      arguments.insert("--always-new-process", at: 1)
      process.arguments = arguments
      process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory)
      var environment = ProcessInfo.processInfo.environment
      environment["NEOVIM_APP_SINGLE_SESSION"] = "1"
      environment["WEZTERM_MACOS_ACTIVATION_POLICY"] = "accessory"
      process.environment = environment
      process.terminationHandler = terminationHandler
      try process.run()
      return process
   }

   static func workspaceDirectory(for path: String?) -> String {
      guard let path else {
         return FileManager.default.homeDirectoryForCurrentUser.path
      }

      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
         return path
      }
      return URL(fileURLWithPath: path).deletingLastPathComponent().path
   }

   private static func firstExecutable(in candidates: [String]) -> String? {
      candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
   }

   private static func shellQuoted(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
   }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
   private var pendingPaths: [String] = []
   private var startupScheduled = false
   private var managedProcesses: [Int32: Process] = [:]

   func applicationDidFinishLaunching(_ notification: Notification) {
      scheduleStartup()
   }

   func application(_ application: NSApplication, open urls: [URL]) {
      pendingPaths.append(contentsOf: urls.filter(\.isFileURL).map(\.path))
      scheduleStartup()
   }

   func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
      if focusExistingSession() {
         return true
      }
      scheduleStartup()
      return true
   }

   private func focusExistingSession() -> Bool {
      guard let process = managedProcesses.values
         .filter(\.isRunning)
         .max(by: { $0.processIdentifier < $1.processIdentifier }) else {
         return false
      }

      focusWezTerm(processIdentifier: process.processIdentifier, remainingAttempts: 15)
      return true
   }

   private func scheduleStartup() {
      guard !startupScheduled else { return }
      startupScheduled = true

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
         guard let self else { return }
         let paths = self.pendingPaths
         self.pendingPaths.removeAll()
         self.launch(paths: paths)
      }
   }

   private func launch(paths: [String]) {
      do {
         let process = try NeovimLauncher.launch(paths: paths) { [weak self] process in
            DispatchQueue.main.async {
               self?.managedProcessDidTerminate(process)
            }
         }
         managedProcesses[process.processIdentifier] = process
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.focusWezTerm(processIdentifier: process.processIdentifier, remainingAttempts: 15)
         }
      } catch LauncherError.yaziNotFound {
         chooseNewWorkspace()
      } catch {
         show(error: error)
         finishLaunchCycle()
      }
   }

   private func focusWezTerm(processIdentifier: Int32, remainingAttempts: Int) {
      if let wezTerm = NSRunningApplication(processIdentifier: processIdentifier), !wezTerm.isTerminated {
         wezTerm.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.finishLaunchCycle()
         }
         return
      }

      guard remainingAttempts > 0 else {
         finishLaunchCycle()
         return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
         self?.focusWezTerm(
            processIdentifier: processIdentifier,
            remainingAttempts: remainingAttempts - 1
         )
      }
   }

   private func managedProcessDidTerminate(_ process: Process) {
      managedProcesses.removeValue(forKey: process.processIdentifier)
      terminateIfIdle()
   }

   private func finishLaunchCycle() {
      startupScheduled = false
      if !pendingPaths.isEmpty {
         scheduleStartup()
      } else {
         terminateIfIdle()
      }
   }

   private func terminateIfIdle() {
      if managedProcesses.isEmpty && !startupScheduled && pendingPaths.isEmpty {
         NSApplication.shared.terminate(nil)
      }
   }

   private func chooseNewWorkspace() {
      NSApplication.shared.activate(ignoringOtherApps: true)
      let panel = NSOpenPanel()
      panel.title = "Apri un workspace in Neovim"
      panel.message = "Yazi non è disponibile: scegli la cartella del progetto."
      panel.prompt = "Apri"
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

      if panel.runModal() == .OK, let selectedURL = panel.url {
         launch(paths: [selectedURL.path])
      } else {
         finishLaunchCycle()
      }
   }

   private func show(error: Error) {
      NSApplication.shared.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "Impossibile aprire Neovim"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "OK")
      alert.runModal()
   }
}

let commandLine = Array(CommandLine.arguments.dropFirst())
if let dryRunIndex = commandLine.firstIndex(of: "--dry-run") {
   let paths = Array(commandLine.dropFirst(dryRunIndex + 1))
   do {
      let request = try NeovimLauncher.makeRequest(paths: paths)
      let data = try JSONEncoder().encode(request)
      print(String(decoding: data, as: UTF8.self))
      exit(EXIT_SUCCESS)
   } catch {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
   }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
