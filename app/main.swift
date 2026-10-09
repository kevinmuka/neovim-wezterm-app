import Cocoa
import Foundation

private enum LauncherError: LocalizedError {
   case bundledTerminalNotFound
   case neovimNotFound
   case yaziNotFound
   case pickerResourceNotFound
   case serverUnavailable
   case remoteOpenFailed

   var errorDescription: String? {
      switch self {
      case .bundledTerminalNotFound:
         return "Il terminale incluso in Neovim.app non è disponibile. Reinstalla o ricompila l'app e riprova."
      case .neovimNotFound:
         return "Neovim non è stato trovato. Installalo con Homebrew (`brew install neovim`) e riprova."
      case .yaziNotFound:
         return "Yazi non è stato trovato."
      case .pickerResourceNotFound:
         return "Il selettore Yazi incluso nell'app non è disponibile."
      case .serverUnavailable:
         return "Impossibile preparare la comunicazione con Neovim. Riprova ad aprire l'app."
      case .remoteOpenFailed:
         return "Impossibile aprire il file nella sessione Neovim esistente."
      }
   }
}

private struct LaunchRequest: Codable {
   let executable: String
   let arguments: [String]
   let workingDirectory: String
}

private struct ManagedSession {
   let process: Process
   let serverDirectory: URL

   var serverAddress: String {
      serverDirectory.appendingPathComponent("nvim.sock").path
   }
}

private enum NeovimLauncher {
   private static var bundledWezTerm: String {
      Bundle.main.bundleURL
         .appendingPathComponent("Contents/Helpers/NeovimWezTermHelper.app/Contents/MacOS/wezterm-gui")
         .path
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

   static func makeRequest(paths: [String], serverAddress: String) throws -> LaunchRequest {
      let wezTerm = bundledWezTerm
      guard FileManager.default.isExecutableFile(atPath: wezTerm) else {
         throw LauncherError.bundledTerminalNotFound
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

      let shellCommand = "exec \(shellQuoted(neovim)) --listen \(shellQuoted(serverAddress)) \"$@\""
      return LaunchRequest(
         executable: wezTerm,
         arguments: [
            "start", "--cwd", workingDirectory, "--",
            "/bin/zsh", "-lic", shellCommand, "nvim-wezterm"
         ] + normalizedPaths,
         workingDirectory: workingDirectory
      )
   }

   static func launch(paths: [String], terminationHandler: @escaping (Process) -> Void) throws -> ManagedSession {
      let serverDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
         .appendingPathComponent("neovim-app-\(UUID().uuidString)", isDirectory: true)
      do {
         try FileManager.default.createDirectory(
            at: serverDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
         )
      } catch {
         throw LauncherError.serverUnavailable
      }
      let serverAddress = serverDirectory.appendingPathComponent("nvim.sock").path

      do {
         let request = try makeRequest(paths: paths, serverAddress: serverAddress)
         let process = Process()
         process.executableURL = URL(fileURLWithPath: request.executable)
         var arguments = request.arguments
         arguments.insert("--always-new-process", at: 1)
         process.arguments = arguments
         process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory)
         var environment = ProcessInfo.processInfo.environment
         environment["NEOVIM_APP_SINGLE_SESSION"] = "1"
         environment["WEZTERM_SINGLE_SESSION_MODE"] = "1"
         environment["WEZTERM_MACOS_ACTIVATION_POLICY"] = "accessory"
         environment["NEOVIM_APP_SERVER_ADDRESS"] = serverAddress
         process.environment = environment
         process.terminationHandler = terminationHandler
         try process.run()
         return ManagedSession(process: process, serverDirectory: serverDirectory)
      } catch {
         removeServerDirectory(serverDirectory)
         throw error
      }
   }

   static func removeServerDirectory(_ directory: URL) {
      guard directory.deletingLastPathComponent().path == "/private/tmp",
            directory.lastPathComponent.hasPrefix("neovim-app-") else {
         return
      }
      try? FileManager.default.removeItem(at: directory)
   }

   static func remoteOpen(paths: [String], serverAddress: String) -> Bool {
      guard let neovim = firstExecutable(in: neovimCandidates), !paths.isEmpty else {
         return false
      }

      let files = paths.map { "fnameescape(\(vimQuoted($0)))" }.joined(separator: " . ' ' . ")
      let process = Process()
      process.executableURL = URL(fileURLWithPath: neovim)
      process.arguments = ["--server", serverAddress, "--remote-expr", "execute('drop ' . \(files))"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
         try process.run()
         process.waitUntilExit()
         return process.terminationStatus == 0
      } catch {
         return false
      }
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

   private static func vimQuoted(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
   }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
   private var pendingPaths: [String] = []
   private var startupScheduled = false
   private var remoteDeliveryActive = false
   private var remoteDeliveryFailures = 0
   private var managedSessions: [Int32: ManagedSession] = [:]

   func applicationDidFinishLaunching(_ notification: Notification) {
      scheduleStartup()
   }

   func application(_ application: NSApplication, open urls: [URL]) {
      pendingPaths.append(contentsOf: urls.filter(\.isFileURL).map(\.path))
      if currentSession() != nil {
         scheduleRemoteDelivery()
      } else {
         scheduleStartup()
      }
   }

   func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
      if focusExistingSession() {
         return true
      }
      scheduleStartup()
      return true
   }

   private func focusExistingSession() -> Bool {
      guard let session = currentSession() else {
         return false
      }

      // Let Launch Services finish the reopen event before activating the
      // terminal window owned by the accessory helper.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
         self?.focusWezTerm(processIdentifier: session.process.processIdentifier, remainingAttempts: 15)
      }
      return true
   }

   private func currentSession() -> ManagedSession? {
      managedSessions.values
         .filter { $0.process.isRunning }
         .max(by: { $0.process.processIdentifier < $1.process.processIdentifier })
   }

   private func scheduleStartup() {
      guard !startupScheduled else { return }
      if currentSession() != nil {
         scheduleRemoteDelivery()
         return
      }
      startupScheduled = true

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
         guard let self else { return }
         if self.currentSession() != nil {
            self.startupScheduled = false
            self.scheduleRemoteDelivery()
            return
         }
         let paths = self.pendingPaths
         self.pendingPaths.removeAll()
         self.launch(paths: paths)
      }
   }

   private func launch(paths: [String]) {
      do {
         let session = try NeovimLauncher.launch(paths: paths) { [weak self] process in
            DispatchQueue.main.async {
               self?.managedSessionDidTerminate(process)
            }
         }
         managedSessions[session.process.processIdentifier] = session
         remoteDeliveryFailures = 0
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.focusWezTerm(processIdentifier: session.process.processIdentifier, remainingAttempts: 15)
         }
      } catch LauncherError.yaziNotFound {
         chooseNewWorkspace()
      } catch {
         show(error: error)
         finishLaunchCycle()
      }
   }

   private func scheduleRemoteDelivery(after delay: TimeInterval = 0) {
      guard !remoteDeliveryActive, !pendingPaths.isEmpty else { return }
      guard let session = currentSession() else {
         scheduleStartup()
         return
      }
      remoteDeliveryActive = true

      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
         guard let self else { return }
         let processIdentifier = session.process.processIdentifier
         guard let current = self.currentSession(), current.process.processIdentifier == processIdentifier else {
            self.remoteDeliveryActive = false
            self.scheduleStartup()
            return
         }
         // The first launch may still be in Yazi. Keep the file request until Nvim starts.
         guard FileManager.default.fileExists(atPath: current.serverAddress) else {
            self.remoteDeliveryActive = false
            self.scheduleRemoteDelivery(after: 0.5)
            return
         }

         let paths = self.pendingPaths
         self.pendingPaths.removeAll()
         DispatchQueue.global(qos: .userInitiated).async {
            let opened = NeovimLauncher.remoteOpen(paths: paths, serverAddress: current.serverAddress)
            DispatchQueue.main.async { [weak self] in
               guard let self else { return }
               self.remoteDeliveryActive = false
               if opened {
                  self.remoteDeliveryFailures = 0
                  self.focusWezTerm(processIdentifier: processIdentifier, remainingAttempts: 15)
                  self.scheduleRemoteDelivery()
               } else if self.currentSession()?.process.processIdentifier != processIdentifier {
                  self.pendingPaths.insert(contentsOf: paths, at: 0)
                  self.scheduleStartup()
               } else if self.remoteDeliveryFailures < 3 {
                  self.remoteDeliveryFailures += 1
                  self.pendingPaths.insert(contentsOf: paths, at: 0)
                  self.scheduleRemoteDelivery(after: 0.5)
               } else {
                  self.remoteDeliveryFailures = 0
                  self.show(error: LauncherError.remoteOpenFailed)
                  self.scheduleRemoteDelivery()
               }
            }
         }
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

   private func managedSessionDidTerminate(_ process: Process) {
      if let session = managedSessions.removeValue(forKey: process.processIdentifier) {
         NeovimLauncher.removeServerDirectory(session.serverDirectory)
      }
      if !pendingPaths.isEmpty && !remoteDeliveryActive {
         scheduleStartup()
      } else {
         terminateIfIdle()
      }
   }

   private func finishLaunchCycle() {
      startupScheduled = false
      if !pendingPaths.isEmpty {
         if currentSession() != nil {
            scheduleRemoteDelivery()
         } else {
            scheduleStartup()
         }
      } else {
         terminateIfIdle()
      }
   }

   private func terminateIfIdle() {
      if managedSessions.isEmpty && !startupScheduled && !remoteDeliveryActive && pendingPaths.isEmpty {
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
      let request = try NeovimLauncher.makeRequest(paths: paths, serverAddress: "/private/tmp/neovim-app-dry-run.sock")
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
