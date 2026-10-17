//
//  PrivacyCamera.swift
//
//  Front camera + Vision face counting. Frames are analyzed on the capture queue and discarded.
//  Only a face count leaves this file. Nothing is stored, logged or sent anywhere.
//

import AVFoundation
import Synchronization
import Vision

/// One face found by Vision, reduced to what the decision needs. No image data.
nonisolated struct DetectedFace: Sendable {
    let width: CGFloat  // fraction of the frame width, 0...1
    let height: CGFloat // fraction of the frame height, 0...1
    let yaw: Double?    // head turn left/right in radians, 0 = facing the camera
    let pitch: Double?  // head tilt up/down in radians, 0 = facing the camera
}

/// One analysis result.
///
/// `faceCount` is "you plus everyone else who is looking at the screen":
/// - the largest (closest) face is assumed to be the owner and always counts,
/// - every other face counts only if its head is turned toward the camera, which sits at the screen,
/// - very small faces (far away, posters) are ignored.
/// So people merely walking past, facing away or sideways, are not counted.
nonisolated struct FaceSample: Sendable {
    /// Faces narrower than this fraction of the frame width are ignored.
    static let minimumFaceWidth: CGFloat = 0.05
    /// A face counts as looking at the screen within about 35 degrees sideways and 40 degrees up or down.
    /// This is head direction, not eye gaze.
    static let maximumYaw = 0.6
    static let maximumPitch = 0.7

    let time: TimeInterval // ProcessInfo.systemUptime
    /// 0 if nobody is in view, otherwise 1 (the owner) plus the others looking at the screen.
    let faceCount: Int
    /// Every usable face seen, looking at the screen or not. For diagnostics.
    let totalFaces: Int

    init(time: TimeInterval, faces: [DetectedFace]) {
        let usable = faces
            .filter { $0.width >= Self.minimumFaceWidth }
            .sorted { $0.width * $0.height > $1.width * $1.height }
        let othersLooking = usable.dropFirst().filter {
            abs($0.yaw ?? 0) <= Self.maximumYaw && abs($0.pitch ?? 0) <= Self.maximumPitch
        }.count
        self.time = time
        self.totalFaces = usable.count
        self.faceCount = usable.isEmpty ? 0 : 1 + othersLooking
    }
}

nonisolated enum PrivacyCameraError: Error {
    case unavailable
}

/// Owns the capture session. It is an actor that runs on its own serial queue, so every session
/// call happens off the main thread and the compiler checks the isolation.
actor PrivacyCamera {

    private let sessionQueue = DispatchSerialQueue(label: "privacy.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "privacy.camera.video", qos: .userInitiated)
    private let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    /// Must be kept: AVCaptureVideoDataOutput holds its delegate WEAKLY, so without this
    /// reference the analyzer is freed at once and no frame ever arrives.
    private var analyzer: FaceAnalyzer?
    private var runtimeErrorObserver: (any NSObjectProtocol)?
    private var continuation: AsyncStream<FaceSample>.Continuation?

    nonisolated var unownedExecutor: UnownedSerialExecutor { sessionQueue.asUnownedSerialExecutor() }

    /// Starts the camera and returns a stream of samples, at most one per `interval` seconds.
    /// The stream ends when `stop()` is called or if the camera fails at runtime.
    /// Calling `start` again first releases the previous run, so there is never more than one session.
    func start(interval: TimeInterval = 0.3) throws -> AsyncStream<FaceSample> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: FaceSample.self, bufferingPolicy: .bufferingNewest(4))

        // Prefer the front camera, fall back to any camera.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            continuation.finish()
            throw PrivacyCameraError.unavailable
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true // slow analysis drops frames instead of queueing them

        session.beginConfiguration()
        // 720p keeps a second, more distant face large enough for Vision to find it.
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            continuation.finish()
            throw PrivacyCameraError.unavailable
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        self.input = input
        self.output = output

        // Upright portrait frames so Vision sees faces the right way up.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        let analyzer = FaceAnalyzer(interval: interval, continuation: continuation)
        self.analyzer = analyzer
        output.setSampleBufferDelegate(analyzer, queue: videoQueue)

        // A fatal runtime error ends the stream, which tells the caller to stop.
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { _ in continuation.finish() }

        session.startRunning() // blocking, but we are on the session queue
        guard session.isRunning else {
            stop()
            continuation.finish()
            throw PrivacyCameraError.unavailable
        }
        self.continuation = continuation
        return stream
    }

    /// Releases the camera completely. Safe to call at any time, any number of times.
    func stop() {
        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
        runtimeErrorObserver = nil
        output?.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning() // always, even if `isRunning` has not caught up yet
        session.beginConfiguration()
        if let input { session.removeInput(input) }
        if let output { session.removeOutput(output) }
        session.commitConfiguration()
        input = nil
        output = nil
        analyzer = nil
        continuation?.finish()
        continuation = nil
    }
}

/// Receives frames on the serial video queue, throttles, runs Vision inline and yields a count.
/// Analysis is synchronous on that queue, so two Vision requests can never overlap.
nonisolated private final class FaceAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {

    private let interval: TimeInterval
    private let continuation: AsyncStream<FaceSample>.Continuation
    private let lastAnalysis = Mutex<TimeInterval>(-.infinity)

    init(interval: TimeInterval, continuation: AsyncStream<FaceSample>.Continuation) {
        self.interval = interval
        self.continuation = continuation
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        let due = lastAnalysis.withLock { last -> Bool in
            guard now - last >= interval else { return false }
            last = now
            return true
        }
        guard due, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3 // reports head yaw and pitch
        do { try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request]) } catch { return }

        let faces = (request.results ?? []).map {
            DetectedFace(width: $0.boundingBox.width, height: $0.boundingBox.height,
                         yaw: $0.yaw?.doubleValue, pitch: $0.pitch?.doubleValue)
        }
        continuation.yield(FaceSample(time: now, faces: faces))
    }
}
