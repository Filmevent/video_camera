import Flutter
import UIKit
import SwiftUI
import Observation

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


    /// Implementing this method is only necessary when the `arguments` in `createWithFrame` is not `nil`.
/*     public func createArgsCodec() -> FlutterMessageCodec &#x26; NSObjectProtocol {
          return FlutterStandardMessageCodec.sharedInstance()
    } */
}

class FLNativeView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var viewModel: ViewModel


    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView()
        viewModel = ViewModel()
        super.init()
        // iOS views can be created here
        createNativeView(view: _view, frame: frame)
    }

    func view() -> UIView {
        return _view
    }

    func createNativeView(view _view: UIView, frame: CGRect){
        NSLog("Native View Created")
        
        let cameraView = CameraView(image: Binding(
            get: { self.viewModel.currentFrame },
            set: { self.viewModel.currentFrame = $0 }
        ))

        let hostingController = UIHostingController(rootView: cameraView)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = UIColor.clear

        _view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: _view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: _view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: _view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: _view.bottomAnchor)
        ])
    }
}