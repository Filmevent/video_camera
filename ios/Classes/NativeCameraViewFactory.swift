import Flutter
import UIKit

class NativeCameraViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    // This method is called by Flutter when it wants to create a new platform view.
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments: Any?
    ) -> FlutterPlatformView {
        return NativeCameraView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: arguments,
            binaryMessenger: messenger
        )
    }

    // This is a boilerplate method required by the protocol.
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
          return FlutterStandardMessageCodec.sharedInstance()
    }
}
