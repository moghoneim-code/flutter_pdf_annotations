import Flutter
import UIKit
import PDFKit

public class FlutterPdfAnnotationsPlugin: NSObject, FlutterPlugin {
    private static weak var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "flutter_pdf_annotations", binaryMessenger: registrar.messenger())
        channel = methodChannel
        let instance = FlutterPdfAnnotationsPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "openPDF":
            handleOpenPDFMethod(call: call, result: result)
        default:
            sendLogToFlutter("Unimplemented method: \(call.method)")
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleOpenPDFMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String,
              let savePath = args["savePath"] as? String else {
            sendLogToFlutter("Missing or invalid arguments for method 'openPDF'")
            result(FlutterError(code: "INVALID_ARGUMENTS",
                                message: "Missing or invalid arguments",
                                details: nil))
            return
        }

        let pdfURL = URL(fileURLWithPath: filePath)
        let saveURL = URL(fileURLWithPath: savePath)

        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            sendLogToFlutter("File not found at path: \(filePath)")
            result(FlutterError(code: "FILE_NOT_FOUND",
                                message: "File not found at path: \(filePath)",
                                details: nil))
            return
        }

        sendLogToFlutter("File path: \(filePath), Save path: \(savePath)")

        DispatchQueue.main.async {
            self.presentPDFViewController(pdfURL: pdfURL, saveURL: saveURL, result: result)
        }
    }

private func presentPDFViewController(pdfURL: URL, saveURL: URL, result: @escaping FlutterResult) {
    let pdfViewController = PDFViewController(
        pdfURL: pdfURL,
        saveURL: saveURL,
        logChannel: FlutterPdfAnnotationsPlugin.channel
    ) { [weak self] savedFilePath in
        guard let self = self else { return }
        if let path = savedFilePath {
            self.sendLogToFlutter("PDF saved at: \(path)")
            result(path)
        } else {
            self.sendLogToFlutter("Failed to save the PDF")
            result(FlutterError(code: "SAVE_FAILED",
                                message: "Failed to save the PDF",
                                details: nil))
        }
    }

    guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
        self.sendLogToFlutter("Unable to find root view controller")
        result(FlutterError(code: "NO_ROOT_VIEW_CONTROLLER",
                            message: "Unable to find root view controller",
                            details: nil))
        return
    }

    let navigationController = UINavigationController(rootViewController: pdfViewController)
    navigationController.modalPresentationStyle = .fullScreen // Set presentation style to fullscreen
    rootVC.present(navigationController, animated: true) {
        self.sendLogToFlutter("Presented PDFViewController")
    }
}


    private func sendLogToFlutter(_ message: String) {
        FlutterPdfAnnotationsPlugin.channel?.invokeMethod("log", arguments: message)
    }
}

class PDFViewController: UIViewController, UIColorPickerViewControllerDelegate {
    private let pdfURL: URL
    private let saveURL: URL
    private var pdfView: PDFView!
    private var penThickness: CGFloat = 2.0
    private var penColor: UIColor = .red
    private var completion: ((String?) -> Void)?
    private weak var logChannel: FlutterMethodChannel?

    // Declare properties for drawing gestures
    private var currentPath: UIBezierPath?
    private var currentAnnotation: PDFAnnotation?
    private var panGesture: UIPanGestureRecognizer!

    init(pdfURL: URL,
         saveURL: URL,
         logChannel: FlutterMethodChannel?,
         completion: @escaping (String?) -> Void) {
        self.pdfURL = pdfURL
        self.saveURL = saveURL
        self.logChannel = logChannel
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sendLogToFlutter("PDFViewController loaded with URL: \(pdfURL)")
        setupView()
        setupPDFView()
        setupToolbar()
        setupPanGesture()
        setupFloatingBar()
    }

    private func setupView() {
        view.backgroundColor = .white
        navigationItem.title = "PDF Annotations"
    }

private func setupPDFView() {
    pdfView = PDFView(frame: view.bounds)
    pdfView.autoScales = true
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical
    pdfView.translatesAutoresizingMaskIntoConstraints = false
    pdfView.isUserInteractionEnabled = true

    guard let document = PDFDocument(url: pdfURL) else {
        sendLogToFlutter("Failed to load PDF document")
        return
    }

    pdfView.document = document

    // Remove text selection gestures
    if let gestureRecognizers = pdfView.gestureRecognizers {
        for recognizer in gestureRecognizers {
            if let tapGesture = recognizer as? UITapGestureRecognizer,
               NSStringFromClass(type(of: tapGesture)) == "UIPDFSelectionTapRecognizer" {
                pdfView.removeGestureRecognizer(tapGesture)
            }
        }
    }

    view.addSubview(pdfView)

    NSLayoutConstraint.activate([
        pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}


    private func setupToolbar() {
        let cancelButton = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(dismissViewController)
        )
        let saveButton = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(savePDF)
        )
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = saveButton
    }

      private var isDrawingEnabled = false
        private var drawingButton: UIButton!

private func setupFloatingBar() {
        let floatingContainer = UIView()
        floatingContainer.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        floatingContainer.layer.cornerRadius = 10
        floatingContainer.clipsToBounds = true
        floatingContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(floatingContainer)

        NSLayoutConstraint.activate([
            floatingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            floatingContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            floatingContainer.widthAnchor.constraint(equalToConstant: 60),
            floatingContainer.heightAnchor.constraint(equalToConstant: 240)
        ])

        let floatingStack = UIStackView()
        floatingStack.axis = .vertical
        floatingStack.spacing = 15
        floatingStack.alignment = .center
        floatingStack.translatesAutoresizingMaskIntoConstraints = false

        floatingContainer.addSubview(floatingStack)

        NSLayoutConstraint.activate([
            floatingStack.leadingAnchor.constraint(equalTo: floatingContainer.leadingAnchor),
            floatingStack.trailingAnchor.constraint(equalTo: floatingContainer.trailingAnchor),
            floatingStack.topAnchor.constraint(equalTo: floatingContainer.topAnchor, constant: 10),
            floatingStack.bottomAnchor.constraint(equalTo: floatingContainer.bottomAnchor, constant: -10)
        ])

        // Drawing Toggle Button
        drawingButton = UIButton(type: .system)
        drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
        drawingButton.tintColor = .white
        drawingButton.addTarget(self, action: #selector(toggleDrawing), for: .touchUpInside)
        floatingStack.addArrangedSubview(drawingButton)

        let colorPickerButton = UIButton(type: .system)
        colorPickerButton.setImage(UIImage(systemName: "paintpalette"), for: .normal)
        colorPickerButton.tintColor = .white
        colorPickerButton.addTarget(self, action: #selector(openColorPicker), for: .touchUpInside)
        floatingStack.addArrangedSubview(colorPickerButton)

        let penSizeButton = UIButton(type: .system)
        penSizeButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        penSizeButton.tintColor = .white
        penSizeButton.addTarget(self, action: #selector(openPenSizeSlider), for: .touchUpInside)
        floatingStack.addArrangedSubview(penSizeButton)
    }

       private var originalGestureRecognizers: [UIGestureRecognizer]?
    private var scrollView: UIScrollView?


   @objc private func toggleDrawing() {
        isDrawingEnabled.toggle()

        if isDrawingEnabled {
            // Disable existing gestures
            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { recognizer in
                recognizer.isEnabled = false
            }

            // Find and disable scrolling
            scrollView = findScrollView(in: pdfView)
            scrollView?.isScrollEnabled = false

            // Re-enable pan gesture for drawing
            panGesture.isEnabled = true

            drawingButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            drawingButton.tintColor = .green
            sendLogToFlutter("Drawing enabled")
        } else {
            // Restore original gestures
            pdfView.gestureRecognizers = originalGestureRecognizers

            // Re-enable scrolling
            scrollView?.isScrollEnabled = true

            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .white
            sendLogToFlutter("Drawing disabled")
        }
    }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView {
                    return scrollView
                }

                if let foundScrollView = findScrollView(in: subview) {
                    return foundScrollView
                }
            }
            return nil
        }



   private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = true
        panGesture.delaysTouchesEnded = true
        pdfView.addGestureRecognizer(panGesture)
    }

   @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // Only handle drawing if drawing is enabled
        guard isDrawingEnabled, let page = pdfView.currentPage else { return }

        let location = gesture.location(in: pdfView)
        let pageLocation = pdfView.convert(location, to: page)

        switch gesture.state {
        case .began:
            // Clear any previous incomplete drawing
            if currentAnnotation != nil {
                page.removeAnnotation(currentAnnotation!)
            }

            currentPath = UIBezierPath()
            currentPath?.move(to: pageLocation)

            currentAnnotation = PDFAnnotation(
                bounds: page.bounds(for: .mediaBox),
                forType: .ink,
                withProperties: nil
            )
            currentAnnotation?.color = penColor

            let border = PDFBorder()
            border.lineWidth = penThickness
            currentAnnotation?.border = border

            // Prevent multiple touches
            gesture.cancelsTouchesInView = true


        case .changed:
            guard let path = currentPath, let annotation = currentAnnotation else { return }

            path.addLine(to: pageLocation)
            annotation.add(path)

            if let page = pdfView.currentPage {
                // Remove previous annotation to avoid duplicates
                page.removeAnnotation(annotation)
                page.addAnnotation(annotation)
            }

            pdfView.setNeedsDisplay()

        case .ended:
            guard let page = pdfView.currentPage,
                  let annotation = currentAnnotation else { return }

            // Ensure the final annotation is added
            page.addAnnotation(annotation)

            // Reset drawing state
            currentAnnotation = nil
            currentPath = nil

        default:
            break
        }
    }

    @objc private func openColorPicker() {
        let colorPicker = UIColorPickerViewController()
        colorPicker.selectedColor = penColor
        colorPicker.delegate = self
        present(colorPicker, animated: true, completion: nil)
    }

    @objc private func openPenSizeSlider() {
        let alert = UIAlertController(title: "Pen Size", message: "\n\n\n", preferredStyle: .alert)
        let slider = UISlider(frame: CGRect(x: 10, y: 50, width: 250, height: 20))
        slider.minimumValue = 1.0
        slider.maximumValue = 10.0
        slider.value = Float(penThickness)
        slider.addTarget(self, action: #selector(updatePenSize(_:)), for: .valueChanged)
        alert.view.addSubview(slider)

        let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }

    @objc private func updatePenSize(_ sender: UISlider) {
        penThickness = CGFloat(sender.value)
    }

@objc private func savePDF() {
    sendLogToFlutter("Save PDF button tapped")

    guard let document = pdfView.document else {
        sendLogToFlutter("No PDF document found to save")
        completion?(nil)
        dismiss(animated: true, completion: nil)
        return
    }

    do {
        // Explicitly capture self
        try document.write(to: self.saveURL)
        self.sendLogToFlutter("PDF successfully saved at \(self.saveURL.path)")

        dismiss(animated: true) {
            self.completion?(self.saveURL.path)
        }
    } catch {
        self.sendLogToFlutter("Error saving PDF: \(error.localizedDescription)")
        dismiss(animated: true) {
            self.completion?(nil)
        }
    }
}


    private func sendLogToFlutter(_ message: String) {
        logChannel?.invokeMethod("log", arguments: message)
    }

    @objc private func dismissViewController() {
        dismiss(animated: true) {
            self.completion?(nil)
        }
    }

    // UIColorPickerViewControllerDelegate
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        penColor = viewController.selectedColor
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        penColor = viewController.selectedColor
    }
}