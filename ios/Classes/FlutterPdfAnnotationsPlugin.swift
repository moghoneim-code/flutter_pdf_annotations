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
        let initialPage = args["initialPage"] as? Int ?? 0
        let locale = args["locale"] as? String
        FPAStrings.configure(locale: locale)
        let config = PDFAnnotationConfig(
            title: title,
            initialPenColor: penColorInt.map { colorFromArgbInt($0) },
            initialHighlightColor: hlColorInt.map { colorFromArgbInt($0) },
            initialStrokeWidth: strokeWidth.map { CGFloat($0) },
            imagePaths: imagePaths,
            initialPage: initialPage
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
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            FlutterPdfAnnotationsPlugin.notifySaveError("No active window scene available")
            return
        }

        let pdfViewController = PDFViewController(
            pdfURL: pdfURL,
            saveURL: saveURL,
            config: config
        ) { savedPath in
            if let path = savedPath, FileManager.default.fileExists(atPath: path) {
                FlutterPdfAnnotationsPlugin.notifySaveResult(path)
            } else if savedPath != nil {
                // Path was returned but file doesn't exist — save failed
                FlutterPdfAnnotationsPlugin.notifySaveError("Saved file not found at reported path")
            } else {
                // nil → user cancelled
                FlutterPdfAnnotationsPlugin.notifyCancelled()
            }
        }

        let navigationController = UINavigationController(rootViewController: pdfViewController)
        navigationController.modalPresentationStyle = .fullScreen
        rootVC.present(navigationController, animated: true) {
            // Presentation succeeded — nothing extra needed
        }
    }

    /// Notify Flutter: user saved successfully.
    static func notifySaveResult(_ path: String) {
        notify(["status": "success", "path": path])
    }

    /// Notify Flutter: user cancelled without saving.
    static func notifyCancelled() {
        notify(["status": "cancelled"])
    }

    /// Notify Flutter: a save error occurred.
    static func notifySaveError(_ message: String) {
        notify(["status": "error", "message": message])
    }

    private static func notify(_ args: [String: String]) {
        DispatchQueue.main.async {
            methodChannel?.invokeMethod("onPdfSaved", arguments: args)
        }
    }
}
