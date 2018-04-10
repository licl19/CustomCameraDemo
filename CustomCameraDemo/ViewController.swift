//
//  ViewController.swift
//  CustomCameraDemo
//
//  Created by zj-db1180 on 2018/4/5.
//  Copyright © 2018年 zj-db1180. All rights reserved.
//

import UIKit
import AVFoundation
import Toast_Swift

class ViewController: UIViewController {
    
    // MARK: 识别结果框,用于人脸识别
    lazy var labelResults : [UILabel] = {
        return []
    }()
    // MARK: 时间label,用于录像
    lazy var recordTimeLabel : UILabel = {
        let recordTimeLabelTmp = UILabel()
        recordTimeLabelTmp.backgroundColor = .clear
        recordTimeLabelTmp.textAlignment = .center
        recordTimeLabelTmp.textColor = .black
        recordTimeLabelTmp.isHidden = true
        return recordTimeLabelTmp
    }()
    let recordTimeMax = 8.0
    let recordTimeRefresh = 0.05
    var recordTimer : Timer?
    var recordTime : Double?
    
    
    
    @IBOutlet dynamic weak var viewContainer: UIView!
    @IBOutlet dynamic weak var flashAutoButton: UIButton!
    @IBOutlet dynamic weak var flashOnButton: UIButton!
    @IBOutlet dynamic weak var flashOffButton: UIButton!
    @IBOutlet dynamic weak var focusCursor: UIImageView!
    @IBOutlet dynamic weak var takePhotoImageView: UIImageView!
    
    
    
    // MARK: 关闭闪光灯
    @IBAction dynamic func flashOffClick(_ sender: UIButton) {
        MTCamera.shared.flashOffClick()
        setFlashModeButtonStatus()
    }
    // MARK: 开启闪光灯
    @IBAction dynamic func flashOnClick(_ sender: UIButton) {
        MTCamera.shared.flashOnClick()
        setFlashModeButtonStatus()
    }
    // MARK: 闪光灯自动
    @IBAction dynamic func flashAutoClick(_ sender: UIButton) {
        MTCamera.shared.flashAutoClick()
        setFlashModeButtonStatus()
    }
    // MARK: 切换摄像头
    @IBAction dynamic func devicePositionChangeClick(_ sender: UIButton) {
        MTCamera.shared.devicePositionChangeClick()
        setFlashModeButtonStatus()
    }
    
    
    
    // MARK: 拍照，保存图片
    @objc dynamic func takePhotoClick() {
        recordTimeLabel.text = ""
        recordTimeLabel.isHidden = true
        MTCamera.shared.takePhoto()
    }
    // MARK: 录制视频
    @objc dynamic func takeVideoClick(longPressGesture : UILongPressGestureRecognizer) {
        if longPressGesture.state == .began {
            MTCamera.shared.startRecord()
            recordTimeLabel.text = ""
            recordTimeLabel.isHidden = false
            recordTime = 0.0
            recordTimer = Timer.scheduledTimer(timeInterval: recordTimeRefresh, target: self, selector: #selector(timeRefresh), userInfo: nil, repeats: true)
            RunLoop.main.add(recordTimer!, forMode: .commonModes)
        }else if longPressGesture.state == .ended || longPressGesture.state == .cancelled || longPressGesture.state == .failed {
            MTCamera.shared.stopRecord()
            recordTimer?.invalidate()
            recordTimer = nil
        }
    }
    @objc dynamic fileprivate func timeRefresh() {
        recordTime = recordTime! + recordTimeRefresh
        recordTimeLabel.text = String(format: "%.1fs", recordTime!)
        if recordTime! >= recordTimeMax {
            MTCamera.shared.stopRecord()
            recordTimer?.invalidate()
            recordTimer = nil
        }
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    // MARK: 初始化相机
    override func viewWillAppear(_ animated: Bool) {
        let tapGesture = UITapGestureRecognizer.init(target: self, action: #selector(takePhotoClick))
        tapGesture.numberOfTouchesRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        takePhotoImageView.addGestureRecognizer(tapGesture)
        
        let longPressGesture = UILongPressGestureRecognizer.init(target: self, action: #selector(takeVideoClick(longPressGesture:)))
        longPressGesture.minimumPressDuration = 1
        takePhotoImageView.addGestureRecognizer(longPressGesture)
        
        viewContainer.addSubview(recordTimeLabel)
        recordTimeLabel.frame = CGRect(x: viewContainer.bounds.size.width/2-35, y: 0, width: 70, height: 35)
        recordTime = 0.0
        
        // MARK: 初始化相机
        MTCamera.shared.setupCamera()
        MTCamera.shared.delegate = self
        let layer = viewContainer.layer
        layer.masksToBounds = true
        let captureVideoPreviewLayer = MTCamera.shared.captureVideoPreviewLayer
        captureVideoPreviewLayer.frame = layer.bounds
        layer.insertSublayer(captureVideoPreviewLayer, below: focusCursor.layer)
        
        addGenstureRecognizer()
        setFlashModeButtonStatus()
    }
    // MARK: 闪光灯按钮状态初始化
    fileprivate func setFlashModeButtonStatus() {
        let captureDevice = MTCamera.shared.captureDeviceCamera
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
        MTCamera.shared.startRunningSession()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidAppear(animated)
        MTCamera.shared.stopRunningSession()
    }
    
    
    
    fileprivate func addGenstureRecognizer() {
        let tap = UITapGestureRecognizer.init(target: self, action: #selector(tapScreen(tapGesture:)))
        viewContainer.addGestureRecognizer(tap)
    }
    // MARK: 对焦
    @objc dynamic fileprivate func tapScreen(tapGesture : UITapGestureRecognizer) {
        let pointTap = tapGesture.location(in: viewContainer)
        let pointCamera = MTCamera.shared.captureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint: pointTap)
        setFocusCursorWithPoint(point: pointTap)
        MTCamera.shared.focusWithMode(focusMode: AVCaptureDevice.FocusMode.autoFocus, exposureMode: AVCaptureDevice.ExposureMode.autoExpose, point: pointCamera)
    }
    // MARK: 对焦动画
    fileprivate func setFocusCursorWithPoint(point : CGPoint) {
        focusCursor.center = point
        focusCursor.transform = CGAffineTransform.init(scaleX: 1.5, y: 1.5)
        focusCursor.alpha = 1.0
        UIView.animate(withDuration: 1.0, animations: {
            self.focusCursor.transform = CGAffineTransform.identity
        }) { (finished) in
            self.focusCursor.alpha = 0
        }
    }

    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}


extension ViewController : MTCameraDelegate {
    func recordFinished(error: NSError?, url: URL?) {
        if let url = url {
            print(url)
            view.makeToast("Success!", duration: 3.0, position: .center)
        }
    }
    
    func takePhotoFinished(error: NSError?, image: UIImage?) {
        if let image = image {
            print(image)
            view.makeToast("Success!", duration: 3.0, position: .center)
        }
    }
}





