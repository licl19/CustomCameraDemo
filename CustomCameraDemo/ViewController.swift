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
    
    @IBAction func flashOffClick(_ sender: UIButton) {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.off)
        setFlashModeButtonStatus()
    }
    @IBAction func flashOnClick(_ sender: UIButton) {
        setFlashMode(flashMode: AVCaptureDevice.FlashMode.on)
        setFlashModeButtonStatus()
    }
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
    @IBAction func toggleButtonClick(_ sender: UIButton) {
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
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    override func viewWillAppear(_ animated: Bool) {
        let captureDevice = getCameraDeviceWithPosition(position: AVCaptureDevice.Position.back)
        guard captureDevice != nil else {
            fatalError("""
                Not support back camera.
            """)
        }
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
            
            addNotificationToCaptureDevice(captureDevice: captureDevice!)
            addGenstureRecognizer()
            setFlashModeButtonStatus()
        } catch {
            print(error)
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
        print("捕获区域改变...")
    }
    
    
    
    private func addGenstureRecognizer() {
        let tap = UITapGestureRecognizer.init(target: self, action: #selector(tapScreen(tapGesture:)))
        ViewContainer.addGestureRecognizer(tap)
    }
    @objc private func tapScreen(tapGesture : UITapGestureRecognizer) {
        let pointTap = tapGesture.location(in: ViewContainer)
        let pointCamera = captureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint: pointTap)
        setFocusCursorWithPoint(point: pointTap)
        focusWithMode(focusMode: AVCaptureDevice.FocusMode.autoFocus, exposureMode: AVCaptureDevice.ExposureMode.autoExpose, point: pointCamera)
    }
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
    private func setFocusMode(focusMode : AVCaptureDevice.FocusMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isFocusModeSupported(focusMode) {
                captureDevice.focusMode = focusMode
            }
        }
    }
    private func setExposureMode(exposureMode : AVCaptureDevice.ExposureMode) {
        changeDeviceProperty { (captureDevice) in
            if captureDevice.isExposureModeSupported(exposureMode) {
                captureDevice.exposureMode = exposureMode
            }
        }
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

