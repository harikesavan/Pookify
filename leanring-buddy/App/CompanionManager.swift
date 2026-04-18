//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import PostHog
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from the AI response;
    /// observed by BlueCursorView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so BlueCursorView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// Custom speech bubble text for the pointing animation. When set,
    /// BlueCursorView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?

    // MARK: - Onboarding Video State (shared across all screen overlays)

    @Published var onboardingVideoPlayer: AVPlayer?
    @Published var showOnboardingVideo: Bool = false
    @Published var onboardingVideoOpacity: Double = 0.0
    private var onboardingVideoEndObserver: NSObjectProtocol?
    private var onboardingDemoTimeObserver: Any?

    // MARK: - Onboarding Prompt Bubble

    /// Text streamed character-by-character on the cursor after the onboarding video ends.
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false

    // MARK: - Onboarding Music

    private var onboardingMusicPlayer: AVAudioPlayer?
    private var onboardingMusicFadeTimer: Timer?

    var usageTracker: UsageTracker?

    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()
    let globalTextPromptShortcutMonitor = GlobalTextPromptShortcutMonitor()
    let overlayWindowManager = OverlayWindowManager()
    private let textPromptWindowManager = TextPromptWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    private static let workerBaseURL = "http://127.0.0.1:8787"

    private lazy var openAIAPI: OpenAIAPI = {
        return OpenAIAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: selectedModel)
    }()

    private lazy var ttsClient: OpenAITTSClient = {
        return OpenAITTSClient(proxyURL: "\(Self.workerBaseURL)/tts")
    }()

    private lazy var knowledgeBaseClient: KnowledgeBaseClient = {
        let client = KnowledgeBaseClient(baseURL: Self.workerBaseURL)
        if let apiKey = CompanyConfigManager.loadConfig()?.api_key {
            client.configure(apiKey: apiKey)
        }
        return client
    }()

    @Published var companyName: String?
    @Published var configurationNoticeText: String?
    @Published private(set) var workflowSession: GuidedWorkflowSession?
    @Published private(set) var isAwaitingWorkflowObjective = false

    private var configurationNoticeClearTask: Task<Void, Never>?
    private var workflowAdvanceTask: Task<Void, Never>?
    private var workflowAutoVerifyTask: Task<Void, Never>?
    private var workflowClickMonitor: Any?

    func reloadCompanyConfig() {
        guard let config = CompanyConfigManager.loadConfig() else { return }
        companyName = config.company_name
        knowledgeBaseClient.configure(apiKey: config.api_key)
        print("📋 Company config reloaded: \(config.company_name)")
    }

    func applyCompanyConfig(_ config: CompanyConfig) {
        let previousApiKey = CompanyConfigManager.loadConfig()?.api_key
        let shouldResetUsage = previousApiKey != config.api_key

        CompanyConfigManager.saveConfig(config)
        reloadCompanyConfig()

        if shouldResetUsage {
            usageTracker?.resetUsage()
        }

        showConfigurationNotice("Connected to \(config.company_name)")
    }

    var isGuidedWorkflowActive: Bool {
        guard let workflowSession else { return false }
        return workflowSession.phase != .completed
    }

    var workflowStatusText: String? {
        guard let workflowSession else { return nil }

        switch workflowSession.phase {
        case .planning:
            return "Planning"
        case .awaitingUserAction:
            return "Step \(workflowSession.stepProgressText)"
        case .verifying:
            return "Checking"
        case .blocked:
            return "Needs help"
        case .completed:
            return "Done"
        }
    }

    func startGuidedWorkflow(withObjective objective: String) {
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObjective.isEmpty else { return }

        isAwaitingWorkflowObjective = false

        workflowAdvanceTask?.cancel()
        currentResponseTask?.cancel()
        ttsClient.stopPlayback()
        clearDetectedElementLocation()

        workflowSession = GuidedWorkflowSession(
            objective: trimmedObjective,
            steps: [],
            stopCondition: "",
            currentStepIndex: 0,
            phase: .planning,
            lastSpokenInstruction: nil,
            lastVerificationEvidence: []
        )

        workflowAdvanceTask = Task { [weak self] in
            await self?.planGuidedWorkflow(for: trimmedObjective)
        }
    }

    func advanceGuidedWorkflow() {
        guard workflowSession != nil else { return }

        workflowAutoVerifyTask?.cancel()
        workflowAdvanceTask?.cancel()
        workflowAdvanceTask = Task { [weak self] in
            await self?.verifyAndAdvanceGuidedWorkflow(extraGuidance: nil)
        }
    }

    func repeatGuidedWorkflowStep() {
        guard let workflowSession else { return }

        workflowAutoVerifyTask?.cancel()
        workflowAdvanceTask?.cancel()
        workflowAdvanceTask = Task { [weak self] in
            await self?.deliverGuidedWorkflowStep(session: workflowSession, extraGuidance: "Repeat the same step clearly and keep the user oriented.")
        }
    }

    func requestGuidedWorkflowHelp() {
        guard workflowSession != nil else { return }

        workflowAutoVerifyTask?.cancel()
        workflowAdvanceTask?.cancel()
        workflowAdvanceTask = Task { [weak self] in
            await self?.verifyAndAdvanceGuidedWorkflow(extraGuidance: "The user says they are stuck. Re-orient them from the current screenshot and give the clearest next move.")
        }
    }

    func cancelGuidedWorkflow() {
        stopWorkflowClickMonitor()
        workflowAutoVerifyTask?.cancel()
        workflowAutoVerifyTask = nil
        workflowAdvanceTask?.cancel()
        workflowAdvanceTask = nil
        workflowSession = nil
        isAwaitingWorkflowObjective = false
        showConfigurationNotice("Workflow cancelled")
    }

    func beginGuidedWorkflowPrompt() {
        isAwaitingWorkflowObjective = true
        showConfigurationNotice("Describe the task you want help with")
        showTextPromptWindow()
    }

    func startGuidedWorkflowFromScreenContext() {
        workflowAdvanceTask?.cancel()
        currentResponseTask?.cancel()
        ttsClient.stopPlayback()
        clearDetectedElementLocation()

        workflowSession = GuidedWorkflowSession(
            objective: "",
            steps: [],
            stopCondition: "",
            currentStepIndex: 0,
            phase: .planning,
            lastSpokenInstruction: nil,
            lastVerificationEvidence: []
        )

        workflowAdvanceTask = Task { [weak self] in
            await self?.planGuidedWorkflowFromScreen()
        }
    }

    private func showConfigurationNotice(_ message: String) {
        configurationNoticeClearTask?.cancel()
        configurationNoticeText = message

        configurationNoticeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.configurationNoticeText = nil
            }
        }
    }

    /// Conversation history so the AI remembers prior exchanges within a session.
    /// Each entry is the user's transcript and the assistant's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var textPromptShortcutCancellable: AnyCancellable?
    private var isKeyboardShortcutInteractionActive = false
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when all three required permissions (accessibility, screen recording,
    /// microphone) are granted. Used by the panel to show a single "all good" state.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission && hasScreenContentPermission
    }

    /// Whether the blue cursor overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// The AI model used for voice responses. Persisted to UserDefaults.
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedAIModel") ?? "gpt-5.4"

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedAIModel")
        openAIAPI.model = model
    }

    /// User preference for whether the Clicky cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isClickyCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isClickyCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isClickyCursorEnabled")

    func setClickyCursorEnabled(_ enabled: Bool) {
        isClickyCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isClickyCursorEnabled")
        transientHideTask?.cancel()
        transientHideTask = nil

        if enabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        } else {
            overlayWindowManager.hideOverlay()
            isOverlayVisible = false
        }
    }

    /// Onboarding is disabled — always returns true so the app skips
    /// the intro video and goes straight to the companion overlay.
    var hasCompletedOnboarding: Bool {
        get { return true }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has submitted their email during onboarding.
    @Published var hasSubmittedEmail: Bool = UserDefaults.standard.bool(forKey: "hasSubmittedEmail")

    /// Submits the user's email to FormSpark and identifies them in PostHog.
    func submitEmail(_ email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        hasSubmittedEmail = true
        UserDefaults.standard.set(true, forKey: "hasSubmittedEmail")

        // Identify user in PostHog
        PostHogSDK.shared.identify(trimmedEmail, userProperties: [
            "email": trimmedEmail
        ])

        // Submit to FormSpark
        Task {
            var request = URLRequest(url: URL(string: "https://submit-form.com/RWbGJxmIs")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmedEmail])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Clicky start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindShortcutTransitions()
        bindTextPromptShortcut()
        reloadCompanyConfig()
        // Eagerly touch the OpenAI API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = openAIAPI

        // If the user already completed onboarding AND all permissions are
        // still granted, show the cursor overlay immediately. If permissions
        // were revoked (e.g. signing change), don't show the cursor — the
        // panel will show the permissions UI instead.
        if hasCompletedOnboarding && allPermissionsGranted && isClickyCursorEnabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }
    }

    /// Called by BlueCursorView after the buddy finishes its pointing
    /// animation and returns to cursor-following mode.
    /// Triggers the onboarding sequence — dismisses the panel and restarts
    /// the overlay so the welcome animation and intro video play.
    func triggerOnboarding() {
        // Post notification so the panel manager can dismiss the panel
        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true

        ClickyAnalytics.trackOnboardingStarted()

        // Play Besaid theme at 60% volume, fade out after 1m 30s
        startOnboardingMusic()

        // Show the overlay for the first time — isFirstAppearance triggers
        // the welcome animation and onboarding video
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    /// Replays the onboarding experience from the "Watch Onboarding Again"
    /// footer link. Same flow as triggerOnboarding but the cursor overlay
    /// is already visible so we just restart the welcome animation and video.
    func replayOnboarding() {
        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)
        ClickyAnalytics.trackOnboardingReplayed()
        startOnboardingMusic()
        // Tear down any existing overlays and recreate with isFirstAppearance = true
        overlayWindowManager.hasShownOverlayBefore = false
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    private func stopOnboardingMusic() {
        onboardingMusicFadeTimer?.invalidate()
        onboardingMusicFadeTimer = nil
        onboardingMusicPlayer?.stop()
        onboardingMusicPlayer = nil
    }

    private func startOnboardingMusic() {
        stopOnboardingMusic()
        guard let musicURL = Bundle.main.url(forResource: "ff", withExtension: "mp3") else {
            print("⚠️ Clicky: ff.mp3 not found in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: musicURL)
            player.volume = 0.3
            player.play()
            self.onboardingMusicPlayer = player

            // After 1m 30s, fade the music out over 3s
            onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { [weak self] _ in
                self?.fadeOutOnboardingMusic()
            }
        } catch {
            print("⚠️ Clicky: Failed to play onboarding music: \(error)")
        }
    }

    private func fadeOutOnboardingMusic() {
        guard let player = onboardingMusicPlayer else { return }

        let fadeSteps = 30
        let fadeDuration: Double = 3.0
        let stepInterval = fadeDuration / Double(fadeSteps)
        let volumeDecrement = player.volume / Float(fadeSteps)
        var stepsRemaining = fadeSteps

        onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            stepsRemaining -= 1
            player.volume -= volumeDecrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.stop()
                self?.onboardingMusicPlayer = nil
                self?.onboardingMusicFadeTimer = nil
            }
        }
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementBubbleText = nil
    }

    func resetSession() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        stopWorkflowClickMonitor()
        workflowAdvanceTask?.cancel()
        workflowAdvanceTask = nil
        workflowAutoVerifyTask?.cancel()
        workflowAutoVerifyTask = nil

        buddyDictationManager.cancelCurrentDictation()
        ttsClient.stopPlayback()
        textPromptWindowManager.hide()

        conversationHistory.removeAll()
        workflowSession = nil
        isAwaitingWorkflowObjective = false
        lastTranscript = nil
        voiceState = .idle

        clearDetectedElementLocation()

        print("🧹 Session reset — cleared conversation history")
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        globalTextPromptShortcutMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        textPromptWindowManager.hide()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()
        stopWorkflowClickMonitor()
        workflowAdvanceTask?.cancel()
        workflowAutoVerifyTask?.cancel()

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        textPromptShortcutCancellable?.cancel()
        isKeyboardShortcutInteractionActive = false
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
            globalTextPromptShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
            globalTextPromptShortcutMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
            ClickyAnalytics.trackPermissionGranted(permission: "accessibility")
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
            ClickyAnalytics.trackPermissionGranted(permission: "screen_recording")
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
            ClickyAnalytics.trackPermissionGranted(permission: "microphone")
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
            ClickyAnalytics.trackAllPermissionsGranted()
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")
                    ClickyAnalytics.trackPermissionGranted(permission: "screen_content")

                    // If onboarding was already completed, show the cursor overlay now
                    if hasCompletedOnboarding && allPermissionsGranted && !isOverlayVisible && isClickyCursorEnabled {
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentAudioPowerLevel = powerLevel
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    private func bindTextPromptShortcut() {
        textPromptShortcutCancellable = globalTextPromptShortcutMonitor
            .shortcutPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.showTextPromptWindow()
            }
    }

    func showTextPromptWindow() {
        guard !showOnboardingVideo else { return }
        textPromptWindowManager.show(companionManager: self)
    }

    func submitTypedMessage(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        guard !buddyDictationManager.isDictationInProgress else { return }

        transientHideTask?.cancel()
        transientHideTask = nil

        if !isOverlayVisible {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }

        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

        if showOnboardingPrompt {
            withAnimation(.easeOut(duration: 0.3)) {
                onboardingPromptOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.showOnboardingPrompt = false
                self.onboardingPromptText = ""
            }
        }

        clearDetectedElementLocation()
        lastTranscript = trimmedMessage
        print("⌨️ Companion received typed message: \(trimmedMessage)")
        ClickyAnalytics.trackUserMessageSent(transcript: trimmedMessage)
        handleIncomingUserMessage(trimmedMessage)
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            guard !isKeyboardShortcutInteractionActive else { return }
            guard !buddyDictationManager.isDictationInProgress else { return }
            // Don't register push-to-talk while the onboarding video is playing
            guard !showOnboardingVideo else { return }
            isKeyboardShortcutInteractionActive = true

            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isClickyCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            ttsClient.stopPlayback()
            clearDetectedElementLocation()

            // Dismiss the onboarding prompt if it's showing
            if showOnboardingPrompt {
                withAnimation(.easeOut(duration: 0.3)) {
                    onboardingPromptOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showOnboardingPrompt = false
                    self.onboardingPromptText = ""
                }
            }
    

            ClickyAnalytics.trackPushToTalkStarted()

            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        ClickyAnalytics.trackUserMessageSent(transcript: finalTranscript)
                        self?.handleIncomingUserMessage(finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            ClickyAnalytics.trackPushToTalkReleased()
            isKeyboardShortcutInteractionActive = false
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're pookify, a friendly always-on companion that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    rules:
    - default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out — give a thorough, detailed explanation with no length limit.
    - all lowercase, casual, warm. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" — those are dead ends that force the user to just say yes.
    - instead, when it fits naturally, end by planting a seed — mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing:
    you have a small blue triangle cursor that can fly to and point at things on screen. use it whenever pointing would genuinely help the user — if they're asking how to do something, looking for a menu, trying to find a button, or need help navigating an app, point at the relevant element. err on the side of pointing rather than not pointing, because it makes your help way more useful and concrete. if the user asks anything like "where", "what do i click", "show me", "point at", "find", "open", "press", "select", or "how do i", you should almost always return a real coordinate tag instead of [POINT:none].

    don't point at things when it would be pointless — like if the user asks a general knowledge question, or the conversation has nothing to do with what's on screen, or you'd just be pointing at something obvious they're already looking at. but if there's a specific UI element, menu, button, or area on screen that's relevant to what you're helping with, point at it.

    when you point, append a coordinate tag at the very end of your response, AFTER your spoken text. do NOT use raw screenshot pixels. use a normalized 0-999 grid instead. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward.

    format: [POINT:x,y:label] where x,y are integer coordinates on a 0-999 grid, and label is a short 1-3 word description of the element (like "search bar" or "save button"). x=0 is the far left edge, x=999 is the far right edge. y=0 is the top edge, y=999 is the bottom edge. always point to the CENTER of the target element, not its edge.

    if you receive multiple screens and the target is not on the primary focus screen, you MUST append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if pointing wouldn't help, append [POINT:none].

    examples:
    - user asks how to color grade in final cut: "you'll want to open the color inspector — it's right up in the top right area of the toolbar. click that and you'll get all the color wheels and curves. [POINT:812,96:color inspector]"
    - user asks what html is: "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
    - user asks how to commit in xcode: "see that source control menu up top? click that and hit commit, or you can use command option c as a shortcut. [POINT:244,88:source control]"
    - element is on screen 2 (not where cursor is): "that's over on your other monitor — see the terminal window? [POINT:503,462:terminal:screen2]"
    """

    private static let guidedWorkflowPlanningSystemPrompt = """
    you are planning a short guided workflow for a screen-aware desktop assistant.

    return ONLY valid json with this exact shape:
    {
      "objective": "string",
      "steps": [
        {
          "id": 1,
          "goal": "string",
          "visualAnchor": "string",
          "successCriteria": "string"
        }
      ],
      "stopCondition": "string"
    }

    rules:
    - create three to five steps only
    - each step must be atomic and visually verifiable from a screenshot
    - successCriteria must describe what should visibly change on screen
    - no markdown, no prose, no code fences, only json
    """

    private static let guidedWorkflowStepSystemPrompt = """
    you're pookify, guiding the user through a workflow one step at a time.

    respond with one short spoken instruction for the CURRENT step only, then append a point tag if pointing helps.

    rules:
    - all lowercase, warm, concise
    - describe only the next immediate action
    - if pointing helps, use normalized 0-999 coordinates in [POINT:x,y:label]
    - if pointing would not help, append [POINT:none]
    - no lists, no step numbers, no markdown
    - keep the instruction actionable and screen-grounded
    """

    private static let guidedWorkflowVerificationSystemPrompt = """
    you are verifying whether a guided workflow step succeeded based on a new screenshot.

    return ONLY valid json with this exact shape:
    {
      "status": "pass" | "fail" | "unsure",
      "evidence": ["string"],
      "mismatchType": "string or null",
      "nextAction": "string or null"
    }

    rules:
    - use pass only when the expected visible change clearly happened
    - use fail when the screenshot clearly shows the user is elsewhere or the step is incomplete
    - use unsure when the screenshot is ambiguous
    - nextAction should be a short correction or recovery hint when status is fail or unsure
    - no markdown, no prose, no code fences, only json
    """

    private func handleIncomingUserMessage(_ message: String) {
        if isGuidedWorkflowActive {
            requestGuidedWorkflowHelp()
            return
        }

        if isAwaitingWorkflowObjective || messageRequestsGuidedWorkflow(message) {
            startGuidedWorkflow(withObjective: message)
        } else {
            sendTranscriptToAIWithScreenshot(transcript: message)
        }
    }

    private func messageRequestsGuidedWorkflow(_ message: String) -> Bool {
        let normalizedMessage = message.lowercased()
        let workflowPhrases = [
            "guide me",
            "walk me through",
            "step by step",
            "help me through",
            "guide me through",
            "walk me step by step"
        ]
        return workflowPhrases.contains { normalizedMessage.contains($0) }
    }

    private func makeLabeledImages(from screenCaptures: [CompanionScreenCapture]) -> [(data: Data, label: String)] {
        screenCaptures.map { capture in
            let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
            return (data: capture.imageData, label: capture.label + dimensionInfo)
        }
    }

    private func enrichPromptWithKnowledge(for prompt: String) async -> String {
        let knowledgeResponse = await knowledgeBaseClient.queryRelevantChunks(for: prompt)
        let retrievedContext = knowledgeBaseClient.formatChunksForPrompt(knowledgeResponse?.chunks ?? [])

        var enrichedPrompt = ""
        if let retrievedContext {
            enrichedPrompt += retrievedContext + "\n\n"
        }
        if let customInstructions = knowledgeResponse?.custom_instructions, !customInstructions.isEmpty {
            enrichedPrompt += "<company_instructions>\n\(customInstructions)\n</company_instructions>\n\n"
        }
        enrichedPrompt += prompt
        return enrichedPrompt
    }

    private static let guidedWorkflowScreenContextPrompt = """
    look at the user's screen and determine what they are currently trying to do or what task they might need help with. then create a guided workflow plan to help them complete that task.

    return ONLY valid json with this exact shape:
    {
      "objective": "string — what the user appears to be doing",
      "steps": [
        {
          "id": 1,
          "goal": "string",
          "visualAnchor": "string",
          "successCriteria": "string"
        }
      ],
      "stopCondition": "string"
    }

    rules:
    - infer the objective from what is visible on screen
    - create three to five steps only
    - each step must be atomic and visually verifiable from a screenshot
    - successCriteria must describe what should visibly change on screen
    - no markdown, no prose, no code fences, only json
    """

    private func planGuidedWorkflowFromScreen() async {
        voiceState = .processing

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard !Task.isCancelled else { return }

            let labeledImages = makeLabeledImages(from: screenCaptures)
            let enrichedPrompt = await enrichPromptWithKnowledge(for: "Look at my screen and help me with what I'm currently doing.")

            let (planText, _) = try await openAIAPI.analyzeImage(
                images: labeledImages,
                systemPrompt: Self.guidedWorkflowScreenContextPrompt,
                userPrompt: enrichedPrompt,
                maxCompletionTokens: 2048
            )

            let workflowPlan = try Self.decodeWorkflowJSON(GuidedWorkflowPlan.self, from: planText)
            guard !workflowPlan.steps.isEmpty else {
                throw NSError(domain: "GuidedWorkflow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Planning returned no steps"])
            }

            let session = GuidedWorkflowSession(
                objective: workflowPlan.objective,
                steps: workflowPlan.steps,
                stopCondition: workflowPlan.stopCondition,
                currentStepIndex: 0,
                phase: .awaitingUserAction,
                lastSpokenInstruction: nil,
                lastVerificationEvidence: []
            )

            workflowSession = session
            await deliverGuidedWorkflowStep(session: session, extraGuidance: nil)
        } catch {
            workflowSession?.phase = .blocked
            voiceState = .idle
            showConfigurationNotice("Workflow planning failed")
            print("⚠️ Workflow screen-context planning error: \(error)")
        }
    }

    private func planGuidedWorkflow(for objective: String) async {
        voiceState = .processing

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard !Task.isCancelled else { return }

            let labeledImages = makeLabeledImages(from: screenCaptures)
            let planningPrompt = await enrichPromptWithKnowledge(for: "Create a guided workflow plan for this user goal: \(objective)")

            let (planText, _) = try await openAIAPI.analyzeImage(
                images: labeledImages,
                systemPrompt: Self.guidedWorkflowPlanningSystemPrompt,
                userPrompt: planningPrompt,
                maxCompletionTokens: 2048
            )

            print("📋 Workflow plan raw: \(planText.prefix(300))...")
            let workflowPlan = try Self.decodeWorkflowJSON(GuidedWorkflowPlan.self, from: planText)
            print("📋 Workflow plan parsed: \(workflowPlan.objective) — \(workflowPlan.steps.count) steps")
            guard !workflowPlan.steps.isEmpty else {
                throw NSError(domain: "GuidedWorkflow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Planning returned no steps"])
            }

            let session = GuidedWorkflowSession(
                objective: workflowPlan.objective,
                steps: workflowPlan.steps,
                stopCondition: workflowPlan.stopCondition,
                currentStepIndex: 0,
                phase: .awaitingUserAction,
                lastSpokenInstruction: nil,
                lastVerificationEvidence: []
            )

            workflowSession = session
            await deliverGuidedWorkflowStep(session: session, extraGuidance: nil)
        } catch {
            workflowSession?.phase = .blocked
            voiceState = .idle
            showConfigurationNotice("Workflow planning failed")
            print("⚠️ Workflow planning error: \(error)")
        }
    }

    private func deliverGuidedWorkflowStep(session: GuidedWorkflowSession, extraGuidance: String?) async {
        guard let currentStep = session.currentStep else {
            print("⚠️ Workflow: no current step at index \(session.currentStepIndex)")
            return
        }

        print("🚶 Workflow step \(session.stepProgressText): \(currentStep.goal)")
        voiceState = .processing
        ttsClient.stopPlayback()
        clearDetectedElementLocation()

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard !Task.isCancelled else { return }

            let labeledImages = makeLabeledImages(from: screenCaptures)
            var stepPrompt = "workflow objective: \(session.objective)\n"
            stepPrompt += "current step: \(session.stepProgressText)\n"
            stepPrompt += "step goal: \(currentStep.goal)\n"
            stepPrompt += "visual anchor: \(currentStep.visualAnchor)\n"
            stepPrompt += "success criteria: \(currentStep.successCriteria)\n"
            if let extraGuidance, !extraGuidance.isEmpty {
                stepPrompt += "extra guidance: \(extraGuidance)\n"
            }

            let enrichedStepPrompt = await enrichPromptWithKnowledge(for: stepPrompt)

            let (fullResponseText, _) = try await openAIAPI.analyzeImageStreaming(
                images: labeledImages,
                systemPrompt: Self.guidedWorkflowStepSystemPrompt,
                userPrompt: enrichedStepPrompt,
                onTextChunk: { _ in }
            )

            guard !Task.isCancelled else { return }

            let parseResult = Self.parsePointingCoordinates(from: fullResponseText)
            let spokenText = parseResult.spokenText

            let targetScreenCapture: CompanionScreenCapture? = {
                if let screenNumber = parseResult.screenNumber,
                   screenNumber >= 1 && screenNumber <= screenCaptures.count {
                    return screenCaptures[screenNumber - 1]
                }
                return screenCaptures.first(where: { $0.isCursorScreen })
            }()

            if let pointCoordinate = parseResult.coordinate,
               let targetScreenCapture {
                let globalLocation = Self.globalScreenLocation(
                    fromNormalizedPoint: pointCoordinate,
                    screenCapture: targetScreenCapture
                )
                voiceState = .idle
                detectedElementScreenLocation = globalLocation
                detectedElementDisplayFrame = targetScreenCapture.displayFrame
                detectedElementBubbleText = parseResult.elementLabel
            }

            workflowSession?.phase = .awaitingUserAction
            workflowSession?.lastSpokenInstruction = spokenText

            if !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await ttsClient.speakText(spokenText)
                voiceState = .responding
            }

            // Wait for TTS to finish, then auto-verify after a delay
            scheduleWorkflowAutoVerify()
        } catch {
            workflowSession?.phase = .blocked
            voiceState = .idle
            showConfigurationNotice("Workflow step failed")
            print("⚠️ Workflow step error: \(error)")
        }
    }

    private func scheduleWorkflowAutoVerify() {
        workflowAutoVerifyTask?.cancel()
        stopWorkflowClickMonitor()

        workflowAutoVerifyTask = Task { [weak self] in
            while self?.ttsClient.isPlaying == true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }

            while self?.detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.startWorkflowClickMonitor()
            }
        }
    }

    private func startWorkflowClickMonitor() {
        stopWorkflowClickMonitor()

        workflowClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                guard self.workflowSession?.phase == .awaitingUserAction else { return }
                self.stopWorkflowClickMonitor()

                try? await Task.sleep(nanoseconds: 1_500_000_000)

                self.workflowAutoVerifyTask?.cancel()
                self.workflowAdvanceTask?.cancel()
                self.workflowAdvanceTask = Task { [weak self] in
                    await self?.verifyAndAdvanceGuidedWorkflow(extraGuidance: nil)
                }
            }
        }
    }

    private func stopWorkflowClickMonitor() {
        if let monitor = workflowClickMonitor {
            NSEvent.removeMonitor(monitor)
            workflowClickMonitor = nil
        }
    }

    private func verifyAndAdvanceGuidedWorkflow(extraGuidance: String?) async {
        guard var workflowSession, let currentStep = workflowSession.currentStep else { return }

        workflowSession.phase = .verifying
        self.workflowSession = workflowSession
        voiceState = .processing

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard !Task.isCancelled else { return }

            let labeledImages = makeLabeledImages(from: screenCaptures)
            var verificationPrompt = "workflow objective: \(workflowSession.objective)\n"
            verificationPrompt += "current step: \(workflowSession.stepProgressText)\n"
            verificationPrompt += "step goal: \(currentStep.goal)\n"
            verificationPrompt += "success criteria: \(currentStep.successCriteria)\n"
            if let lastInstruction = workflowSession.lastSpokenInstruction {
                verificationPrompt += "last instruction: \(lastInstruction)\n"
            }
            if let extraGuidance, !extraGuidance.isEmpty {
                verificationPrompt += "extra guidance: \(extraGuidance)\n"
            }

            let enrichedVerificationPrompt = await enrichPromptWithKnowledge(for: verificationPrompt)

            let (verificationText, _) = try await openAIAPI.analyzeImage(
                images: labeledImages,
                systemPrompt: Self.guidedWorkflowVerificationSystemPrompt,
                userPrompt: enrichedVerificationPrompt
            )

            let verification = try Self.decodeWorkflowJSON(GuidedWorkflowVerification.self, from: verificationText)
            workflowSession.lastVerificationEvidence = verification.evidence

            let shouldAdvance = verification.status == "pass" || verification.status == "unsure"

            if shouldAdvance {
                if workflowSession.currentStepIndex + 1 >= workflowSession.steps.count {
                    workflowSession.phase = .completed
                    self.workflowSession = workflowSession
                    voiceState = .idle
                    showConfigurationNotice("Workflow completed")
                    try? await ttsClient.speakText("nice, that workflow is done.")
                    return
                }

                workflowSession.currentStepIndex += 1
                workflowSession.phase = .awaitingUserAction
                self.workflowSession = workflowSession
                print("✅ Workflow step verified — advancing to step \(workflowSession.stepProgressText)")
                await deliverGuidedWorkflowStep(session: workflowSession, extraGuidance: nil)
            } else {
                workflowSession.phase = .blocked
                self.workflowSession = workflowSession
                print("❌ Workflow step failed verification — waiting for user action")
                let recoveryMessage = verification.nextAction ?? "that step doesn't look complete yet. try again or press i'm stuck if you need help."
                try? await ttsClient.speakText(recoveryMessage)
                voiceState = .idle
                startWorkflowClickMonitor()
            }
        } catch {
            self.workflowSession?.phase = .blocked
            voiceState = .idle
            showConfigurationNotice("Workflow check failed")
            print("⚠️ Workflow verification error: \(error)")
        }
    }

    private static func decodeWorkflowJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIndex = trimmedText.firstIndex(of: "{") else {
            throw NSError(domain: "GuidedWorkflow", code: -2, userInfo: [NSLocalizedDescriptionKey: "No JSON object found in response"])
        }

        var jsonText = String(trimmedText[startIndex...])

        if JSONSerialization.isValidJSONObject(try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) == false {
            jsonText = repairTruncatedJSON(jsonText)
        }

        let data = Data(jsonText.utf8)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let repairedText = repairTruncatedJSON(jsonText)
            let repairedData = Data(repairedText.utf8)
            return try JSONDecoder().decode(T.self, from: repairedData)
        }
    }

    private static func repairTruncatedJSON(_ json: String) -> String {
        var repaired = json

        var inString = false
        var lastValidIndex = repaired.startIndex
        var prevChar: Character?

        for index in repaired.indices {
            let char = repaired[index]
            if char == "\"" && prevChar != "\\" {
                inString = !inString
            }
            lastValidIndex = index
            prevChar = char
        }

        if inString {
            repaired.append("\"")
        }

        var openBraces = 0
        var openBrackets = 0
        inString = false
        prevChar = nil

        for char in repaired {
            if char == "\"" && prevChar != "\\" {
                inString = !inString
            }
            if !inString {
                if char == "{" { openBraces += 1 }
                if char == "}" { openBraces -= 1 }
                if char == "[" { openBrackets += 1 }
                if char == "]" { openBrackets -= 1 }
            }
            prevChar = char
        }

        for _ in 0..<openBrackets { repaired += "]" }
        for _ in 0..<openBraces { repaired += "}" }

        print("🔧 Repaired truncated JSON: closed \(openBrackets) brackets and \(openBraces) braces")
        return repaired
    }

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to OpenAI,
    /// and plays the response aloud via OpenAI TTS. The cursor stays in
    /// the spinner/processing state until TTS audio begins playing.
    /// The AI response may include a [POINT:x,y:label] tag which triggers
    /// the buddy to fly to that element on screen.
    private func sendTranscriptToAIWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        ttsClient.stopPlayback()

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Capture all connected screens so the AI has full context
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                guard !Task.isCancelled else { return }

                // Build image labels with the actual screenshot pixel dimensions
                // so the AI's coordinate space matches the image it sees. We
                // scale from screenshot pixels to display points ourselves.
                let labeledImages = screenCaptures.map { capture in
                    let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                    return (data: capture.imageData, label: capture.label + dimensionInfo)
                }
                print("📸 Captured \(labeledImages.count) screenshot(s) for OpenAI: \(labeledImages.map { $0.label }.joined(separator: " | "))")

                // Pass conversation history so the AI remembers prior exchanges
                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                let knowledgeResponse = await knowledgeBaseClient.queryRelevantChunks(for: transcript)
                let retrievedContext = knowledgeBaseClient.formatChunksForPrompt(knowledgeResponse?.chunks ?? [])

                var enrichedUserPrompt = ""
                if let retrievedContext {
                    enrichedUserPrompt += retrievedContext + "\n\n"
                }
                if let customInstructions = knowledgeResponse?.custom_instructions, !customInstructions.isEmpty {
                    enrichedUserPrompt += "<company_instructions>\n\(customInstructions)\n</company_instructions>\n\n"
                }
                enrichedUserPrompt += transcript

                let (fullResponseText, _) = try await openAIAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.companionVoiceResponseSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: enrichedUserPrompt,
                    onTextChunk: { _ in
                        // No streaming text display — spinner stays until TTS plays
                    }
                )

                guard !Task.isCancelled else { return }

                // Parse the [POINT:...] tag from the AI response
                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)
                let spokenText = parseResult.spokenText
                print("🧭 Point tag parse: coordinate=\(parseResult.coordinate.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none"), label=\(parseResult.elementLabel ?? "none"), screen=\(parseResult.screenNumber.map(String.init) ?? "cursor")")

                // Handle element pointing if the AI returned coordinates.
                // Switch to idle BEFORE setting the location so the triangle
                // becomes visible and can fly to the target. Without this, the
                // spinner hides the triangle and the flight animation is invisible.
                let hasPointCoordinate = parseResult.coordinate != nil
                if hasPointCoordinate {
                    voiceState = .idle
                }

                // Pick the screen capture matching the AI's screen number,
                // falling back to the cursor screen if not specified.
                let targetScreenCapture: CompanionScreenCapture? = {
                    if let screenNumber = parseResult.screenNumber,
                       screenNumber >= 1 && screenNumber <= screenCaptures.count {
                        return screenCaptures[screenNumber - 1]
                    }
                    return screenCaptures.first(where: { $0.isCursorScreen })
                }()

                if let pointCoordinate = parseResult.coordinate,
                   let targetScreenCapture {
                    let globalLocation = Self.globalScreenLocation(
                        fromNormalizedPoint: pointCoordinate,
                        screenCapture: targetScreenCapture
                    )

                    detectedElementScreenLocation = globalLocation
                    detectedElementDisplayFrame = targetScreenCapture.displayFrame
                    ClickyAnalytics.trackElementPointed(elementLabel: parseResult.elementLabel)
                    print("🎯 Element pointing: (\(Int(pointCoordinate.x)), \(Int(pointCoordinate.y))) → \"\(parseResult.elementLabel ?? "element")\"")
                } else {
                    print("🎯 Element pointing: \(parseResult.elementLabel ?? "no element")")
                }

                // Record usage for token/credit tracking
                let estimatedTokens = UsageTracker.estimateTokenCount(forText: transcript)
                    + UsageTracker.estimateTokenCount(forText: spokenText)
                usageTracker?.recordMessage(estimatedTokenCount: estimatedTokens)

                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: spokenText
                ))

                // Keep only the last 10 exchanges to avoid unbounded context growth
                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")

                ClickyAnalytics.trackAIResponseReceived(response: spokenText)

                // Play the response via TTS. Keep the spinner (processing state)
                // until the audio actually starts playing, then switch to responding.
                if !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try await ttsClient.speakText(spokenText)
                        // speakText returns after player.play() — audio is now playing
                        voiceState = .responding
                    } catch {
                        ClickyAnalytics.trackTTSError(error: error.localizedDescription)
                        print("⚠️ OpenAI TTS error: \(error)")
                    }
                }
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch {
                ClickyAnalytics.trackResponseError(error: error.localizedDescription)
                print("⚠️ Companion response error: \(error)")
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// If the cursor is in transient mode (user toggled "Show Clicky" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isClickyCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while ttsClient.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    // MARK: - Point Tag Parsing

    /// Result of parsing a [POINT:...] tag from the AI response.
    struct PointingParseResult {
        /// The response text with the [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The parsed pixel coordinate, or nil if the AI said "none" or no tag was found.
        let coordinate: CGPoint?
        /// Short label describing the element (e.g. "run button"), or "none".
        let elementLabel: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// Parses a [POINT:x,y:label:screenN] or [POINT:none] tag from the end of the AI response.
    /// Returns the spoken text (tag removed) and the optional coordinate + label + screen number.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2]
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            // No tag found at all
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        // Remove the tag from the spoken text
        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's [POINT:none]
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
        }

        var elementLabel: String? = nil
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int? = nil
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return PointingParseResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }

    // MARK: - Onboarding Video

    /// Sets up the onboarding video player, starts playback, and schedules
    /// the demo interaction at 40s. Called by BlueCursorView when onboarding starts.
    func setupOnboardingVideo() {
        guard let videoURL = URL(string: "https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8") else { return }

        let player = AVPlayer(url: videoURL)
        player.isMuted = false
        player.volume = 0.0
        self.onboardingVideoPlayer = player
        self.showOnboardingVideo = true
        self.onboardingVideoOpacity = 0.0

        // Start playback immediately — the video plays while invisible,
        // then we fade in both the visual and audio over 1s.
        player.play()

        // Wait for SwiftUI to mount the view, then set opacity to 1.
        // The .animation modifier on the view handles the actual animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onboardingVideoOpacity = 1.0
            // Fade audio volume from 0 → 1 over 2s to match visual fade
            self.fadeInVideoAudio(player: player, targetVolume: 1.0, duration: 2.0)
        }

        // At 40 seconds into the video, trigger the onboarding demo where
        // Clicky flies to something interesting on screen and comments on it
        let demoTriggerTime = CMTime(seconds: 40, preferredTimescale: 600)
        onboardingDemoTimeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: demoTriggerTime)],
            queue: .main
        ) { [weak self] in
            ClickyAnalytics.trackOnboardingDemoTriggered()
            self?.performOnboardingDemoInteraction()
        }

        // Fade out and clean up when the video finishes
        onboardingVideoEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            ClickyAnalytics.trackOnboardingVideoCompleted()
            self.onboardingVideoOpacity = 0.0
            // Wait for the 2s fade-out animation to complete before tearing down
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.tearDownOnboardingVideo()
                // After the video disappears, stream in the prompt to try talking
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.startOnboardingPromptStream()
                }
            }
        }
    }

    func tearDownOnboardingVideo() {
        showOnboardingVideo = false
        if let timeObserver = onboardingDemoTimeObserver {
            onboardingVideoPlayer?.removeTimeObserver(timeObserver)
            onboardingDemoTimeObserver = nil
        }
        onboardingVideoPlayer?.pause()
        onboardingVideoPlayer = nil
        if let observer = onboardingVideoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingVideoEndObserver = nil
        }
    }

    private func startOnboardingPromptStream() {
        let message = "press control + option and introduce yourself"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }

    /// Gradually raises an AVPlayer's volume from its current level to the
    /// target over the specified duration, creating a smooth audio fade-in.
    private func fadeInVideoAudio(player: AVPlayer, targetVolume: Float, duration: Double) {
        let steps = 20
        let stepInterval = duration / Double(steps)
        let volumeIncrement = (targetVolume - player.volume) / Float(steps)
        var stepsRemaining = steps

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { timer in
            stepsRemaining -= 1
            player.volume += volumeIncrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.volume = targetVolume
            }
        }
    }

    // MARK: - Onboarding Demo Interaction

    private static let onboardingDemoSystemPrompt = """
    you're pookify, a small blue cursor buddy living on the user's screen. you're showing off during onboarding — look at their screen and find ONE specific, concrete thing to point at. pick something with a clear name or identity: a specific app icon (say its name), a specific word or phrase of text you can read, a specific filename, a specific button label, a specific tab title, a specific image you can describe. do NOT point at vague things like "a window" or "some text" — be specific about exactly what you see.

    make a short quirky 3-6 word observation about the specific thing you picked — something fun, playful, or curious that shows you actually read/recognized it. no emojis ever. NEVER quote or repeat text you see on screen — just react to it. keep it to 6 words max, no exceptions.

    CRITICAL COORDINATE RULE: you MUST only pick elements near the CENTER of the screen. your x coordinate must be between 20%-80% of the image width. your y coordinate must be between 20%-80% of the image height. do NOT pick anything in the top 20%, bottom 20%, left 20%, or right 20% of the screen. no menu bar items, no dock icons, no sidebar items, no items near any edge. only things clearly in the middle area of the screen. if the only interesting things are near the edges, pick something boring in the center instead.

    respond with ONLY your short comment followed by the coordinate tag. nothing else. all lowercase.

    format: your comment [POINT:x,y:label]

    use a normalized 0-999 grid, not raw screenshot pixels. origin (0,0) is top-left. x=999 is the far right edge. y=999 is the bottom edge. point to the center of the thing you picked.
    """

    /// Captures a screenshot and asks the AI to find something interesting to
    /// point at, then triggers the buddy's flight animation. Used during
    /// onboarding to demo the pointing feature while the intro video plays.
    func performOnboardingDemoInteraction() {
        // Don't interrupt an active voice response
        guard voiceState == .idle || voiceState == .responding else { return }

        Task {
            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                // Only send the cursor screen so the AI can't pick something
                // on a different monitor that we can't point at.
                guard let cursorScreenCapture = screenCaptures.first(where: { $0.isCursorScreen }) else {
                    print("🎯 Onboarding demo: no cursor screen found")
                    return
                }

                let dimensionInfo = " (image dimensions: \(cursorScreenCapture.screenshotWidthInPixels)x\(cursorScreenCapture.screenshotHeightInPixels) pixels)"
                let labeledImages = [(data: cursorScreenCapture.imageData, label: cursorScreenCapture.label + dimensionInfo)]

                let (fullResponseText, _) = try await openAIAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.onboardingDemoSystemPrompt,
                    userPrompt: "look around my screen and find something interesting to point at",
                    onTextChunk: { _ in }
                )

                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)

                guard let pointCoordinate = parseResult.coordinate else {
                    print("🎯 Onboarding demo: no element to point at")
                    return
                }

                let globalLocation = Self.globalScreenLocation(
                    fromNormalizedPoint: pointCoordinate,
                    screenCapture: cursorScreenCapture
                )

                // Set custom bubble text so the pointing animation uses the AI's
                // comment instead of a random phrase
                detectedElementBubbleText = parseResult.spokenText
                detectedElementScreenLocation = globalLocation
                detectedElementDisplayFrame = cursorScreenCapture.displayFrame
                print("🎯 Onboarding demo: pointing at \"\(parseResult.elementLabel ?? "element")\" — \"\(parseResult.spokenText)\"")
            } catch {
                print("⚠️ Onboarding demo error: \(error)")
            }
        }
    }

    private static func globalScreenLocation(
        fromNormalizedPoint point: CGPoint,
        screenCapture: CompanionScreenCapture
    ) -> CGPoint {
        let displayWidth = CGFloat(screenCapture.displayWidthInPoints)
        let displayHeight = CGFloat(screenCapture.displayHeightInPoints)
        let displayFrame = screenCapture.displayFrame

        let clampedNormalizedX = max(0, min(point.x, 999))
        let clampedNormalizedY = max(0, min(point.y, 999))

        let displayLocalX = clampedNormalizedX / 999.0 * max(displayWidth - 1, 1)
        let displayLocalY = clampedNormalizedY / 999.0 * max(displayHeight - 1, 1)

        let appKitY = displayHeight - displayLocalY

        return CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitY + displayFrame.origin.y
        )
    }
}
