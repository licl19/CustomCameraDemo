//
//  ViewController.swift
//  CustomCameraDemo
//
//  Created by zj-db1180 on 2018/4/5.
//  Copyright © 2018年 zj-db1180. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary
import Toast_Swift

class ViewController: UIViewController {
    // MARK: 定义Block
    typealias PropertyChangeBlock = (_ captureDevice : AVCaptureDevice) -> Void

    lazy var captureSession : AVCaptureSession = {
        let captureSessionTmp = AVCaptureSession()
        if captureSessionTmp.canSetSessionPreset(AVCaptureSession.Preset.photo) {
            captureSessionTmp.sessionPreset = AVCaptureSession.Preset.photo
        }
        return captureSessionTmp
    }()
    lazy var captureDeviceInput : AVCaptureDeviceInput? = {
        let captureDevice = getCameraDeviceWithPosition(position: AVCaptureDevice.Position.back)
        do {
            let captureDeviceInputTmp = try AVCaptureDeviceInput.init(device: captureDevice!)
            return captureDeviceInputTmp
        }catch {
            print(error)
        }
        return nil
    }()
    lazy var captureStillImageOutput : AVCaptureStillImageOutput = {
        let captureStillImageOutputTmp = AVCaptureStillImageOutput()
        captureStillImageOutputTmp.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        return captureStillImageOutputTmp
    }()
    // MARK: 用于实时数据处理，例如人脸识别
    lazy var sampleBufferQueue : DispatchQueue = {
        return DispatchQueue(label: Bundle.main.bundleIdentifier! +
            ".sampleBufferQueue")
    }()
    // MARK: 用于实时数据处理
    lazy var captureVideoDataOutput : AVCaptureVideoDataOutput = {
        let captureVideoDataOutputTmp = AVCaptureVideoDataOutput()
        captureVideoDataOutputTmp.alwaysDiscardsLateVideoFrames = true
        captureVideoDataOutputTmp.setSampleBufferDelegate(self as! AVCaptureVideoDataOutputSampleBufferDelegate, queue: sampleBufferQueue)
        captureVideoDataOutputTmp.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        return captureVideoDataOutputTmp
    }()
    // MARK: 识别结果框
    lazy var labelResults : [UILabel] = {
        return []
    }()
    lazy var captureVideoPreviewLayer : AVCaptureVideoPreviewLayer = {
        let captureVideoPreviewLayerTmp = AVCaptureVideoPreviewLayer.init(session: captureSession)
        return captureVideoPreviewLayerTmp
    }()
    
    @IBOutlet weak var ViewContainer: UIView!
    @IBOutlet weak var takeButton: UIButton!
    @IBOutlet weak var flashAutoButton: UIButton!
    @IBOutlet weak var flashOnButton: UIButton!
    @IBOutlet weak var flashOffButton: UIButton!
    @IBOutlet weak var focusCursor: UIImageView!
    
    // MARK: 关闭闪光灯
    @IBAction func flashOffClick(_ sender: UIButton) {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.off)
        setFlashModeButtonStatus()
    }
    // MARK: 开启闪光灯
    @IBAction func flashOnClick(_ sender: UIButton) {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.on)
        setFlashModeButtonStatus()
    }
    // MARK: 闪光灯自动
    @IBAction func flashAutoClick(_ sender: UIButton) {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.auto)
        setFlashModeButtonStatus()
    }
    private func setFlashMode(flashMode : AVCaptureDevice.FlashMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFlashModeSupported(flashMode) {
                captureDevice.flashMode = flashMode
            }
        }
    }
    // MARK: 切换摄像头
    @IBAction func toggleButtonClick(_ sender: UIButton) {
        // MARK: 切换动画
        let animation = CATransition()
        animation.duration = CFTimeInterval.init(0.5)
        animation.timingFunction = CAMediaTimingFunction.init(name: kCAMediaTimingFunctionEaseInEaseOut)
        animation.type = "oglFlip"
        
        let currentDevice = captureDeviceInput?.device
        let currentPosition = currentDevice?.position
        removeNotificationFromCaptureDevice(captureDevice: currentDevice!)
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
        addNotificationToCaptureDevice(captureDevice: toChangeDevice!)
        do {
            let toChangeDeviceInput = try AVCaptureDeviceInput.init(device: toChangeDevice!)
            captureSession.beginConfiguration()
            captureSession.removeInput(captureDeviceInput!)
            if captureSession.canAddInput(toChangeDeviceInput) {
                captureSession.addInput(toChangeDeviceInput)
                captureDeviceInput = toChangeDeviceInput
            }
            captureSession.commitConfiguration()
            setFlashModeButtonStatus()
        } catch {
            print(error)
        }
    }
    private func removeNotificationFromCaptureDevice(captureDevice : AVCaptureDevice) {
        NotificationCenter.default.removeObserver(self, name: Notification.Name.AVCaptureDeviceSubjectAreaDidChange, object: captureDevice)
    }
    
    // MARK: 拍照，保存图片
    @IBAction func takeButtonClick(_ sender: UIButton) {
        let captureConnection = captureStillImageOutput.connection(with: AVMediaType.video)
        captureStillImageOutput.captureStillImageAsynchronously(from: captureConnection!) { (imageDataSampleBuffer, error) in
            if imageDataSampleBuffer != nil {
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer!)
                let image = UIImage.init(data: imageData!)
                UIImageWriteToSavedPhotosAlbum(image!, self, #selector(self.imageDidFinishSavingWithError(image:error:contextInfo:)), nil)
            }
        }
        
    }
    @objc private func imageDidFinishSavingWithError(image: UIImage, error: NSError, contextInfo: UnsafeMutableRawPointer) {
        if error != nil {
            print(error)
        }
        if image != nil {
            print(image)
            view.makeToast("Success!", duration: 3.0, position: .center)
        }
    }
    
    // MARK: 添加数据处理
    // MARK: 在需要的地方调用即可
    func addVideoDataOutput() -> Void {
        if captureSession.canAddOutput(captureVideoDataOutput) {
            captureSession.addOutput(captureVideoDataOutput)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    // MARK: 初始化相机
    override func viewWillAppear(_ animated: Bool) {
        do {
            if captureSession.canAddInput(captureDeviceInput!) {
                captureSession.addInput(captureDeviceInput!)
            }
            if captureSession.canAddOutput(captureStillImageOutput) {
                captureSession.addOutput(captureStillImageOutput)
            }
            let layer = ViewContainer.layer
            layer.masksToBounds = true
            captureVideoPreviewLayer.frame = layer.bounds
            captureVideoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            layer.insertSublayer(captureVideoPreviewLayer, below: focusCursor.layer)
            
            addNotificationToCaptureDevice(captureDevice: (captureDeviceInput?.device)!)
            addGenstureRecognizer()
            setFlashModeButtonStatus()
            
            
            addVideoDataOutput()
        } catch {
            print(error)
        }
    }
    // MARK: 闪光灯按钮状态初始化
    private func setFlashModeButtonStatus() {
        let captureDevice = captureDeviceInput?.device
        let flashMode = captureDevice?.flashMode
        if captureDevice?.isFlashAvailable == true {
            flashAutoButton.isHidden = false
            flashOnButton.isHidden = false
            flashOffButton.isHidden = false
            flashAutoButton.isEnabled = true
            flashOnButton.isEnabled = true
            flashOffButton.isEnabled = true
            switch (flashMode) {
            case .auto?:
                flashAutoButton.isEnabled = false
                break
            case .on?:
                flashOnButton.isEnabled = false
                break
            case .off?:
                flashOffButton.isEnabled = false
                break
            case .none:
                break
            }
        }else {
            flashAutoButton.isHidden = true
            flashOnButton.isHidden = true
            flashOffButton.isHidden = true
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSession.startRunning()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSession.stopRunning()
    }
    // MARK: 获取对应位置相机
    private func getCameraDeviceWithPosition(position : AVCaptureDevice.Position) -> AVCaptureDevice? {
        let cameras = AVCaptureDevice.devices(for: AVMediaType.video)
        for camera : AVCaptureDevice in cameras {
            if camera.position == position {
                return camera
            }
        }
        return nil
    }
    
    
    
    private func addNotificationToCaptureDevice(captureDevice : AVCaptureDevice) {
        changeDeviceProperty { (captureDevice) in
            captureDevice.isSubjectAreaChangeMonitoringEnabled = true
        }
        NotificationCenter.default.addObserver(self, selector: #selector(areaChange(noti:)), name: Notification.Name.AVCaptureDeviceSubjectAreaDidChange, object: captureDevice)
    }
    // MARK: 修改相机属性，需加锁
    private func changeDeviceProperty(propertyChange : PropertyChangeBlock) {
        let captureDevice = captureDeviceInput?.device
        do {
            try captureDevice?.lockForConfiguration()
            propertyChange(captureDevice!)
            captureDevice?.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    @objc private func areaChange(noti : Notification) {
    }
    
    
    
    private func addGenstureRecognizer() {
        let tap = UITapGestureRecognizer.init(target: self, action: #selector(tapScreen(tapGesture:)))
        ViewContainer.addGestureRecognizer(tap)
    }
    // MARK: 对焦
    @objc private func tapScreen(tapGesture : UITapGestureRecognizer) {
        let pointTap = tapGesture.location(in: ViewContainer)
        let pointCamera = captureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint: pointTap)
        setFocusCursorWithPoint(point: pointTap)
        focusWithMode(focusMode: AVCaptureDevice.FocusMode.autoFocus, exposureMode: AVCaptureDevice.ExposureMode.autoExpose, point: pointCamera)
    }
    // MARK: 对焦动画
    private func setFocusCursorWithPoint(point : CGPoint) {
        focusCursor.center = point
        focusCursor.transform = CGAffineTransform.init(scaleX: 1.5, y: 1.5)
        focusCursor.alpha = 1.0
        UIView.animate(withDuration: 1.0, animations: {
            self.focusCursor.transform = CGAffineTransform.identity
        }) { (finished) in
            self.focusCursor.alpha = 0
        }
    }
    private func focusWithMode(focusMode : AVCaptureDevice.FocusMode, exposureMode : AVCaptureDevice.ExposureMode, point : CGPoint) {
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
    private func setFocusMode(focusMode : AVCaptureDevice.FocusMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFocusModeSupported(focusMode) {
                captureDevice.focusMode = focusMode
            }
        }
    }
    // MARK: 设置曝光模式
    private func setExposureMode(exposureMode : AVCaptureDevice.ExposureMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isExposureModeSupported(exposureMode) {
                captureDevice.exposureMode = exposureMode
            }
        }
    }
    // MARK: 设置手电筒
    private func setTorchMode(torchMode : AVCaptureDevice.TorchMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isTorchModeSupported(torchMode) {
                captureDevice.torchMode = torchMode
            }
        }
    }
    // MARK: 设置白平衡模式
    private func setTorchMode(whiteBalanceMode : AVCaptureDevice.WhiteBalanceMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isWhiteBalanceModeSupported(whiteBalanceMode) {
                captureDevice.whiteBalanceMode = whiteBalanceMode
            }
        }
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}



// MARK: AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer)
        let features = detectFaceResultWithImage(image: image)
        guard features != nil else {
            DispatchQueue.main.async {
                for labelResult : UILabel in self.labelResults {
                    labelResult.isHidden = true
                }
            }
            return
        }
        DispatchQueue.main.async {
            if self.labelResults.count < (features?.count)! {
                for _ in 0..<(features?.count)!-self.labelResults.count {
                    let labelResult = UILabel()
                    labelResult.backgroundColor = .clear
//                    labelResult.layer.borderColor = .red
                    labelResult.layer.borderWidth = 1
                    self.ViewContainer.addSubview(labelResult)
                    self.labelResults.append(labelResult)
                }
            }
            for (offset ,labelResult) in self.labelResults.enumerated() {
                if offset < (features?.count)! {
                    labelResult.isHidden = false
                    let rectValue = features![offset] as NSValue
                    labelResult.frame = self.rectFromOriRect(originAllRect: rectValue.cgRectValue)
                }else {
                    labelResult.isHidden = true
                }
            }
        }
    }
    // MARK: 获取图上rect
    private func rectFromOriRect(originAllRect : CGRect) -> CGRect {
        print(originAllRect)
        let scrSalImageW = 720/UIScreen.main.bounds.size.width
        let scrSalImageH = (1280-164)/(UIScreen.main.bounds.size.height-164)
        var getRect = originAllRect
        getRect.size.width = originAllRect.size.width/scrSalImageW
        getRect.size.height = originAllRect.size.height/scrSalImageH
        let hx = self.ViewContainer.bounds.size.width/720
        let hy = self.ViewContainer.bounds.size.height/(1280-164)
        getRect.origin.x = originAllRect.origin.x*hx
        getRect.origin.y = (self.ViewContainer.bounds.size.height-originAllRect.origin.y*hy)-getRect.size.height
        print(getRect)
        return getRect
    }
    // MARK: 从缓存数据创建图片
    private func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let ciImage = CIImage.init(cvPixelBuffer: imageBuffer!)
        let ciContext = CIContext.init(options: nil)
        let videoImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width :CVPixelBufferGetWidth(imageBuffer!), height :CVPixelBufferGetHeight(imageBuffer!)))
        let imageResult = UIImage.init(cgImage: videoImage!, scale: 1.0, orientation: UIImageOrientation.leftMirrored)
        return imageResult
    }
    // MARK: 识别结果
    private func detectFaceResultWithImage(image : UIImage) -> [NSValue]? {
        guard hasFace(image: image) else { return nil }
        let features = detectFaceWithImage(image: image)
        var arrM = [NSValue]()
        for feature : CIFeature in features {
            arrM.append(NSValue.init(cgRect: feature.bounds))
        }
        return arrM
    }
    // MARK: 是否识别脸部
    private func hasFace(image : UIImage) -> Bool {
        let features = detectFaceWithImage(image: image)
        return features.count > 0
    }
    // MARK: 识别脸部特征
    private func detectFaceWithImage(image : UIImage) -> [CIFeature] {
        let faceDetector = CIDetector.init(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let ciImage = CIImage.init(image: image)
        let features = faceDetector?.features(in: ciImage!)
        return features!
    }
}
