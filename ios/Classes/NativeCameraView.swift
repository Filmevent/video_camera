import Flutter
import UIKit

class NativeCameraView: NSObject, FlutterPlatformView {
    private var _viewController: MetalCameraViewController

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        // Instantiate your custom ViewController
        _viewController = MetalCameraViewController()
        super.init()
    }

    // This method is required by the protocol and returns the view to Flutter.
    func view() -> UIView {
        return _viewController.view
    }
}
