//
//  PrivacyAssistant.swift
//
//  Copy the whole PrivacyAssistant folder into any UIKit project (iOS 18+), add
//  NSCameraUsageDescription to Info.plist, then:
//
//      private lazy var privacy = PrivacyAssistant(hostView: view)
//
//      await privacy.start()   // asks for camera permission if needed; returns false if it could not start
//      await privacy.stop()    // safe to call any time, any number of times
//
//  While running, the front camera counts faces on-device. If more than one face stays in view,
//  a warning banner slides in over `hostView`. Its "Hide content" button covers the screen with a
//  shield until the user taps "Show content". Nothing is recorded, saved or sent anywhere.
//  This is a heuristic: it cannot prove that anyone is actually looking at the screen.
//

import AVFoundation
import UIKit

@MainActor
final class PrivacyAssistant {

    private enum Phase { case stopped, starting, running }

    private let overlay = PrivacyOverlayView()
    private let camera = PrivacyCamera()
    private var rules = PrivacyRules()
    private var phase = Phase.stopped
    /// Bumped by every stop, so a start that was waiting on an `await` knows it was cancelled.
    private var generation = 0
    private var consumer: Task<Void, Never>?
    private var backgroundObserver: (any NSObjectProtocol)?

    var isRunning: Bool { phase == .running }

    /// Optional. Called about every 0.3s while running with the number of faces in view,
    /// and once with `nil` when detection stops. Handy for a status label.
    var onFaceCountChange: (@MainActor (Int?) -> Void)?

    /// Adds the (invisible until needed) banner and shield overlay on top of `hostView`.
    init(hostView: UIView) {
        hostView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor)
        ])
    }

    /// Safety net: if the owner goes away without calling `stop()`, the camera is still released.
    isolated deinit {
        consumer?.cancel()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        let camera = camera
        Task { await camera.stop() }
    }

    /// Starts detection. Does nothing if already starting or running.
    /// - Returns: `true` if detection is running or already on its way, `false` if permission was
    ///   denied or the camera failed.
    @discardableResult
    func start() async -> Bool {
        guard phase == .stopped else { return true } // a repeated tap is not a failure
        phase = .starting
        generation += 1
        let token = generation
        overlay.superview?.bringSubviewToFront(overlay) // stay above views added after init

        guard await Self.hasCameraAccess(), token == generation else {
            if token == generation { phase = .stopped }
            return false
        }
        do {
            let samples = try await camera.start()
            guard token == generation else { return false } // stop() was called meanwhile and releases the camera
            phase = .running
            observeBackground()
            consumer = Task { [weak self] in
                for await sample in samples {
                    guard let self, self.generation == token else { return }
                    self.handle(sample)
                }
                // The stream also ends if the camera fails at runtime. Clean up in that case.
                if let self, self.generation == token { await self.stop() }
            }
            return true
        } catch {
            if token == generation { phase = .stopped }
            return false
        }
    }

    /// Stops detection and releases the camera. Does nothing if already stopped.
    /// A hidden-content shield stays up until the user taps "Show content".
    func stop() async {
        guard phase != .stopped else { return }
        generation += 1
        phase = .stopped
        consumer?.cancel()
        consumer = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil
        rules = PrivacyRules()
        overlay.hideWarning()
        onFaceCountChange?(nil)
        await camera.stop()
    }

    // MARK: - Private

    private func handle(_ sample: FaceSample) {
        #if DEBUG
        // Debug builds only, and only counts: how many faces are seen vs. how many count as looking at the screen.
        print("PrivacyAssistant: \(sample.totalFaces) face(s) seen, counted \(sample.faceCount)")
        #endif
        onFaceCountChange?(sample.faceCount)
        switch rules.update(faceCount: sample.faceCount, at: sample.time) {
        case .raise: overlay.showWarning()
        case .clear: overlay.hideWarning()
        case nil: break
        }
    }

    /// iOS takes the camera away in the background. Stop cleanly and never restart without a user tap.
    private func observeBackground() {
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stop() }
        }
    }

    private static func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}

// MARK: - Rules

/// Turns noisy per-frame face counts into "raise the warning" / "clear it".
/// Pure value type with no UIKit or camera dependency, so it is easy to unit test.
nonisolated struct PrivacyRules {

    nonisolated enum Change { case raise, clear }

    /// Two or more faces must keep showing up for this long before warning (ignores one-frame false positives).
    var onset: TimeInterval = 1.0
    /// Samples with fewer faces are tolerated for this long inside a sighting, so detector flicker
    /// does not restart the onset timer. A longer gap starts the onset over.
    var gapTolerance: TimeInterval = 1.0
    /// Exactly one face must be seen continuously this long before an active warning is cleared.
    var recovery: TimeInterval = 3.0

    private var multipleFacesSince: TimeInterval?
    private var lastMultipleFaces: TimeInterval?
    private var singleFaceSince: TimeInterval?
    private var isWarning = false

    mutating func update(faceCount: Int, at time: TimeInterval) -> Change? {
        if faceCount >= 2 {
            singleFaceSince = nil
            guard !isWarning else { return nil } // already warning: no repeats
            if let last = lastMultipleFaces, time - last > gapTolerance { multipleFacesSince = nil }
            lastMultipleFaces = time
            let start = multipleFacesSince ?? time
            multipleFacesSince = start
            guard time - start >= onset else { return nil }
            isWarning = true
            multipleFacesSince = nil
            lastMultipleFaces = nil
            return .raise
        }

        // Fewer than two faces. Only a gap longer than the tolerance ends a pending sighting.
        if let last = lastMultipleFaces, time - last > gapTolerance {
            multipleFacesSince = nil
            lastMultipleFaces = nil
        }
        // Recovery needs exactly one face. Nobody in view cannot conclude anything: keep the
        // warning and restart the recovery timer.
        guard faceCount == 1, isWarning else {
            singleFaceSince = nil
            return nil
        }
        let start = singleFaceSince ?? time
        singleFaceSince = start
        guard time - start >= recovery else { return nil }
        isWarning = false
        singleFaceSince = nil
        return .clear
    }
}
