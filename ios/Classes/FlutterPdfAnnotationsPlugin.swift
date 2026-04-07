import Flutter
import UIKit
import PDFKit

public class FlutterPdfAnnotationsPlugin: NSObject, FlutterPlugin {
    private static var methodChannel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pdf_annotations", binaryMessenger: registrar.messenger())
        methodChannel = channel
        let instance = FlutterPdfAnnotationsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "openPDF":
            handleOpenPDFMethod(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleOpenPDFMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String,
              let savePath = args["savePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                                message: "Missing or invalid arguments",
                                details: nil))
            return
        }

        let pdfURL = URL(fileURLWithPath: filePath)
        let saveURL = URL(fileURLWithPath: savePath)

        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            result(FlutterError(code: "FILE_NOT_FOUND",
                                message: "Source PDF not found at path: \(filePath)",
                                details: nil))
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            result(FlutterError(code: "DIRECTORY_CREATE_ERROR",
                                message: "Failed to create save directory: \(error.localizedDescription)",
                                details: nil))
            return
        }

        // Build optional config
        let title = args["title"] as? String
        let penColorInt = args["initialPenColor"] as? Int
        let hlColorInt = args["initialHighlightColor"] as? Int
        let strokeWidth = args["initialStrokeWidth"] as? Double
        let imagePaths = args["imagePaths"] as? [String]
        let config = PDFAnnotationConfig(
            title: title,
            initialPenColor: penColorInt.map { colorFromArgbInt($0) },
            initialHighlightColor: hlColorInt.map { colorFromArgbInt($0) },
            initialStrokeWidth: strokeWidth.map { CGFloat($0) },
            imagePaths: imagePaths
        )

        result(nil)

        DispatchQueue.main.async {
            self.presentPDFViewController(pdfURL: pdfURL, saveURL: saveURL, config: config)
        }
    }

    /// Converts a signed ARGB Int32 (from Dart's Color.toARGB32().toSigned(32)) to UIColor.
    private func colorFromArgbInt(_ value: Int) -> UIColor {
        let argb = value & 0xFFFFFFFF
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private func presentPDFViewController(pdfURL: URL, saveURL: URL, config: PDFAnnotationConfig?) {
        let pdfViewController = PDFViewController(
            pdfURL: pdfURL,
            saveURL: saveURL,
            config: config
        ) { savedPath in
            if let path = savedPath, FileManager.default.fileExists(atPath: path) {
                FlutterPdfAnnotationsPlugin.notifySaveResult(path)
            } else {
                FlutterPdfAnnotationsPlugin.notifySaveResult(nil)
            }
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            FlutterPdfAnnotationsPlugin.notifySaveResult(nil)
            return
        }

        let navigationController = UINavigationController(rootViewController: pdfViewController)
        navigationController.modalPresentationStyle = .fullScreen
        rootVC.present(navigationController, animated: true, completion: nil)
    }

    static func notifySaveResult(_ path: String?) {
        DispatchQueue.main.async {
            methodChannel?.invokeMethod("onPdfSaved", arguments: path)
        }
    }
}
