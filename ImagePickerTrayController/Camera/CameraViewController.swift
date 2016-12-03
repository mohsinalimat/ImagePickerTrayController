//
//  CameraViewController.swift
//  ImagePickerTrayController
//
//  Created by Laurin Brandner on 03.12.16.
//  Copyright © 2016 Laurin Brandner. All rights reserved.
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController {
    
    let session = AVCaptureSession()
    
    fileprivate var cameraView: CameraView {
        return view as! CameraView
    }
    
    fileprivate var devicePosition: AVCaptureDevicePosition = .back {
        didSet {
            reloadCameraDevice()
        }
    }
    
    // MARK: - View Lifecycle

    override func loadView() {
        let layer = AVCaptureVideoPreviewLayer(session: session)!
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill
        
        let cameraView = CameraView(previewLayer: layer)
        cameraView.addTarget(self, action: #selector(takePicture), for: .touchUpInside)
        cameraView.flipCameraButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        
        view = cameraView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        reloadCameraDevice()
    }
    
    // MARK: - Camera
    
    fileprivate func reloadCameraDevice() {
        let device = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: devicePosition)
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)
        }
        catch {
            
        }
    }
    
    @objc fileprivate func flipCamera() {
        devicePosition = (devicePosition == .back) ? .front : .back
        
        if isViewLoaded {
            UIView.transition(with: cameraView.previewView, duration: 0.2, options: UIViewAnimationOptions(rawValue: 0), animations: {
                
            }, completion: nil)
        }
    }
    
    @objc fileprivate func takePicture() {
//        cameraController.takePicture()
    }
    
}