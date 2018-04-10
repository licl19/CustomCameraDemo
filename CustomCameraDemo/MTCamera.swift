//
//  MTCamera.swift
//  CustomCameraDemo
//
//  Created by zj-db1180 on 2018/4/9.
//  Copyright © 2018年 zj-db1180. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary



// MARK: 录像文件管理器
class MTVideoFileManager: NSObject {
    
    static let shared = MTVideoFileManager()
    private override init() {
    }
    // MARK: 清除文件
    fileprivate func clearFileWithUrl(url : URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print(error)
            }
        }
    }
    // MARK: 清除文件
    fileprivate func clearFileWithPath(filePath : String) {
        if FileManager.default.fileExists(atPath: filePath) {
            do {
                try FileManager.default.removeItem(at: URL.init(fileURLWithPath: filePath))
            } catch {
                print(error)
            }
        }
    }
    // MARK: 清除文件夹
    fileprivate func clearFolder() {
        let fileManager = FileManager.default
        do {
            let subPaths = try fileManager.subpathsOfDirectory(atPath: videoFolder())
            for subPath : String in subPaths {
                let allPath = videoFolder()+"/"+subPath
                if fileManager.fileExists(atPath: allPath) {
                    try fileManager.removeItem(at: URL.init(fileURLWithPath: allPath))
                }
            }
        } catch {
            print(error)
        }
    }
    // MARK: 录像文件名
    fileprivate func videoFilePath() -> String {
        let videoName = NSUUID().uuidString
        return videoFolder()+"/"+videoName+".mov"
    }
    // MARK: 录像文件夹
    fileprivate func videoFolder() -> String {
        let cachePaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let cachePath = cachePaths[0]+"/video"
        if FileManager.default.fileExists(atPath: cachePath) != true {
            do {
                try FileManager.default.createDirectory(at: URL.init(fileURLWithPath: cachePath), withIntermediateDirectories: true, attributes: nil)
            }catch {
                print(error)
            }
        }
        return cachePath
    }
}



// MARK: 协议，用于通知外部拍照及录像结果
protocol MTCameraDelegate {
    func takePhotoFinished(error : NSError?, image : UIImage?)
    func recordFinished(error : NSError?, url : URL?)
}



// MARK: 相机管理类
class MTCamera: NSObject {
    
    // MARK: 单例
    static let shared = MTCamera()
    private override init() {
    }
    
    internal var delegate : MTCameraDelegate?
    
    // MARK: 定义Block，用于给改变属性时加锁
    fileprivate typealias PropertyChangeBlock = (_ captureDevice : AVCaptureDevice) -> Void
    // MARK: 会话
    fileprivate lazy var captureSession : AVCaptureSession = {
        let captureSessionTmp = AVCaptureSession()
        if captureSessionTmp.canSetSessionPreset(AVCaptureSession.Preset.photo) {
            captureSessionTmp.sessionPreset = AVCaptureSession.Preset.photo
        }
        return captureSessionTmp
    }()
    // MARK: 预览视图
    internal lazy var captureVideoPreviewLayer : AVCaptureVideoPreviewLayer = {
        let captureVideoPreviewLayerTmp = AVCaptureVideoPreviewLayer.init(session: captureSession)
        captureVideoPreviewLayerTmp.videoGravity = AVLayerVideoGravity.resizeAspectFill
        return captureVideoPreviewLayerTmp
    }()
    // MARK: 相机设备
    internal lazy var captureDeviceCamera : AVCaptureDevice? = {
        return captureDeviceInputCamera?.device
    }()
    // MARK: 视频输入
    fileprivate lazy var captureDeviceInputCamera : AVCaptureDeviceInput? = {
        let captureDevice = getCameraDeviceWithPosition(position: AVCaptureDevice.Position.back)
        do {
            let captureDeviceInputCameraTmp = try AVCaptureDeviceInput.init(device: captureDevice!)
            return captureDeviceInputCameraTmp
        }catch {
        }
        return nil
    }()
    fileprivate lazy var captureStillImageOutput : AVCaptureStillImageOutput = {
        let captureStillImageOutputTmp = AVCaptureStillImageOutput()
        captureStillImageOutputTmp.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        return captureStillImageOutputTmp
    }()
    // MARK: 音频输入
    fileprivate lazy var captureDeviceInputAudio : AVCaptureDeviceInput? = {
        let captureDevice = AVCaptureDevice.devices(for: AVMediaType.audio).first
        do {
            let captureDeviceInputAudioTmp = try AVCaptureDeviceInput.init(device: captureDevice!)
            return captureDeviceInputAudioTmp
        }catch {
        }
        return nil
    }()
    // MARK: 视频文件输出
    fileprivate lazy var captureMovieFileOutput : AVCaptureMovieFileOutput = {
        let captureMovieFileOutputTmp = AVCaptureMovieFileOutput()
        let captureConnection = captureMovieFileOutputTmp.connection(with: AVMediaType.video)
        //        if (captureConnection?.isVideoStabilizationSupported)! {
        captureConnection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
        //        }
        captureConnection?.videoOrientation = (captureVideoPreviewLayer.connection?.videoOrientation)!
        return captureMovieFileOutputTmp
    }()
    // MARK: 队列，用于人脸识别
    fileprivate lazy var sampleBufferQueue : DispatchQueue = {
        return DispatchQueue(label: Bundle.main.bundleIdentifier! +
            ".sampleBufferQueue")
    }()
    // MARK: 视频数据输出，用于人脸识别
    fileprivate lazy var captureVideoDataOutput : AVCaptureVideoDataOutput = {
        let captureVideoDataOutputTmp = AVCaptureVideoDataOutput()
        captureVideoDataOutputTmp.alwaysDiscardsLateVideoFrames = true
        captureVideoDataOutputTmp.setSampleBufferDelegate(self as! AVCaptureVideoDataOutputSampleBufferDelegate, queue: sampleBufferQueue)
        captureVideoDataOutputTmp.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        return captureVideoDataOutputTmp
    }()

    
    
    // MARK: 获取对应位置相机
    fileprivate func getCameraDeviceWithPosition(position : AVCaptureDevice.Position) -> AVCaptureDevice? {
        let cameras = AVCaptureDevice.devices(for: AVMediaType.video)
        for camera : AVCaptureDevice in cameras {
            if camera.position == position {
                return camera
            }
        }
        return nil
    }
    // MARK: 修改相机属性，需加锁
    fileprivate func changeDeviceProperty(propertyChange : PropertyChangeBlock) {
        let captureDevice = captureDeviceInputCamera?.device
        do {
            try captureDevice?.lockForConfiguration()
            propertyChange(captureDevice!)
            captureDevice?.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    
    
    
    // MARK: 关闭闪光灯
    internal func flashOffClick() {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.off)
    }
    // MARK: 开启闪光灯
    internal func flashOnClick() {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.on)
    }
    // MARK: 闪光灯自动
    internal func flashAutoClick() {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.auto)
    }
    fileprivate func setFlashMode(flashMode : AVCaptureDevice.FlashMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFlashModeSupported(flashMode) {
                captureDevice.flashMode = flashMode
            }
        }
    }
    // MARK: 切换摄像头
    internal func devicePositionChangeClick() {
        // MARK: 切换动画
        let animation = CATransition()
        animation.duration = CFTimeInterval.init(0.5)
        animation.timingFunction = CAMediaTimingFunction.init(name: kCAMediaTimingFunctionEaseInEaseOut)
        animation.type = "oglFlip"
        
        let currentDevice = captureDeviceInputCamera?.device
        let currentPosition = currentDevice?.position
        var toChangeDevice : AVCaptureDevice?
        var toChangePosition = AVCaptureDevice.Position.front
        if currentPosition == AVCaptureDevice.Position.unspecified || currentPosition == AVCaptureDevice.Position.front {
            toChangePosition = AVCaptureDevice.Position.back
            animation.subtype = kCATransitionFromLeft
        }else {
            animation.subtype = kCATransitionFromRight
        }
        captureVideoPreviewLayer.add(animation, forKey: "flip")
        
        toChangeDevice = getCameraDeviceWithPosition(position: toChangePosition)
        do {
            let toChangeDeviceInput = try AVCaptureDeviceInput.init(device: toChangeDevice!)
            captureSession.beginConfiguration()
            captureSession.removeInput(captureDeviceInputCamera!)
            if captureSession.canAddInput(toChangeDeviceInput) {
                captureSession.addInput(toChangeDeviceInput)
                captureDeviceInputCamera = toChangeDeviceInput
            }
            captureSession.commitConfiguration()
        } catch {
            print(error)
        }
    }

    
    
    internal func takePhoto() {
        addPhoto()
        let captureConnection = captureStillImageOutput.connection(with: AVMediaType.video)
        captureStillImageOutput.captureStillImageAsynchronously(from: captureConnection!) { (imageDataSampleBuffer, error) in
            if let error = error {
                self.delegate?.takePhotoFinished(error: error as! NSError, image: nil)
            }
            if let imageDataSampleBuffer = imageDataSampleBuffer {
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                let image = UIImage.init(data: imageData!)
                UIImageWriteToSavedPhotosAlbum(image!, self, #selector(self.imageDidFinishSavingWithError(image:error:contextInfo:)), nil)
            }
        }
    }
    @objc dynamic fileprivate func imageDidFinishSavingWithError(image: UIImage, error: NSError, contextInfo: UnsafeMutableRawPointer) {
        if error != nil {
            print(error)
            self.delegate?.takePhotoFinished(error: error as! NSError, image: nil)
        }
        if image != nil {
            print(image)
            self.delegate?.takePhotoFinished(error: nil, image: image)
        }
    }
    
    
    internal func startRunningSession() {
        captureSession.startRunning()
    }
    internal func stopRunningSession() {
        captureSession.stopRunning()
    }
    internal func startRecord() {
        if captureSession.canSetSessionPreset(AVCaptureSession.Preset.high) {
            captureSession.sessionPreset = AVCaptureSession.Preset.high
        }
        addVideoFile()
        let videoUrl = URL.init(fileURLWithPath: MTVideoFileManager.shared.videoFilePath())
        captureMovieFileOutput.startRecording(to: videoUrl, recordingDelegate: self)
    }
    internal func stopRecord() {
        captureMovieFileOutput.stopRecording()
    }
    // MARK: 用于人脸识别
    internal func addDetectFace() -> Void {
        if captureSession.canAddOutput(captureVideoDataOutput) {
            captureSession.addOutput(captureVideoDataOutput)
        }
    }
    // MARK: 用于录制视频
    internal func addVideoFile() -> Void {
        if captureSession.canAddInput(captureDeviceInputAudio!) {
            captureSession.addInput(captureDeviceInputAudio!)
        }
        if captureSession.canAddOutput(captureMovieFileOutput) {
            captureSession.addOutput(captureMovieFileOutput)
        }
    }
    // MARK: 用于拍照
    internal func addPhoto() -> Void {
        if captureSession.canAddOutput(captureStillImageOutput) {
            captureSession.addOutput(captureStillImageOutput)
        }
    }
    // MARK: 初始化相机，添加输入源，输出源
    internal func setupCamera() {
        do {
            if captureSession.canAddInput(captureDeviceInputCamera!) {
                captureSession.addInput(captureDeviceInputCamera!)
            }
        } catch {
            print(error)
        }
    }

    
    
    // MARK: 设置聚焦，曝光，聚焦点
    internal func focusWithMode(focusMode : AVCaptureDevice.FocusMode, exposureMode : AVCaptureDevice.ExposureMode, point : CGPoint) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFocusModeSupported(focusMode) {
                captureDevice.focusMode = focusMode
            }
            if captureDevice.isFocusPointOfInterestSupported {
                captureDevice.focusPointOfInterest = point
            }
            if captureDevice.isExposureModeSupported(exposureMode) {
                captureDevice.exposureMode = exposureMode
            }
            if captureDevice.isExposurePointOfInterestSupported {
                captureDevice.exposurePointOfInterest = point
            }
        }
    }
    // MARK: 设置对焦模式
    internal func setFocusMode(focusMode : AVCaptureDevice.FocusMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFocusModeSupported(focusMode) {
                captureDevice.focusMode = focusMode
            }
        }
    }
    // MARK: 设置曝光模式
    internal func setExposureMode(exposureMode : AVCaptureDevice.ExposureMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isExposureModeSupported(exposureMode) {
                captureDevice.exposureMode = exposureMode
            }
        }
    }
    // MARK: 设置手电筒
    internal func setTorchMode(torchMode : AVCaptureDevice.TorchMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isTorchModeSupported(torchMode) {
                captureDevice.torchMode = torchMode
            }
        }
    }
    // MARK: 设置白平衡模式
    internal func setTorchMode(whiteBalanceMode : AVCaptureDevice.WhiteBalanceMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isWhiteBalanceModeSupported(whiteBalanceMode) {
                captureDevice.whiteBalanceMode = whiteBalanceMode
            }
        }
    }
}



// MARK: AVCaptureVideoDataOutputSampleBufferDelegate 用于人脸识别
extension MTCamera : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer)
        let features = detectFaceResultWithImage(image: image)
//        guard features != nil else {
//            DispatchQueue.main.async {
//                for labelResult : UILabel in self.labelResults {
//                    labelResult.isHidden = true
//                }
//            }
//            return
//        }
//        DispatchQueue.main.async {
//            if self.labelResults.count < (features?.count)! {
//                for _ in 0..<(features?.count)!-self.labelResults.count {
//                    let labelResult = UILabel()
//                    labelResult.backgroundColor = .clear
//                    //                    labelResult.layer.borderColor = .red
//                    labelResult.layer.borderWidth = 1
//                    self.viewContainer.addSubview(labelResult)
//                    self.labelResults.append(labelResult)
//                }
//            }
//            for (offset ,labelResult) in self.labelResults.enumerated() {
//                if offset < (features?.count)! {
//                    labelResult.isHidden = false
//                    let rectValue = features![offset] as NSValue
//                    labelResult.frame = self.rectFromOriRect(originAllRect: rectValue.cgRectValue)
//                }else {
//                    labelResult.isHidden = true
//                }
//            }
//        }
    }
//    // MARK: 获取图上rect
//    fileprivate func rectFromOriRect(originAllRect : CGRect) -> CGRect {
//        print(originAllRect)
//        let scrSalImageW = 720/UIScreen.main.bounds.size.width
//        let scrSalImageH = (1280-164)/(UIScreen.main.bounds.size.height-164)
//        var getRect = originAllRect
//        getRect.size.width = originAllRect.size.width/scrSalImageW
//        getRect.size.height = originAllRect.size.height/scrSalImageH
//        let hx = self.viewContainer.bounds.size.width/720
//        let hy = self.viewContainer.bounds.size.height/(1280-164)
//        getRect.origin.x = originAllRect.origin.x*hx
//        getRect.origin.y = (self.viewContainer.bounds.size.height-originAllRect.origin.y*hy)-getRect.size.height
//        print(getRect)
//        return getRect
//    }
    // MARK: 从缓存数据创建图片
    fileprivate func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let ciImage = CIImage.init(cvPixelBuffer: imageBuffer!)
        let ciContext = CIContext.init(options: nil)
        let videoImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width :CVPixelBufferGetWidth(imageBuffer!), height :CVPixelBufferGetHeight(imageBuffer!)))
        let imageResult = UIImage.init(cgImage: videoImage!, scale: 1.0, orientation: UIImageOrientation.leftMirrored)
        return imageResult
    }
    // MARK: 识别结果
    fileprivate func detectFaceResultWithImage(image : UIImage) -> [NSValue]? {
        guard hasFace(image: image) else { return nil }
        let features = detectFaceWithImage(image: image)
        var arrM = [NSValue]()
        for feature : CIFeature in features {
            arrM.append(NSValue.init(cgRect: feature.bounds))
        }
        return arrM
    }
    // MARK: 是否识别脸部
    fileprivate func hasFace(image : UIImage) -> Bool {
        let features = detectFaceWithImage(image: image)
        return features.count > 0
    }
    // MARK: 识别脸部特征
    fileprivate func detectFaceWithImage(image : UIImage) -> [CIFeature] {
        let faceDetector = CIDetector.init(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let ciImage = CIImage.init(image: image)
        let features = faceDetector?.features(in: ciImage!)
        return features!
    }
}



// MARK: AVCaptureFileOutputRecordingDelegate 用于录制视频
extension MTCamera : AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let asset = AVAsset.init(url: outputFileURL)
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let videoAssetTrack = asset.tracks(withMediaType: AVMediaType.video).first
        do {
            try videoTrack?.insertTimeRange(CMTimeRange.init(start: kCMTimeZero, duration: (videoAssetTrack?.timeRange.duration)!), of: videoAssetTrack!, at: kCMTimeZero)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction.init(assetTrack: videoTrack!)
            let totalDuration = CMTimeAdd(kCMTimeZero, (videoAssetTrack?.timeRange.duration)!)
            let t1 = CGAffineTransform.init(translationX: -1*(videoAssetTrack?.naturalSize.width)!/2, y: -1*(videoAssetTrack?.naturalSize.height)!/2)
            layerInstruction.setTransform(t1, at: kCMTimeZero)
            var renderSize = CGSize(width: 0, height: 0)
            renderSize.width = max(renderSize.width, (videoAssetTrack?.naturalSize.height)!)
            renderSize.height = max(renderSize.height, (videoAssetTrack?.naturalSize.width)!)
            let renderW = min(renderSize.width, renderSize.height)
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange.init(start: kCMTimeZero, duration: totalDuration)
            instruction.layerInstructions = [layerInstruction]
            let mainComposition = AVMutableVideoComposition()
            mainComposition.instructions = [instruction]
            mainComposition.frameDuration = CMTimeMake(1, 30)
            mainComposition.renderSize = CGSize(width: renderW, height: renderW)
            
            let exporter = AVAssetExportSession.init(asset: composition, presetName: AVAssetExportPresetMediumQuality)
            exporter?.videoComposition = mainComposition
            exporter?.outputURL = outputFileURL
            exporter?.shouldOptimizeForNetworkUse = true
            exporter?.outputFileType = AVFileType.mov
            exporter?.exportAsynchronously {
                DispatchQueue.main.async {
                    let lib = ALAssetsLibrary()
                    lib.writeVideoAtPath(toSavedPhotosAlbum: outputFileURL, completionBlock: { (url, error) in
                        if let error = error {
                            print(error)
                            self.delegate?.recordFinished(error: error as! NSError, url: nil)
                        }
                        if let url = url {
                            print(url)
                            MTVideoFileManager.shared.clearFileWithUrl(url: outputFileURL)
                            self.delegate?.recordFinished(error: nil, url: url)
                        }
                    })
                }
            }
        } catch {
            print(error)
        }
    }
}
