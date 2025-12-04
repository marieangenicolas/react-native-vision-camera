//
//  CameraView.swift
//  mrousavy
//
//  Created by Marc Rousavy on 09.11.20.
//  Copyright © 2020 mrousavy. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit
import MetalPetal
import MetalKit

// TODOs for the CameraView which are currently too hard to implement either because of AVFoundation's limitations, or my brain capacity
//
// CameraView+RecordVideo
// TODO: Better startRecording()/stopRecording() (promise + callback, wait for TurboModules/JSI)
//
// CameraView+TakePhoto
// TODO: Photo HDR

// MARK: - CameraView

public final class CameraView: UIView, CameraSessionDelegate, PreviewViewDelegate, FpsSampleCollectorDelegate,MTKViewDelegate {
  // pragma MARK: React Properties

  private var lutFilter: MTIColorLookupFilter?

  // props that require reconfiguring
  @objc var cameraId: NSString?
  @objc var enableDepthData = false
  @objc var enablePortraitEffectsMatteDelivery = false
  @objc var enableBufferCompression = false
  @objc var isMirrored = false

  // use cases
  @objc var photo = false
  @objc var video = false
  @objc var audio = false
  @objc var enableFrameProcessor = false
  @objc var codeScannerOptions: NSDictionary?
  @objc var pixelFormat: NSString?
  @objc var enableLocation = false
  @objc var preview = true {
    didSet {
      // updatePreview()
    }
  }

  // props that require format reconfiguring
  @objc var format: NSDictionary?
  @objc var minFps: NSNumber?
  @objc var maxFps: NSNumber?
  @objc var videoHdr = false
  @objc var photoHdr = false
  @objc var photoQualityBalance: NSString?
  @objc var lowLightBoost = false
  @objc var outputOrientation: NSString?
  @objc var videoBitRateOverride: NSNumber?
  @objc var videoBitRateMultiplier: NSNumber?

  // other props
  @objc var isActive = false
  @objc var torch = "off"
  @objc var zoom: NSNumber = 1.0 // in "factor"
  @objc var exposure: NSNumber = 0.0
  @objc var videoStabilizationMode: NSString?
  @objc var resizeMode: NSString = "cover" {
    didSet {
      // updatePreview()
    }
  }

  // events
  @objc var onInitializedEvent: RCTDirectEventBlock?
  @objc var onErrorEvent: RCTDirectEventBlock?
  @objc var onStartedEvent: RCTDirectEventBlock?
  @objc var onStoppedEvent: RCTDirectEventBlock?
  @objc var onPreviewStartedEvent: RCTDirectEventBlock?
  @objc var onPreviewStoppedEvent: RCTDirectEventBlock?
  @objc var onShutterEvent: RCTDirectEventBlock?
  @objc var onPreviewOrientationChangedEvent: RCTDirectEventBlock?
  @objc var onOutputOrientationChangedEvent: RCTDirectEventBlock?
  @objc var onViewReadyEvent: RCTDirectEventBlock?
  @objc var onAverageFpsChangedEvent: RCTDirectEventBlock?
  @objc var onCodeScannedEvent: RCTDirectEventBlock?

  @objc var lutAsset: NSDictionary? {
    didSet {
      guard let lutUIImage = RCTConvert.uiImage(lutAsset) else {
        print("❌ Failed to convert LUT asset")
        return
      }
      
      guard let cgImage = lutUIImage.cgImage else {
        return
      }
      
      // Create MTIImage for LUT
      let lutMTIImage = MTIImage(cgImage: cgImage, options: [.SRGB: true], isOpaque: false)
      
      // Create filter if not created yet
      if lutFilter == nil {
        lutFilter = MTIColorLookupFilter()
      }
      
      lutFilter?.inputColorLookupTable = lutMTIImage
      lutFilter?.intensity = 0.8
      print("✅ LUT updated")
    }
  }

  // zoom
  @objc var enableZoomGesture = false {
    didSet {
      if enableZoomGesture {
        addPinchGestureRecognizer()
      } else {
        removePinchGestureRecognizer()
      }
    }
  }

  #if VISION_CAMERA_ENABLE_FRAME_PROCESSORS
    @objc public var frameProcessor: FrameProcessor?
  #endif

  // pragma MARK: Internal Properties
  var orientationManager = OrientationManager()
  var cameraSession = CameraSession()
  var previewView: PreviewView?
  var isMounted = false
  var _mtkView: MTKView?
  private var renderContext: MTIContext?
  private var latestImage: MTIImage?
  private let imageLock = NSLock()
  private var currentConfigureCall: DispatchTime?
  private let fpsSampleCollector = FpsSampleCollector()

  // CameraView+Zoom
  var pinchGestureRecognizer: UIPinchGestureRecognizer?
  var pinchScaleOffset: CGFloat = 1.0

  // CameraView+TakeSnapshot
  var latestVideoFrame: Snapshot?

  // pragma MARK: Setup

  override public init(frame: CGRect) {
    super.init(frame: frame)
    cameraSession.delegate = self
    fpsSampleCollector.delegate = self
    setupMetalRendering()
    // updatePreview()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not implemented.")
  }
  // MARK: - Metal Rendering Setup
  private func setupMetalRendering() {
    // 1️⃣ Metal device and MetalPetal context
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    renderContext = try? MTIContext(device: device)
    
    // 2️⃣ MTKView
    let view = MTKView(frame: bounds, device: device)
    //    view.framebufferOnly = false
    //    view.enableSetNeedsDisplay = false
    //    view.isPaused = false
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Match pixel format to BGRA as we capture 32BGRA
    view.colorPixelFormat = .bgra8Unorm
    view.delegate = self
    addSubview(view)
    self._mtkView = view
  }
  override public func willMove(toSuperview newSuperview: UIView?) {
    super.willMove(toSuperview: newSuperview)

    if newSuperview != nil {
      fpsSampleCollector.start()
      if !isMounted {
        isMounted = true
        onViewReadyEvent?(nil)
      }
    } else {
      fpsSampleCollector.stop()
    }
  }

  override public func layoutSubviews() {
    if let previewView {
      previewView.frame = frame
      previewView.bounds = bounds
    }
  }

  func getPixelFormat() -> PixelFormat {
    // TODO: Use ObjC RCT enum parser for this
    if let pixelFormat = pixelFormat as? String {
      do {
        return try PixelFormat(jsValue: pixelFormat)
      } catch {
        if let error = error as? CameraError {
          onError(error)
        } else {
          onError(.unknown(message: error.localizedDescription, cause: error as NSError))
        }
      }
    }
    return .yuv
  }

  func getTorch() -> Torch {
    // TODO: Use ObjC RCT enum parser for this
    if let torch = try? Torch(jsValue: torch) {
      return torch
    }
    return .off
  }

  func getPhotoQualityBalance() -> QualityBalance {
    if let photoQualityBalance = photoQualityBalance as? String,
       let balance = try? QualityBalance(jsValue: photoQualityBalance) {
      return balance
    }
    return .balanced
  }

  // pragma MARK: Props updating
  override public final func didSetProps(_ changedProps: [String]!) {
    VisionLogger.log(level: .info, message: "Updating \(changedProps.count) props: [\(changedProps.joined(separator: ", "))]")
    let now = DispatchTime.now()
    currentConfigureCall = now

    cameraSession.configure { [self] config in
      // Check if we're still the latest call to configure { ... }
      guard currentConfigureCall == now else {
        // configure waits for a lock, and if a new call to update() happens in the meantime we can drop this one.
        // this works similar to how React implemented concurrent rendering, the newer call to update() has higher priority.
        VisionLogger.log(level: .info, message: "A new configure { ... } call arrived, aborting this one...")
        throw CameraConfiguration.AbortThrow.abort
      }

      // Input Camera Device
      config.cameraId = cameraId as? String
      config.isMirrored = isMirrored

      // Photo
      if photo {
        config.photo = .enabled(config: CameraConfiguration.Photo(qualityBalance: getPhotoQualityBalance(),
                                                                  enableDepthData: enableDepthData,
                                                                  enablePortraitEffectsMatte: enablePortraitEffectsMatteDelivery))
      } else {
        config.photo = .disabled
      }

      // Video/Frame Processor
      if video || enableFrameProcessor {
        config.video = .enabled(config: CameraConfiguration.Video(pixelFormat: getPixelFormat(),
                                                                  enableBufferCompression: enableBufferCompression,
                                                                  enableHdr: videoHdr,
                                                                  enableFrameProcessor: enableFrameProcessor))
      } else {
        config.video = .disabled
      }

      if(lutFilter != nil){
        config.lutFilter = lutFilter
      }

      // Audio
      if audio {
        config.audio = .enabled(config: CameraConfiguration.Audio())
      } else {
        config.audio = .disabled
      }

      // Code Scanner
      if let codeScannerOptions {
        let options = try CodeScannerOptions(fromJsValue: codeScannerOptions)
        config.codeScanner = .enabled(config: CameraConfiguration.CodeScanner(options: options))
      } else {
        config.codeScanner = .disabled
      }

      // Location tagging
      config.enableLocation = enableLocation && isActive

      // Video Stabilization
      if let jsVideoStabilizationMode = videoStabilizationMode as? String {
        let videoStabilizationMode = try VideoStabilizationMode(jsValue: jsVideoStabilizationMode)
        config.videoStabilizationMode = videoStabilizationMode
      } else {
        config.videoStabilizationMode = .off
      }

      // Orientation
      if let jsOrientation = outputOrientation as? String {
        let outputOrientation = try OutputOrientation(jsValue: jsOrientation)
        config.outputOrientation = outputOrientation
      } else {
        config.outputOrientation = .device
      }

      // Format
      if let jsFormat = format {
        let format = try CameraDeviceFormat(jsValue: jsFormat)
        config.format = format
      } else {
        config.format = nil
      }

      // Side-Props
      config.minFps = minFps?.int32Value
      config.maxFps = maxFps?.int32Value
      config.enableLowLightBoost = lowLightBoost
      config.torch = try Torch(jsValue: torch)

      // Zoom
      config.zoom = zoom.doubleValue

      // Exposure
      config.exposure = exposure.floatValue

      // isActive
      config.isActive = isActive
    }

    // Store `zoom` offset for native pinch-gesture
    if changedProps.contains("zoom") {
      pinchScaleOffset = zoom.doubleValue
    }

    // Prevent phone from going to sleep
    UIApplication.shared.isIdleTimerDisabled = isActive
  }

  func updatePreview() {
    if preview && previewView == nil {
      // Create PreviewView and add it
      previewView = cameraSession.createPreviewView(frame: frame)
      previewView!.delegate = self
      addSubview(previewView!)
    } else if !preview && previewView != nil {
      // Remove PreviewView and destroy it
      previewView?.removeFromSuperview()
      previewView = nil
    }

    if let previewView {
      // Update resizeMode from React
      let parsed = try? ResizeMode(jsValue: resizeMode as String)
      previewView.resizeMode = parsed ?? .cover
    }
  }

  // pragma MARK: Event Invokers

  func onError(_ error: CameraError) {
    VisionLogger.log(level: .error, message: "Invoking onError(): \(error.message)")

    var causeDictionary: [String: Any]?
    if case let .unknown(_, cause) = error,
       let cause = cause {
      causeDictionary = [
        "code": cause.code,
        "domain": cause.domain,
        "message": cause.description,
        "details": cause.userInfo,
      ]
    }
    onErrorEvent?([
      "code": error.code,
      "message": error.message,
      "cause": causeDictionary ?? NSNull(),
    ])
  }

  func onSessionInitialized() {
    onInitializedEvent?([:])
  }

  func onCameraStarted() {
    onStartedEvent?([:])
  }

  func onCameraStopped() {
    onStoppedEvent?([:])
  }

  func onPreviewStarted() {
    onPreviewStartedEvent?([:])
  }

  func onPreviewStopped() {
    onPreviewStoppedEvent?([:])
  }

  func onCaptureShutter(shutterType: ShutterType) {
    onShutterEvent?([
      "type": shutterType.jsValue,
    ])
  }

  func onOutputOrientationChanged(_ outputOrientation: Orientation) {
    onOutputOrientationChangedEvent?([
      "outputOrientation": outputOrientation.jsValue,
    ])
  }

  func onPreviewOrientationChanged(_ previewOrientation: Orientation) {
    onPreviewOrientationChangedEvent?([
      "previewOrientation": previewOrientation.jsValue,
    ])
  }

  func onFrame(sampleBuffer: CMSampleBuffer, orientation: Orientation, isMirrored: Bool) {
    // Update latest frame that can be used for snapshot capture
    latestVideoFrame = Snapshot(imageBuffer: sampleBuffer, orientation: orientation)

    // Get camera pixel buffer
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let inputImage = MTIImage(cvPixelBuffer: pixelBuffer, alphaType: .alphaIsOne)
    
    // Apply LUT if available
    let filteredImage: MTIImage
    if let lutFilter = lutFilter {
      lutFilter.inputImage = inputImage
      filteredImage = lutFilter.outputImage ?? inputImage
    } else {
      filteredImage = inputImage
    }
    
    // Determine rotation angle (your original mapping)
    var rotateAngle: CGFloat = 0.0
    switch cameraSession.orientationManager._deviceOrientation {
    case .portrait: rotateAngle = -.pi / 2
    case .landscapeLeft: rotateAngle = -.pi / 2
    case .portraitUpsideDown: rotateAngle = -.pi / 2
    case .landscapeRight: rotateAngle = 3 * .pi / 2
    @unknown default: rotateAngle = 0
    }
    
    // Get original image size
    let imageWidth = filteredImage.size.width
    let imageHeight = filteredImage.size.height
    
    // Compute rotated bounding box size
    let rotatedWidth = abs(imageWidth * cos(rotateAngle)) + abs(imageHeight * sin(rotateAngle))
    let rotatedHeight = abs(imageWidth * sin(rotateAngle)) + abs(imageHeight * cos(rotateAngle))
    
    // Compute scale to fit rotated image inside original bounds
    let scaleX = imageWidth / rotatedWidth
    let scaleY = imageHeight / rotatedHeight
    let scale = min(scaleX, scaleY)
    
    // Apply rotation and scale
    let transformFilter = MTITransformFilter()
    let rotationTransform = CATransform3DMakeRotation(rotateAngle, 0, 0, 1)
    transformFilter.transform = CATransform3DScale(rotationTransform, scale, scale, 1)
    transformFilter.inputImage = filteredImage
    
    // Store latest image
    imageLock.lock()
    latestImage = transformFilter.outputImage
    imageLock.unlock()
    
    // Trigger MTKView draw on main thread
    DispatchQueue.main.async { [weak self] in
      self?._mtkView?.draw()
    }
    

    // Notify FPS Collector that we just had a Frame
    fpsSampleCollector.onTick()

    #if VISION_CAMERA_ENABLE_FRAME_PROCESSORS
      if let frameProcessor = frameProcessor {
        // Call Frame Processor
        let frame = Frame(buffer: sampleBuffer,
                          orientation: orientation.imageOrientation,
                          isMirrored: isMirrored)
        frameProcessor.call(frame)
      }
    #endif
  }

  func onCodeScanned(codes: [CameraSession.Code], scannerFrame: CameraSession.CodeScannerFrame) {
    onCodeScannedEvent?([
      "codes": codes.map { $0.toJSValue() },
      "frame": scannerFrame.toJSValue(),
    ])
  }

  func onAverageFpsChanged(averageFps: Double) {
    onAverageFpsChangedEvent?([
      "averageFps": averageFps,
    ])
  }

  // MARK: - MTKViewDelegate
  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    // No-op for now. Could be used to update scaling if needed.
  }
  
  public func draw(in view: MTKView) {
    guard let renderContext = renderContext else { return }
    imageLock.lock()
    let image = latestImage
    imageLock.unlock()
    guard let imageToRender = image else { return }
    //    guard let drawable = view.currentDrawable else { return }
    
    // Build a drawable rendering request; use aspectFill to match contentMode
    let request = MTIDrawableRenderingRequest(drawableProvider: view, resizingMode: .aspectFill)
    
    do {
      try renderContext.render(imageToRender, toDrawableWithRequest: request)
    } catch {
      // Swallow or log as needed
      // print("Render error: \(error)")
    }
  }
}
