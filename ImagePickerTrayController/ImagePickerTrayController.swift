//
//  ImagePickerTrayController.swift
//  ImagePickerTrayController
//
//  Created by Laurin Brandner on 14.10.16.
//  Copyright © 2016 Laurin Brandner. All rights reserved.
//

import UIKit
import Photos
import MobileCoreServices

fileprivate let itemSpacing: CGFloat = 1

/// The media type an instance of ImagePickerSheetController can display
public enum ImagePickerMediaType {
    case image
    case video
    case imageAndVideo
}

@objc public protocol ImagePickerTrayControllerDelegate {
    
    @objc optional func controller(_ controller: ImagePickerTrayController, willSelectAsset asset: PHAsset)
    @objc optional func controller(_ controller: ImagePickerTrayController, didSelectAsset asset: PHAsset)
    
    @objc optional func controller(_ controller: ImagePickerTrayController, willDeselectAsset asset: PHAsset)
    @objc optional func controller(_ controller: ImagePickerTrayController, didDeselectAsset asset: PHAsset)
    
    @objc optional func controller(_ controller: ImagePickerTrayController, didTakeImage image:UIImage)
    
}

public class ImagePickerTrayController: UIViewController {
    
    fileprivate(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 2, right: 1)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor(red: 209.0/255.0, green: 213.0/255.0, blue: 218.0/255.0, alpha: 1.0)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        
        collectionView.register(ActionCell.self, forCellWithReuseIdentifier: NSStringFromClass(ActionCell.self))
        collectionView.register(CameraCell.self, forCellWithReuseIdentifier: NSStringFromClass(CameraCell.self))
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: NSStringFromClass(ImageCell.self))
        
        return collectionView
    }()
    
    fileprivate lazy var cameraController: UIImagePickerController = {
        let controller = UIImagePickerController()
        controller.delegate =  self
        controller.sourceType = .camera
        controller.showsCameraControls = false
        controller.allowsEditing = false
        controller.cameraFlashMode = .off
        controller.mediaTypes = [kUTTypeImage as String, kUTTypeLivePhoto as String]
        
        let view = CameraOverlayView()
        view.addTarget(self, action: #selector(takePicture), for: .touchUpInside)
        view.flipCameraButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        controller.cameraOverlayView = view
        
        return controller
    }()
    
    fileprivate var assets = [PHAsset]()
    
    fileprivate lazy var requestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        
        return options
    }()
    
    fileprivate let imageManager = PHCachingImageManager()
    
    /// The media type of the displayed assets
    open let mediaType: ImagePickerMediaType = .imageAndVideo
    
    open var allowsMultipleSelection = true {
        didSet {
            if isViewLoaded {
                collectionView.allowsMultipleSelection = allowsMultipleSelection
            }
        }
    }
    
    fileprivate let height: CGFloat
    
    fileprivate var imageSize: CGSize = .zero

    fileprivate let actionCellWidth: CGFloat = 162
    
    fileprivate weak var actionCell: ActionCell?

    public fileprivate(set) var actions = [ImagePickerAction]()

    fileprivate var sections: [Int] {
        let actionSection = (actions.count > 0) ? 1 : 0
        let cameraSection = UIImagePickerController.isSourceTypeAvailable(.camera) ? 1 : 0
        let assetSection = assets.count
        
        return [actionSection, cameraSection, assetSection]
    }
    
    public var delegate: ImagePickerTrayControllerDelegate?
    
    // MARK: - Initialization
    
    public init() {
        self.height = 216
        
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    public override func loadView() {
        super.loadView()
        
        view.addSubview(collectionView)
        collectionView.heightAnchor.constraint(equalToConstant: height).isActive = true
        collectionView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        collectionView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        collectionView.allowsMultipleSelection = allowsMultipleSelection
        
        let numberOfRows = (UIDevice.current.userInterfaceIdiom == .pad) ? 3 : 2
        let totalItemSpacing = CGFloat(numberOfRows-1)*itemSpacing + collectionView.contentInset.vertical
        let side = round((self.height-totalItemSpacing)/CGFloat(numberOfRows))
        self.imageSize = CGSize(width: side, height: side)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        fetchAssets()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        collectionView.setContentOffset(CGPoint(x: actionCellWidth - spacing.x, y: 0), animated: false)
        reloadActionCellDisclosureProgress()
    }
    
    // MARK: - Action
    
    public func add(action: ImagePickerAction) {
        actions.append(action)
    }
    
    // MARK: - Images
    
    fileprivate func prepareAssets() {
        fetchAssets()
    }
    
    fileprivate func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch mediaType {
        case .image:
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        case .video:
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        case .imageAndVideo:
            options.predicate = NSPredicate(format: "mediaType = %d OR mediaType = %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        }
        
        let fetchLimit = 100
        options.fetchLimit = fetchLimit
        
        let result = PHAsset.fetchAssets(with: options)
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .fastFormat
        
        result.enumerateObjects(options: [], using: { asset, index, stop in
            defer {
                if self.assets.count >= fetchLimit {
                    stop.initialize(to: true)
                }
            }
            
            self.imageManager.requestImageData(for: asset, options: requestOptions) { data, _, _, info in
                if data != nil {
                    self.assets.append(asset)
                }
            }
        })
    }
    
    fileprivate func requestImage(for asset: PHAsset, completion: @escaping (_ image: UIImage?) -> ()) {
        requestOptions.isSynchronous = true
        let size = scale(imageSize: imageSize)
        
        // Workaround because PHImageManager.requestImageForAsset doesn't work for burst images
        if asset.representsBurst {
            imageManager.requestImageData(for: asset, options: requestOptions) { data, _, _, _ in
                let image = data.flatMap { UIImage(data: $0) }
                completion(image)
            }
        }
        else {
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: requestOptions) { image, _ in
                completion(image)
            }
        }
    }
    
    fileprivate func prefetchImages(for asset: PHAsset) {
        let size = scale(imageSize: imageSize)
        imageManager.startCachingImages(for: [asset], targetSize: size, contentMode: .aspectFill, options: requestOptions)
    }
    
    fileprivate func scale(imageSize size: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    
    // MARK: - Camera
    
    @objc fileprivate func flipCamera() {
        cameraController.cameraDevice = (cameraController.cameraDevice == .rear) ? .front : .rear
    }
    
    @objc fileprivate func takePicture() {
        cameraController.takePicture()
    }
    
    // MARK: -
    
    fileprivate func reloadActionCellDisclosureProgress() {
        if sections[0] > 0 {
            actionCell?.disclosureProcess = (collectionView.contentOffset.x / (actionCellWidth/2))
        }
    }
    
}

// MARK: - UICollectionViewDataSource

extension ImagePickerTrayController: UICollectionViewDataSource {
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sections[section]
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch indexPath.section {
        case 0:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NSStringFromClass(ActionCell.self), for: indexPath) as! ActionCell
            cell.actions = actions
            actionCell = cell
            reloadActionCellDisclosureProgress()
            
            return cell
        case 1:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NSStringFromClass(CameraCell.self), for: indexPath) as! CameraCell
            cell.cameraView = cameraController.view
            cell.cameraOverlayView = cameraController.cameraOverlayView
            
            return cell
        case 2:
            let asset = assets[indexPath.item]
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NSStringFromClass(ImageCell.self), for: indexPath) as! ImageCell
            requestImage(for: asset) { cell.imageView.image = $0 }
            cell.accessoryType = (asset.mediaType == .video) ? .video : .none
            
            return cell
        default:
            fatalError("More than 3 sections are invalid.")
        }
    }
    
}

// MARK: - UICollectionViewDelegate

extension ImagePickerTrayController: UICollectionViewDelegate {
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard indexPath.section == sections.count - 1 else {
            return false
        }
        
        delegate?.controller?(self, willSelectAsset: assets[indexPath.item])
        
        return true
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.controller?(self, didSelectAsset: assets[indexPath.item])
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        delegate?.controller?(self, willDeselectAsset: assets[indexPath.item])
        
        return true
    }
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        delegate?.controller?(self, didDeselectAsset: assets[indexPath.item])
    }
    
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImagePickerTrayController: UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let maxItemHeight = collectionView.frame.height-collectionView.contentInset.vertical
        
        switch indexPath.section {
        case 0:
            return CGSize(width: actionCellWidth, height: maxItemHeight)
        case 1:
            return CGSize(width: 150, height: maxItemHeight)
        case 2:
            return imageSize
        default:
            return .zero
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard section == 1 else {
            return UIEdgeInsets()
        }
        
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
    }
    
}

// MARK: - UIScrollViewDelegate

extension ImagePickerTrayController: UIScrollViewDelegate {

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reloadActionCellDisclosureProgress()
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ImagePickerTrayController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            delegate?.controller?(self, didTakeImage: image)
        }
    }
    
}

// MARK: - UIViewControllerTransitioningDelegate

extension ImagePickerTrayController: UIViewControllerTransitioningDelegate {
    
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerTrayController: self, presenting: true)
    }
    
    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerTrayController: self, presenting: false)
    }
    
}
