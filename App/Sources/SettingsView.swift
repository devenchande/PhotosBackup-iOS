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
            HelpDisclosure(title: "What these options do", points: Self.backupHelp)
        } header: {
            Text("Backup")
        }
    }

    private static let backupHelp: [HelpDisclosure.Point] = [
        .init("Automatic Backup", "backs up new photos in your selected albums on its own."),
        .init("Simultaneous Uploads", "how many items upload at once.",
              ["Each one keeps a full-size copy on the iPhone while it runs; 2 suits most phones."]),
        .init("Storage Saver", "Google Photos makes files smaller."),
        .init("Count Against Storage Quota", "off, uploads don't use your Google storage.",
              ["The Google Photos app may still label them “Storage saver”; the file size shows the real quality."]),
        .init("Back Up Live Photo Motion", "a Live Photo plays as one in Google Photos, and its Free up space can remove it.",
              ["A few MB per Live Photo.", "Live Photos backed up earlier get their motion in the background."]),
        .init("Add to Matching Albums", "puts each upload in a Google Photos album named after its album, or its folder.",
              ["Photos backed up earlier aren't moved."]),
        .init("Back Up Portrait Originals", "also uploads the original of an edited Portrait photo, so you can change its focus after downloading it.",
              ["Only photos with depth are uploaded.", "Each appears as a second item in Google Photos."]),
        .init("Back Up Video Originals", "also uploads the original of every edited video, including Cinematic ones.",
              ["Lets the Google Photos app count Cinematic videos as backed up.",
               "Each edited video appears twice; some Cinematic originals don't play in the Google Photos app."]),
    ]

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
                if preferences.useQuota {
                    Label("Turn off Count Against Storage Quota first: re-uploading under it would still use your storage.",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Re-upload Selected Albums") { confirmReupload = true }
                    .disabled(!canVerify || preferences.useQuota)
                    .confirmationDialog("Upload the selected albums again?", isPresented: $confirmReupload,
                                        titleVisibility: .visible) {
                        Button("Re-upload") { runReupload() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every photo and video in the selected albums is uploaded again, including ones already in Google Photos. This takes as long and uses as much data as the first backup.")
                    }
                Button("Re-upload a Folder…") { showReuploadFolderPicker = true }
                    .disabled(!canReuploadChosen)
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
            HelpDisclosure(title: "What these options do", points: Self.recheckHelp)
        } header: {
            Text("Re-check")
        }
    }

    private static let recheckHelp: [HelpDisclosure.Point] = [
        .init("Re-check Backups", "checks your selected albums against Google Photos again.",
              ["Items still there finish quickly; anything deleted there is uploaded again."]),
        .init("Allow Re-upload", "uploads items again, even ones Google already has, so they can move to the free quota.",
              ["Pick Photos on Home then re-uploads what you pick.",
               "Shows Re-upload Selected Albums and Re-upload a Folder….",
               "Only works with Count Against Storage Quota off.",
               "Google may keep its old copy: try a few photos and compare your storage."]),
        .init("Pick Photos on Home", "with Allow Re-upload off, checks with Google first, so photos already there show “Already backed up”."),
    ]

    private var automationSection: some View {
        Section {
            ShortcutsSettingsRows()
            HelpDisclosure(title: "How to set it up", points: Self.shortcutsHelp)
        } header: {
            Text("Shortcuts")
        }
    }

    private static let shortcutsHelp: [HelpDisclosure.Point] = [
        .init("Create an automation", "in the Shortcuts app, under Automation → Personal Automation.",
              ["Trigger it when the iPhone charges, at a time of day, or on your home Wi-Fi.",
               "Set it to Run Immediately and add Back Up Photos."]),
        .init("Each run", "has about 30 seconds to find new photos and hand them to iOS to upload."),
        .init("Rules", "it runs even with Automatic Backup off, and still follows Use Connection and Pause."),
        .init("iCloud", "photos stored only in iCloud wait until the app is open."),
    ]

    private var canVerify: Bool {
        account.status.isUsable && !isVerifying && !preferences.selectedAlbumIDs.isEmpty
    }

    /// A folder needs no album selection.
    private var canReuploadChosen: Bool {
        account.status.isUsable && !isVerifying && !preferences.useQuota
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
        guard canReuploadChosen else { return }
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

/// A collapsed help row, the desktop app's "What these options do": a short
/// point per option, some with detail beneath, shown only when tapped open.
struct HelpDisclosure: View {
    struct Point {
        let title: String
        let text: String
        let details: [String]
        init(_ title: String, _ text: String, _ details: [String] = []) {
            self.title = title; self.text = text; self.details = details
        }
    }

    let title: String
    let points: [Point]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 4) {
                        bullet("•", Text(point.title + ":").bold().foregroundColor(.primary) + Text(" " + point.text))
                        ForEach(Array(point.details.enumerated()), id: \.offset) { _, detail in
                            bullet("◦", Text(detail)).padding(.leading, 14)
                        }
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.tint)
        }
    }

    private func bullet(_ mark: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark)
            text.fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
