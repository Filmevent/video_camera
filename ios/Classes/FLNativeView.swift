import Flutter
import UIKit
import SwiftUI

class FLNativeViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return FLNativeView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger)
    }
}

class FLNativeView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var viewModel: ViewModel
    private var hostingController: UIHostingController<CameraView>?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView()
        viewModel = ViewModel()
        super.init()
        // Create and embed the SwiftUI view
        createNativeView(view: _view, frame: frame)
    }

    func view() -> UIView {
        return _view
    }

    func createNativeView(view: UIView, frame: CGRect) {
        // Create a SwiftUI CameraView with binding to viewModel
        let cameraView = CameraView(image: Binding(
            get: { self.viewModel.currentFrame },
            set: { self.viewModel.currentFrame = $0 }
        ))
        
        // Create a hosting controller to embed SwiftUI in UIKit
        hostingController = UIHostingController(rootView: cameraView)
        
        guard let hostingController = hostingController else { return }
        
        // Add the hosting controller's view as a subview
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.backgroundColor = .clear
        
        view.addSubview(hostingController.view)
        
        // Important: Add the hosting controller as a child view controller
        // This ensures proper lifecycle management
        if let parentViewController = view.parentViewController {
            parentViewController.addChild(hostingController)
            hostingController.didMove(toParent: parentViewController)
        }
    }
}

// Extension to find the parent view controller
extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder?.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}