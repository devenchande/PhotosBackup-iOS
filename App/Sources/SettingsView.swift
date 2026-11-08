import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var account: PhotosAccount
    @EnvironmentObject private var queue: UploadQueue
    @EnvironmentObject private var preferences: BackupPreferences
    @EnvironmentObject private var albums: PhotoAlbumStore
    @EnvironmentObject private var automaticBackup: AutomaticBackupCoordinator

    let showTutorial: () -> Void
    @State private var confirmDisconnect = false
    @State private var connectionCheckResult: PhotosAccount.VerificationOutcome?
    @State private var verifyMessage: String?
    @State private var isVerifying = false
    @State private var confirmReupload = false
    @State private var showReuploadFolderPicker = false
    /// The folder picked for re-upload, held until the user confirms it.
    @State private var reuploadFolder: URL?
    private let gpmcURL = URL(string: "https://github.com/xob0t/gpmc")!

    var body: some View {
        NavigationView {
            Form {
                accountSection
                backupSection
                automationSection
                verifySection
                supportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog("Disconnect Google Photos?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await account.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("New backups will stop until you connect again. Photos already backed up are not affected.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var accountSection: some View {
        Section("Google Photos Account") {
            HStack(alignment: .top, spacing: 12) {
                FeatureIcon(symbol: "person.crop.circle.fill", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(accountTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(account.status.isUsable ? Color.green : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer()
                Image(systemName: account.status.isUsable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(account.status.isUsable ? Color.green : Color.orange)
                    .accessibilityLabel(account.status.isUsable ? "Connected" : "Action needed")
            }
            .padding(.vertical, 4)

            if account.status.isUsable {
                Button {
                    connectionCheckResult = nil
                    Task {
                        let result = await account.verify()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            connectionCheckResult = result
                        }
                    }
                } label: {
                    HStack {
                        Text(account.verifying ? "Checking Connection…" : "Check Connection")
                        Spacer()
                        if account.verifying {
                            ProgressView()
                        } else if connectionCheckResult == .succeeded {
                            Label("Verified", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                    .disabled(account.verifying)
                Button("Disconnect Account", role: .destructive) { confirmDisconnect = true }
            } else {
                Button("Connect Account") { showTutorial() }
            }

            if case .failed(let reason) = connectionCheckResult, account.status.isUsable {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if account.status.isUsable, let warning = account.persistenceWarning {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Not saved to Keychain", systemImage: "key.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(warning + " The account works for this session but may need to be connected again after relaunch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .onChange(of: account.status) { status in
            if !status.isUsable { connectionCheckResult = nil }
        }
    }

    private var backupSection: some View {
        Section {
            Toggle("Automatic Backup", isOn: $preferences.automaticBackup)
            Picker("Use Connection", selection: $preferences.connection) {
                ForEach(BackupConnection.allCases) { option in Text(option.title).tag(option) }
            }
            if let reason = queue.networkPauseReason {
                Label(reason, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Picker("Simultaneous Uploads", selection: $preferences.concurrentUploads) {
                ForEach(Array(UploadQueue.concurrencyRange), id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            }
            Toggle("Storage Saver", isOn: $preferences.storageSaver)
            Toggle("Count Against Storage Quota", isOn: $preferences.useQuota)
            Toggle("Back Up Live Photo Motion", isOn: $preferences.backUpLivePhotoMotion)
            Toggle("Add to Matching Albums", isOn: $preferences.albumsFromLibrary)
            Toggle("Back Up Portrait Originals", isOn: $preferences.backUpPortraitOriginals)
            Toggle("Back Up Video Originals", isOn: $preferences.backUpVideoOriginals)
        } header: {
            Text("Backup")
        } footer: {
            Text("More simultaneous uploads finish a large backup sooner. Each one stages a full-size copy on the device while it runs, so high values use more storage, battery and data at once — 2 suits most phones. Lowering it lets uploads already running finish first.\n\nStorage Saver asks Google Photos to reduce file size. With Count Against Storage Quota off, uploads identify as an older Pixel phone so they don't use your Google storage; the Google Photos app may then label them “Storage saver” even though the original file was kept. The file size, or Google Photos on the web, shows the real quality.\n\nBack Up Live Photo Motion attaches each Live Photo's motion to its photo, so it plays as a Live Photo in Google Photos and the Google Photos app's Free up space can remove it from this iPhone. It uploads the short video too, a few MB per Live Photo, and uses storage the same way the photo does. Live Photos backed up earlier get their motion added in the background.\n\nAdd to Matching Albums puts each new upload into a Google Photos album with the same name as each of your albums holding it, or for a file from a picked folder, the folder holding it, creating the album the first time. Photos backed up before it was turned on are not moved.\n\nBack Up Portrait Originals also uploads the camera's original of each Portrait photo, and of each photo the camera captured depth for so Portrait can be turned on later, when it has been edited. Google Photos otherwise only gets the edit, with the blur rendered in; the original keeps the depth data, so after downloading it you can change the focus and depth in Photos again. It appears as a separate item in Google Photos. Photos without depth are checked once and not uploaded, and unedited ones already back up with their depth. Photos backed up earlier are checked in the background.\n\nBack Up Video Originals also uploads the camera's original of every edited video, including each Cinematic video, which the camera always saves as edited. The Google Photos app may show a Cinematic video as not backed up until its original is in the account, so its Free up space cannot remove it. Each edited video then appears twice in Google Photos, and some Cinematic originals do not play in the Google Photos iPhone app. Edited videos backed up earlier get their original added in the background.")
        }
    }

    private var verifySection: some View {
        Section {
            Button {
                runVerification()
            } label: {
                HStack {
                    Text(isVerifying ? "Re-checking…" : "Re-check Backups")
                    Spacer()
                    if isVerifying { ProgressView() }
                }
            }
            .disabled(!canVerify)
            Toggle("Allow Re-upload", isOn: $preferences.allowReupload)
            if preferences.allowReupload {
                Button("Re-upload Selected Albums") { confirmReupload = true }
                    .disabled(!canVerify)
                    .confirmationDialog("Upload the selected albums again?", isPresented: $confirmReupload,
                                        titleVisibility: .visible) {
                        Button("Re-upload") { runReupload() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every photo and video in the selected albums is uploaded again, including ones already in Google Photos. This takes as long and uses as much data as the first backup.")
                    }
                Button("Re-upload a Folder…") { showReuploadFolderPicker = true }
                    .disabled(!canReuploadFolder)
                    .fileImporter(isPresented: $showReuploadFolderPicker, allowedContentTypes: [.folder]) { result in
                        switch result {
                        case .success(let url): reuploadFolder = url
                        case .failure(let error): verifyMessage = "Could not open that folder: \(error.localizedDescription)"
                        }
                    }
                    .confirmationDialog("Upload this folder again?",
                                        isPresented: Binding(get: { reuploadFolder != nil },
                                                             set: { if !$0 { reuploadFolder = nil } }),
                                        titleVisibility: .visible, presenting: reuploadFolder) { folder in
                        Button("Re-upload") { runReuploadFolder(folder) }
                        Button("Cancel", role: .cancel) {}
                    } message: { folder in
                        Text("Every photo and video in “\(folder.lastPathComponent)” and its subfolders is uploaded again, including ones already in Google Photos. This takes as long and uses as much data as the first backup.")
                    }
            }
            if let verifyMessage {
                Text(verifyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Re-check")
        } footer: {
            Text("Re-check compares your selected albums against Google Photos again. Items still in the cloud finish quickly; anything deleted there is queued for upload again.\n\nAllow Re-upload shows two buttons that send every item in your selected albums, or in a folder from the Files app, again using your current Storage Saver and storage quota settings, even where Google Photos already has it. It is meant for photos that use your Google storage because they were uploaded another way. Google Photos may keep the copy it already has, so try a small album or folder first and compare your storage before and after.")
        }
    }

    private var automationSection: some View {
        Section {
            ShortcutsSettingsRows()
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("In the Shortcuts app, create a personal automation — when the iPhone connects to power, at a time of day, or when it joins your home Wi-Fi — set it to run immediately, and add Back Up Photos. Each run has about 30 seconds: it finds new photos in the selected albums and hands them to iOS to upload in the background. It runs even with Automatic Backup off, and still follows Use Connection and Pause. Photos stored only in iCloud wait until the app is open.")
        }
    }

    private var canVerify: Bool {
        account.status.isUsable && !isVerifying && !preferences.selectedAlbumIDs.isEmpty
    }

    /// A folder needs no album selection.
    private var canReuploadFolder: Bool {
        account.status.isUsable && !isVerifying
    }

    private func runVerification() {
        guard canVerify else { return }
        isVerifying = true
        verifyMessage = nil
        Task {
            let outcome = await automaticBackup.reverifySelectedAlbums()
            isVerifying = false
            verifyMessage = DashboardView.message(for: outcome)
        }
    }

    private func runReuploadFolder(_ folder: URL) {
        guard canReuploadFolder else { return }
        isVerifying = true
        verifyMessage = nil
        Task {
            do {
                let outcome = try await automaticBackup.reuploadFolder(folder)
                verifyMessage = outcome == .nothingToDo
                    ? "No photos or videos found in “\(folder.lastPathComponent)”."
                    : DashboardView.message(for: outcome)
            } catch {
                verifyMessage = "Could not read that folder: \(error.localizedDescription)"
            }
            isVerifying = false
        }
    }

    private func runReupload() {
        guard canVerify else { return }
        isVerifying = true
        verifyMessage = nil
        Task {
            let outcome = await automaticBackup.reuploadSelectedAlbums()
            isVerifying = false
            verifyMessage = DashboardView.message(for: outcome)
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink("Create Diagnostic Report") { DiagnosticReportView() }
            NavigationLink("Storage") { StorageUsageView() }
            NavigationLink("Diagnostics") { DiagnosticsView() }
            Button("Run Onboarding Again") {
                preferences.resetOnboarding()
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledRow("App", value: "Photos Backup")
            LabeledRow("Version", value: appVersion)
            LabeledRow("iOS", value: UIDevice.current.systemVersion)
            LabeledRow("Core technology") {
                Link("GPMC by xob0t", destination: gpmcURL)
            }
        }
    }

    private var accountTitle: String {
        switch account.status {
        case .loading: return "Checking account…"
        case .disconnected: return "Not connected"
        case .connected(let email, _): return email
        case .rejected(let email, _): return email.isEmpty ? "Sign in again" : email
        }
    }

    private var accountSubtitle: String {
        switch account.status {
        case .loading: return "Looking for a saved credential"
        case .disconnected: return "Connect to start backing up"
        case .connected(_, let since): return "Connected · \(since.formatted(date: .abbreviated, time: .omitted))"
        case .rejected(_, let reason): return reason
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

/// The Shortcuts rows: a way into the Shortcuts app, and the last run, so an
/// automation can be checked without waiting for a problem.
private struct ShortcutsSettingsRows: View {
    @State private var lastRun: AutomaticBackupRunRecord?

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                Label("Back Up Photos action", systemImage: "square.stack.3d.up.fill")
                Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                if let lastRun {
                    AutomaticRunRow(run: lastRun)
                } else {
                    Text("The action has not run yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Requires iOS 16 or later", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { lastRun = AutomaticBackupRunHistory.latest(.shortcut) }
    }
}

/// Presents the in-app Google account connection flow (see AccountConnectView)
/// and runs the token exchange on capture. Shown as a sheet from the dashboard
/// and Settings.
struct ConnectionTutorialView: View {
    @EnvironmentObject private var probe: AccountConnector
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AccountConnectView(
            onCaptured: { token in
                dismiss()
                Task { await probe.ingestWebToken(token) }
            },
            onCancel: { dismiss() }
        )
    }
}
