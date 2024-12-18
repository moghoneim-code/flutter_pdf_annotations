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
                              message: "File not found at path: \(filePath)",
                              details: nil))
            return
        }
        
        // Send initial success for opening PDF
        result(nil)
        
        DispatchQueue.main.async {
            self.presentPDFViewController(pdfURL: pdfURL, saveURL: saveURL)
        }
    }
    
    private func presentPDFViewController(pdfURL: URL, saveURL: URL) {
        let pdfViewController = PDFViewController(
            pdfURL: pdfURL,
            saveURL: saveURL
        ) { savedPath in
            // This closure is called when saving is complete
            if let path = savedPath {
                // Notify Flutter of successful save
                FlutterPdfAnnotationsPlugin.notifySaveResult(path)
            } else {
                // Notify Flutter of save failure
                FlutterPdfAnnotationsPlugin.notifySaveResult(nil)
            }
        }
        
        guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
            FlutterPdfAnnotationsPlugin.notifySaveResult(nil)
            return
        }
        
        let navigationController = UINavigationController(rootViewController: pdfViewController)
        navigationController.modalPresentationStyle = .fullScreen
        rootVC.present(navigationController, animated: true, completion: nil)
    }
    
    private static func notifySaveResult(_ path: String?) {
        DispatchQueue.main.async {
            methodChannel?.invokeMethod("onPdfSaved", arguments: path)
        }
    }
}

class PDFViewController: UIViewController, UIColorPickerViewControllerDelegate {
    private let pdfURL: URL
    private let saveURL: URL
    private var pdfView: PDFView!
    private var penThickness: CGFloat = 2.0
    private var penColor: UIColor = .red
    private var completion: ((String?) -> Void)
    
    private var isDrawingEnabled = false
    private var currentPath: UIBezierPath?
    private var currentAnnotation: PDFAnnotation?
    private var panGesture: UIPanGestureRecognizer!
    private var drawingButton: UIButton!
    private var originalGestureRecognizers: [UIGestureRecognizer]?
    private var scrollView: UIScrollView?

    init(pdfURL: URL, saveURL: URL, completion: @escaping (String?) -> Void) {
        self.pdfURL = pdfURL
        self.saveURL = saveURL
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
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
            return
        }

        pdfView.document = document

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

    private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = true
        panGesture.delaysTouchesEnded = true
        pdfView.addGestureRecognizer(panGesture)
    }

    @objc private func toggleDrawing() {
        isDrawingEnabled.toggle()

        if isDrawingEnabled {
            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { recognizer in
                recognizer.isEnabled = false
            }

            scrollView = findScrollView(in: pdfView)
            scrollView?.isScrollEnabled = false

            panGesture.isEnabled = true

            drawingButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            drawingButton.tintColor = .green
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers
            scrollView?.isScrollEnabled = true

            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .white
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

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard isDrawingEnabled, let page = pdfView.currentPage else { return }

        let location = gesture.location(in: pdfView)
        let pageLocation = pdfView.convert(location, to: page)

        switch gesture.state {
        case .began:
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

            gesture.cancelsTouchesInView = true

        case .changed:
            guard let path = currentPath, let annotation = currentAnnotation else { return }

            path.addLine(to: pageLocation)
            annotation.add(path)

            if let page = pdfView.currentPage {
                page.removeAnnotation(annotation)
                page.addAnnotation(annotation)
            }

            pdfView.setNeedsDisplay()

        case .ended:
            guard let page = pdfView.currentPage,
                  let annotation = currentAnnotation else { return }

            page.addAnnotation(annotation)
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
        guard let document = pdfView.document else {
            completion(nil)
            dismiss(animated: true, completion: nil)
            return
        }

        do {
            try document.write(to: saveURL)
            dismiss(animated: true) {
                self.completion(self.saveURL.path)
            }
        } catch {
            dismiss(animated: true) {
                self.completion(nil)
            }
        }
    }
    
    @objc private func dismissViewController() {
        dismiss(animated: true) {
            self.completion(nil)
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
