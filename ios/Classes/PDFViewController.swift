import UIKit
import PDFKit

struct PDFAnnotationConfig {
    let title: String?
    let initialPenColor: UIColor?
    let initialHighlightColor: UIColor?
    let initialStrokeWidth: CGFloat?
    let imagePaths: [String]?
}

// MARK: - ImagePDFAnnotation (data container only — rendering handled by ImageAnnotationOverlayView)

class ImagePDFAnnotation: PDFAnnotation {
    let image: UIImage

    init(image: UIImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .link, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = 0
        self.border = border
        self.color = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    // draw(with:in:) intentionally not overridden.
    // Live rendering is done by ImageAnnotationOverlayView.
    // Save rendering is done manually in savePDF() without selection handles.
}

// MARK: - ImageAnnotationOverlayView

private class ImageAnnotationOverlayView: UIView {
    var annotations: [ImagePDFAnnotation] = []
    var selectedAnnotation: ImagePDFAnnotation?
    weak var pdfView: PDFView?
    var aspectRatioLocked: Bool = false

    // Visual constants
    private let cornerHalf: CGFloat = 13   // half-side of corner handle square (bigger for easier grabbing)
    private let deleteRadius: CGFloat = 14  // radius of delete circle
    let confirmRadius: CGFloat = 16  // radius of confirm circle (accessible for hit-testing)
    private let borderWidth: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let pdfView = pdfView,
              let context = UIGraphicsGetCurrentContext() else { return }

        for ann in annotations {
            guard let page = ann.page else { continue }
            // Convert PDF-page bounds → pdfView coordinate space (UIKit, y-down)
            let sr = pdfView.convert(ann.bounds, from: page)

            // Draw the image
            ann.image.draw(in: sr)

            guard ann === selectedAnnotation else { continue }

            // ── Semi-transparent selection overlay ─────────────────────────────
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.06).cgColor)
            context.fill(sr)

            // ── Dashed selection border ──────────────────────────────────────
            context.saveGState()
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(borderWidth)
            context.setLineDash(phase: 0, lengths: [8, 4])
            context.stroke(sr)
            context.restoreGState()

            context.setLineDash(phase: 0, lengths: [])

            // ── Corner resize handles (rounded squares) ──────────────────────
            let corners = [
                CGPoint(x: sr.minX, y: sr.minY),   // visual top-left
                CGPoint(x: sr.maxX, y: sr.minY),   // visual top-right
                CGPoint(x: sr.minX, y: sr.maxY),   // visual bottom-left
                CGPoint(x: sr.maxX, y: sr.maxY),   // visual bottom-right
            ]
            for pt in corners {
                let cr = CGRect(x: pt.x - cornerHalf, y: pt.y - cornerHalf,
                                width: cornerHalf * 2, height: cornerHalf * 2)
                let handlePath = UIBezierPath(roundedRect: cr, cornerRadius: 5)
                // Shadow for depth
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                                  color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.setFill()
                handlePath.fill()
                context.restoreGState()
                // Blue border
                UIColor.systemBlue.setStroke()
                handlePath.lineWidth = 2
                handlePath.stroke()
            }

            // ── Delete button at visual top-center ───────────────────────────
            let dc = CGPoint(x: sr.midX, y: sr.minY)
            let dr = CGRect(x: dc.x - deleteRadius, y: dc.y - deleteRadius,
                            width: deleteRadius * 2, height: deleteRadius * 2)
            // Shadow
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                              color: UIColor.black.withAlphaComponent(0.35).cgColor)
            context.setFillColor(UIColor.systemRed.cgColor)
            context.fillEllipse(in: dr)
            context.restoreGState()

            // White X mark
            let xOff = deleteRadius * 0.42
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: dc.x - xOff, y: dc.y - xOff))
            context.addLine(to: CGPoint(x: dc.x + xOff, y: dc.y + xOff))
            context.strokePath()
            context.move(to: CGPoint(x: dc.x + xOff, y: dc.y - xOff))
            context.addLine(to: CGPoint(x: dc.x - xOff, y: dc.y + xOff))
            context.strokePath()

            // ── Confirm button at visual bottom-center (green circle + white checkmark) ──
            let cc = CGPoint(x: sr.midX, y: sr.maxY + confirmRadius + 4)
            let ccr = CGRect(x: cc.x - confirmRadius, y: cc.y - confirmRadius,
                             width: confirmRadius * 2, height: confirmRadius * 2)
            // Shadow
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                              color: UIColor.black.withAlphaComponent(0.3).cgColor)
            context.setFillColor(UIColor.systemGreen.cgColor)
            context.fillEllipse(in: ccr)
            context.restoreGState()

            // White checkmark
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: cc.x - confirmRadius * 0.35, y: cc.y))
            context.addLine(to: CGPoint(x: cc.x - confirmRadius * 0.05, y: cc.y + confirmRadius * 0.3))
            context.addLine(to: CGPoint(x: cc.x + confirmRadius * 0.4, y: cc.y - confirmRadius * 0.3))
            context.strokePath()

            // ── Aspect ratio indicator text ──────────────────────────────────
            let infoText = (aspectRatioLocked ? "Aspect locked" : "Free resize") as NSString
            let infoColor = aspectRatioLocked ? UIColor.systemBlue : UIColor.systemOrange
            let infoFont = UIFont.systemFont(ofSize: 10, weight: .medium)
            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: infoFont,
                .foregroundColor: infoColor.withAlphaComponent(0.7)
            ]
            let infoSize = infoText.size(withAttributes: infoAttrs)
            let infoRect = CGRect(x: sr.midX - infoSize.width / 2,
                                  y: cc.y + confirmRadius + 3,
                                  width: infoSize.width, height: infoSize.height)
            infoText.draw(in: infoRect, withAttributes: infoAttrs)
        }
    }

    /// Returns the center of the confirm button in view coordinates for the selected annotation.
    func confirmButtonViewCenter() -> CGPoint? {
        guard let pdfView = pdfView, let ann = selectedAnnotation, let page = ann.page else { return nil }
        let sr = pdfView.convert(ann.bounds, from: page)
        return CGPoint(x: sr.midX, y: sr.maxY + confirmRadius + 4)
    }
}

// MARK: - PDFViewController

class PDFViewController: UIViewController, UIColorPickerViewControllerDelegate {
    private let pdfURL: URL
    private let saveURL: URL
    private let config: PDFAnnotationConfig?
    private var pdfView: PDFView!
    private var penThickness: CGFloat = 5.0
    private var penColor: UIColor = .red
    private var completion: ((String?) -> Void)

    private var isDrawingEnabled = false
    private var isEraserMode = false
    private var isHighlightMode = false
    private var highlightColor: UIColor = UIColor.yellow.withAlphaComponent(0.5)
    private var highlightStartPoint: CGPoint?
    private var currentPath: UIBezierPath?
    private var currentAnnotation: PDFAnnotation?
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var drawingButton: UIButton!
    private var eraserButton: UIButton!
    private var highlightButton: UIButton!
    private var colorButton: UIButton!
    private var sizeSButton: UIButton!
    private var sizeMButton: UIButton!
    private var sizeLButton: UIButton!
    private var originalGestureRecognizers: [UIGestureRecognizer]?
    private var scrollView: UIScrollView?
    private var bottomBar: UIView!

    // Undo stack
    private var annotationStack: [PDFAnnotation] = []

    // Image insertion state
    private var availableImages: [UIImage] = []
    private var isImageMode = false
    private var selectedImageAnnotation: ImagePDFAnnotation?
    private var imageDragMode: ImageDragMode = .none
    private var imageDragStartPagePt: CGPoint = .zero
    private var imageDragOrigBounds: CGRect = .zero
    private var imageButton: UIButton?

    // Pinch-to-resize state
    private var pinchBaseWidth: CGFloat = 0
    private var pinchBaseHeight: CGFloat = 0
    private var pinchBaseCenter: CGPoint = .zero
    private var pinchAnnPage: PDFPage?

    // Image overlay for live display
    private var overlayView: ImageAnnotationOverlayView!
    private var scrollObservation: NSKeyValueObservation?

    // Hit-test radius in PDF page points for handles
    private let handleHitRadius: CGFloat = 22

    // Aspect ratio lock
    private var aspectRatioLocked = false

    // Remember last confirmed image position for next placement
    private var lastConfirmedImageRect: CGRect?

    // Image toolbar (shown when an image is selected)
    private var imageToolbar: UIView!
    private var imageToolbarStack: UIStackView!
    private var normalToolStack: UIStackView!
    private var aspectToggleButton: UIButton!

    private enum ImageDragMode { case none, move, tl, tr, bl, br, deleteHit, confirmHit }

    init(pdfURL: URL, saveURL: URL, config: PDFAnnotationConfig? = nil, completion: @escaping (String?) -> Void) {
        self.pdfURL = pdfURL
        self.saveURL = saveURL
        self.config = config
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyConfig()
        setupView()
        setupBottomBar()
        setupPDFView()
        setupToolbar()
        setupPanGesture()
        setupPinchGesture()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePDFPageChanged),
            name: .PDFViewPageChanged, object: pdfView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshOverlay),
            name: .PDFViewScaleChanged, object: pdfView
        )
    }

    deinit {
        scrollObservation = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handlePDFPageChanged() {
        disableTextSelectionGestures(in: pdfView)
        overlayView.setNeedsDisplay()
    }

    @objc private func refreshOverlay() {
        overlayView.setNeedsDisplay()
    }

    private func refreshImageOverlay() {
        overlayView.annotations = annotationStack.compactMap { $0 as? ImagePDFAnnotation }
        overlayView.selectedAnnotation = selectedImageAnnotation
        overlayView.aspectRatioLocked = aspectRatioLocked
        overlayView.setNeedsDisplay()

        // Show/hide image toolbar
        if selectedImageAnnotation != nil && imageToolbarStack.isHidden {
            showImageToolbar()
        } else if selectedImageAnnotation == nil && !imageToolbarStack.isHidden {
            hideImageToolbar()
        }
    }

    private func disableTextSelectionGestures(in view: UIView) {
        for gr in view.gestureRecognizers ?? [] {
            if gr is UILongPressGestureRecognizer { view.removeGestureRecognizer(gr) }
        }
        for subview in view.subviews { disableTextSelectionGestures(in: subview) }
    }

    private func applyConfig() {
        guard let cfg = config else { return }
        if let color = cfg.initialPenColor { penColor = color }
        if let color = cfg.initialHighlightColor { highlightColor = color }
        if let width = cfg.initialStrokeWidth { penThickness = width }
        cfg.imagePaths?.forEach { path in
            if let img = UIImage(contentsOfFile: path) { availableImages.append(img) }
        }
    }

    private func setupView() {
        view.backgroundColor = .systemBackground
        navigationItem.title = config?.title ?? "PDF Annotations"
    }

    // MARK: - Bottom bar

    private func setupBottomBar() {
        bottomBar = UIView()
        bottomBar.backgroundColor = .systemBackground
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(separator)

        // ── Normal annotation tools ─────────────────────────────────────────
        normalToolStack = UIStackView()
        normalToolStack.axis = .horizontal
        normalToolStack.distribution = .fillEqually
        normalToolStack.alignment = .center
        normalToolStack.spacing = 0
        normalToolStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(normalToolStack)

        drawingButton = makeSymbolButton(symbol: "pencil.slash", action: #selector(toggleDrawing))
        let highlightSymbol = (UIImage(systemName: "highlighter") != nil) ? "highlighter" : "rectangle.and.pencil.and.ellipsis"
        highlightButton = makeSymbolButton(symbol: highlightSymbol, action: #selector(toggleHighlight))
        eraserButton = makeSymbolButton(symbol: "eraser", action: #selector(toggleEraser))

        colorButton = UIButton(type: .custom)
        colorButton.addTarget(self, action: #selector(openColorPicker), for: .touchUpInside)

        sizeSButton = makeSizeButton(title: "S", action: #selector(sizeSmallTapped))
        sizeMButton = makeSizeButton(title: "M", action: #selector(sizeMediumTapped))
        sizeLButton = makeSizeButton(title: "L", action: #selector(sizeLargeTapped))

        let undoButton = makeSymbolButton(symbol: "arrow.uturn.backward", action: #selector(undoAnnotation))
        let trashButton = makeSymbolButton(symbol: "trash", action: #selector(clearAllAnnotations))

        if !availableImages.isEmpty {
            imageButton = makeSymbolButton(symbol: "photo", action: #selector(toggleImageMode))
        }

        var items: [UIView] = [
            wrapButton(drawingButton),
            wrapButton(highlightButton),
            wrapButton(eraserButton),
        ]
        if let imgBtn = imageButton { items.append(wrapButton(imgBtn)) }
        items += [
            wrapColorButton(colorButton),
            wrapSizeButton(sizeSButton),
            wrapSizeButton(sizeMButton),
            wrapSizeButton(sizeLButton),
            wrapButton(undoButton),
            wrapButton(trashButton),
        ]
        for item in items { normalToolStack.addArrangedSubview(item) }

        // ── Image editing toolbar (hidden by default) ───────────────────────
        imageToolbarStack = UIStackView()
        imageToolbarStack.axis = .vertical
        imageToolbarStack.alignment = .fill
        imageToolbarStack.spacing = 4
        imageToolbarStack.translatesAutoresizingMaskIntoConstraints = false
        imageToolbarStack.isHidden = true
        bottomBar.addSubview(imageToolbarStack)

        // Hint label
        let hintLabel = UILabel()
        hintLabel.text = "Drag to move · Corners to resize · Pinch to scale"
        hintLabel.font = UIFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        imageToolbarStack.addArrangedSubview(hintLabel)

        // Button row
        let imgBtnStack = UIStackView()
        imgBtnStack.axis = .horizontal
        imgBtnStack.distribution = .fillEqually
        imgBtnStack.spacing = 10

        // Aspect ratio toggle
        aspectToggleButton = UIButton(type: .system)
        aspectToggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        aspectToggleButton.layer.cornerRadius = 8
        aspectToggleButton.layer.borderWidth = 1.5
        aspectToggleButton.addTarget(self, action: #selector(toggleAspectRatio), for: .touchUpInside)
        updateAspectToggleUI()
        imgBtnStack.addArrangedSubview(aspectToggleButton)

        // Confirm button
        let confirmBtn = UIButton(type: .system)
        confirmBtn.setTitle("Confirm", for: .normal)
        confirmBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.backgroundColor = .systemGreen
        confirmBtn.layer.cornerRadius = 8
        confirmBtn.addTarget(self, action: #selector(confirmImageTapped), for: .touchUpInside)
        imgBtnStack.addArrangedSubview(confirmBtn)

        // Delete button
        let delBtn = UIButton(type: .system)
        delBtn.setTitle("Delete", for: .normal)
        delBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        delBtn.setTitleColor(.white, for: .normal)
        delBtn.backgroundColor = .systemRed
        delBtn.layer.cornerRadius = 8
        delBtn.addTarget(self, action: #selector(deleteImageTapped), for: .touchUpInside)
        imgBtnStack.addArrangedSubview(delBtn)

        imgBtnStack.translatesAutoresizingMaskIntoConstraints = false
        imgBtnStack.heightAnchor.constraint(equalToConstant: 36).isActive = true
        imageToolbarStack.addArrangedSubview(imgBtnStack)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            normalToolStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 2),
            normalToolStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -2),
            normalToolStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 6),
            normalToolStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),

            imageToolbarStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            imageToolbarStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            imageToolbarStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 6),
            imageToolbarStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -72),
        ])

        updateColorSwatch()
        let initialSizeBtn: UIButton
        switch penThickness {
        case ..<3.5: initialSizeBtn = sizeSButton
        case 14.0...: initialSizeBtn = sizeLButton
        default: initialSizeBtn = sizeMButton
        }
        updateSizeButtons(active: initialSizeBtn)
    }

    private func showImageToolbar() {
        UIView.animate(withDuration: 0.2) {
            self.normalToolStack.alpha = 0
        } completion: { _ in
            self.normalToolStack.isHidden = true
            self.imageToolbarStack.isHidden = false
            self.imageToolbarStack.alpha = 0
            UIView.animate(withDuration: 0.2) {
                self.imageToolbarStack.alpha = 1
            }
        }
    }

    private func hideImageToolbar() {
        UIView.animate(withDuration: 0.2) {
            self.imageToolbarStack.alpha = 0
        } completion: { _ in
            self.imageToolbarStack.isHidden = true
            self.normalToolStack.isHidden = false
            self.normalToolStack.alpha = 0
            UIView.animate(withDuration: 0.2) {
                self.normalToolStack.alpha = 1
            }
        }
    }

    @objc private func toggleAspectRatio() {
        aspectRatioLocked.toggle()
        overlayView.aspectRatioLocked = aspectRatioLocked
        updateAspectToggleUI()
        overlayView.setNeedsDisplay()
    }

    private func updateAspectToggleUI() {
        if aspectRatioLocked {
            aspectToggleButton.setTitle("Aspect: Locked", for: .normal)
            aspectToggleButton.setTitleColor(.systemBlue, for: .normal)
            aspectToggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            aspectToggleButton.layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            aspectToggleButton.setTitle("Aspect: Free", for: .normal)
            aspectToggleButton.setTitleColor(.systemOrange, for: .normal)
            aspectToggleButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.1)
            aspectToggleButton.layer.borderColor = UIColor.systemOrange.cgColor
        }
    }

    @objc private func confirmImageTapped() {
        // Save position for next image placement
        if let sel = selectedImageAnnotation {
            lastConfirmedImageRect = sel.bounds
        }
        selectedImageAnnotation = nil
        refreshImageOverlay()

        // Exit image mode entirely and release scroll lock
        isImageMode = false
        pdfView.gestureRecognizers = originalGestureRecognizers
        scrollView?.isScrollEnabled = true
        imageButton?.tintColor = .secondaryLabel
        hideImageToolbar()
    }

    @objc private func deleteImageTapped() {
        guard let sel = selectedImageAnnotation else { return }
        sel.page?.removeAnnotation(sel)
        annotationStack.removeAll { $0 === sel }
        selectedImageAnnotation = nil
        refreshImageOverlay()

        // Exit image mode entirely and release scroll lock
        isImageMode = false
        pdfView.gestureRecognizers = originalGestureRecognizers
        scrollView?.isScrollEnabled = true
        imageButton?.tintColor = .secondaryLabel
        hideImageToolbar()
    }

    private func makeSymbolButton(symbol: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: symbol), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func makeSizeButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        btn.tintColor = .systemTeal
        btn.layer.cornerRadius = 13
        btn.layer.borderWidth = 1.5
        btn.layer.borderColor = UIColor.systemTeal.cgColor
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 28),
            btn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return btn
    }

    private func wrapButton(_ button: UIButton) -> UIView {
        let stack = UIStackView(arrangedSubviews: [button])
        stack.axis = .vertical
        stack.alignment = .center
        return stack
    }

    private func wrapColorButton(_ button: UIButton) -> UIView {
        let stack = UIStackView(arrangedSubviews: [button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .equalCentering
        return stack
    }

    private func wrapSizeButton(_ button: UIButton) -> UIView {
        let stack = UIStackView(arrangedSubviews: [button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .equalCentering
        return stack
    }

    private func updateColorSwatch() {
        let c = isHighlightMode ? highlightColor : penColor
        let img = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { ctx in
            c.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 26, height: 26))
        }
        colorButton.setImage(img, for: .normal)
        colorButton.tintColor = .clear
    }

    private func updateSizeButtons(active: UIButton) {
        for btn in [sizeSButton!, sizeMButton!, sizeLButton!] {
            if btn == active {
                btn.backgroundColor = .systemTeal
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(.systemTeal, for: .normal)
            }
        }
    }

    @objc private func sizeSmallTapped()  { penThickness = 2.0;  updateSizeButtons(active: sizeSButton) }
    @objc private func sizeMediumTapped() { penThickness = 5.0;  updateSizeButtons(active: sizeMButton) }
    @objc private func sizeLargeTapped()  { penThickness = 10.0; updateSizeButtons(active: sizeLButton) }

    // MARK: - PDF View

    private func setupPDFView() {
        pdfView = PDFView(frame: view.bounds)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.isUserInteractionEnabled = true

        guard let document = PDFDocument(url: pdfURL) else { return }
        pdfView.document = document
        DispatchQueue.main.async { self.disableTextSelectionGestures(in: self.pdfView) }

        // Remove PDFKit's text-selection tap recognizer
        for recognizer in pdfView.gestureRecognizers ?? [] {
            if let tap = recognizer as? UITapGestureRecognizer,
               NSStringFromClass(type(of: tap)) == "UIPDFSelectionTapRecognizer" {
                pdfView.removeGestureRecognizer(tap)
            }
        }

        view.insertSubview(pdfView, belowSubview: bottomBar)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])

        // Transparent overlay for image annotation rendering
        overlayView = ImageAnnotationOverlayView()
        overlayView.pdfView = pdfView
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false
        pdfView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: pdfView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),
        ])

        // Refresh overlay on scroll
        if let sv = findScrollView(in: pdfView) {
            scrollObservation = sv.observe(\.contentOffset, options: .new) { [weak self] _, _ in
                self?.overlayView.setNeedsDisplay()
            }
        }
    }

    private func setupToolbar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(dismissViewController))
        let shareBtn = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
            target: self, action: #selector(sharePDF))
        let saveBtn = UIBarButtonItem(
            title: "Save", style: .done, target: self, action: #selector(savePDF))
        navigationItem.rightBarButtonItems = [saveBtn, shareBtn]
    }

    @objc private func sharePDF() {
        guard let document = pdfView.document,
              let pdfData = document.dataRepresentation() else { return }
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share_\(UUID().uuidString).pdf")
            try pdfData.write(to: tempURL)
            let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let pop = ac.popoverPresentationController {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            present(ac, animated: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        } catch { print("Share error: \(error)") }
    }

    private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = true
        panGesture.delaysTouchesEnded = true
        panGesture.maximumNumberOfTouches = 1  // single finger only; pinch handled separately
        pdfView.addGestureRecognizer(panGesture)
    }

    private func setupPinchGesture() {
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pdfView.addGestureRecognizer(pinchGesture)
    }

    // MARK: - Mode toggles

    @objc private func toggleDrawing() {
        if isEraserMode   { isEraserMode = false;   eraserButton.tintColor = .secondaryLabel }
        if isHighlightMode { isHighlightMode = false; highlightButton.tintColor = .secondaryLabel }

        isDrawingEnabled.toggle()
        if isDrawingEnabled {
            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { $0.isEnabled = false }
            scrollView = findScrollView(in: pdfView); scrollView?.isScrollEnabled = false
            panGesture.isEnabled = true
            pinchGesture.isEnabled = true
            drawingButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            drawingButton.tintColor = .systemBlue
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers
            scrollView?.isScrollEnabled = true
            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .secondaryLabel
        }
        updateColorSwatch()
    }

    @objc private func toggleEraser() {
        if isDrawingEnabled {
            isDrawingEnabled = false
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .secondaryLabel
        }
        if isHighlightMode { isHighlightMode = false; highlightButton.tintColor = .secondaryLabel }

        isEraserMode.toggle()
        if isEraserMode {
            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { $0.isEnabled = false }
            scrollView = findScrollView(in: pdfView); scrollView?.isScrollEnabled = false
            panGesture.isEnabled = true
            pinchGesture.isEnabled = true
            eraserButton.tintColor = .systemOrange
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            eraserButton.tintColor = .secondaryLabel
        }
    }

    @objc private func toggleHighlight() {
        if isDrawingEnabled {
            isDrawingEnabled = false
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .secondaryLabel
        }
        if isEraserMode { isEraserMode = false; eraserButton.tintColor = .secondaryLabel }

        isHighlightMode.toggle()
        if isHighlightMode {
            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { $0.isEnabled = false }
            scrollView = findScrollView(in: pdfView); scrollView?.isScrollEnabled = false
            panGesture.isEnabled = true
            pinchGesture.isEnabled = true
            highlightButton.tintColor = .systemYellow
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            highlightButton.tintColor = .secondaryLabel
        }
        updateColorSwatch()
    }

    @objc private func toggleImageMode() {
        isImageMode.toggle()

        if isImageMode {
            // Turn off other modes
            if isDrawingEnabled {
                isDrawingEnabled = false
                pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
                drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
                drawingButton.tintColor = .secondaryLabel
            }
            if isEraserMode   { isEraserMode = false;   eraserButton.tintColor = .secondaryLabel }
            if isHighlightMode { isHighlightMode = false; highlightButton.tintColor = .secondaryLabel }

            originalGestureRecognizers = pdfView.gestureRecognizers
            pdfView.gestureRecognizers?.forEach { $0.isEnabled = false }
            scrollView = findScrollView(in: pdfView); scrollView?.isScrollEnabled = false
            panGesture.isEnabled = true
            pinchGesture.isEnabled = true
            imageButton?.tintColor = .systemGreen

            // Auto-place: pick image then place it in the center of the current page
            if availableImages.count == 1 {
                placeImageInCenter(availableImages[0])
            } else {
                showImagePickerSheet()
            }
        } else {
            selectedImageAnnotation = nil
            pdfView.gestureRecognizers = originalGestureRecognizers
            scrollView?.isScrollEnabled = true
            imageButton?.tintColor = .secondaryLabel
            refreshImageOverlay()
        }
    }

    /// Places `image` at the last confirmed position (if any), otherwise in the center of the current page.
    private func placeImageInCenter(_ image: UIImage) {
        guard let page = pdfView.currentPage else { return }
        let bounds: CGRect
        if let lastRect = lastConfirmedImageRect {
            // Reuse last confirmed position and size
            bounds = lastRect
        } else {
            let pb = page.bounds(for: .mediaBox)
            let imgW = pb.width * 0.35
            let imgH = imgW * image.size.height / max(image.size.width, 1)
            bounds = CGRect(x: pb.midX - imgW / 2, y: pb.midY - imgH / 2,
                            width: imgW, height: imgH)
        }
        let ann = ImagePDFAnnotation(image: image, bounds: bounds)
        page.addAnnotation(ann)
        annotationStack.append(ann)
        selectedImageAnnotation = ann
        refreshImageOverlay()
    }

    private func showImagePickerSheet() {
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Select Image to Insert"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sheet.view.addSubview(titleLabel)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 90, height: 90)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let collectionView = ImagePickerCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.images = availableImages
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        // After dismissal, auto-place image in center of the current page
        collectionView.onImageSelected = { [weak self, weak sheet] image in
            sheet?.dismiss(animated: true) {
                self?.placeImageInCenter(image)
            }
        }
        sheet.view.addSubview(collectionView)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addAction(UIAction { [weak self, weak sheet] _ in
            self?.isImageMode = false
            self?.imageButton?.tintColor = .secondaryLabel
            sheet?.dismiss(animated: true) {
                self?.pdfView.gestureRecognizers = self?.originalGestureRecognizers
                self?.scrollView?.isScrollEnabled = true
            }
        }, for: .touchUpInside)
        sheet.view.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: sheet.view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: sheet.view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: sheet.view.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: sheet.view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: sheet.view.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 106),

            cancelBtn.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 12),
            cancelBtn.centerXAnchor.constraint(equalTo: sheet.view.centerXAnchor),
        ])

        if #available(iOS 15.0, *) {
            if let pc = sheet.sheetPresentationController {
                pc.detents = [.medium()]; pc.prefersGrabberVisible = true
            }
        } else {
            sheet.modalPresentationStyle = .pageSheet
        }
        present(sheet, animated: true)
    }

    @objc private func undoAnnotation() {
        guard let annotation = annotationStack.popLast() else { return }
        annotation.page?.removeAnnotation(annotation)
        if annotation === selectedImageAnnotation { selectedImageAnnotation = nil }
        pdfView.setNeedsDisplay()
        refreshImageOverlay()
    }

    @objc private func clearAllAnnotations() {
        let alert = UIAlertController(title: "Clear All?",
                                      message: "This will remove all annotations.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            for ann in self.annotationStack { ann.page?.removeAnnotation(ann) }
            self.annotationStack.removeAll()
            self.selectedImageAnnotation = nil
            self.pdfView.setNeedsDisplay()
            self.refreshImageOverlay()
        })
        present(alert, animated: true)
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        for sub in view.subviews {
            if let sv = sub as? UIScrollView { return sv }
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Pinch gesture for image resize

    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard isImageMode, let sel = selectedImageAnnotation, let page = sel.page else { return }

        switch gesture.state {
        case .began:
            pinchBaseWidth = sel.bounds.width
            pinchBaseHeight = sel.bounds.height
            pinchBaseCenter = CGPoint(x: sel.bounds.midX, y: sel.bounds.midY)
            pinchAnnPage = page

        case .changed:
            let scale = gesture.scale.clamped(to: 0.2...5.0)
            let newW = max(pinchBaseWidth * scale, 40)
            let newH: CGFloat
            if aspectRatioLocked {
                let aspect = pinchBaseWidth / max(pinchBaseHeight, 1)
                newH = newW / aspect
            } else {
                newH = max(pinchBaseHeight * scale, 40)
            }

            let nb = CGRect(x: pinchBaseCenter.x - newW / 2,
                            y: pinchBaseCenter.y - newH / 2,
                            width: newW, height: newH)

            let annPage = pinchAnnPage ?? page
            annPage.removeAnnotation(sel)
            sel.bounds = nb
            annPage.addAnnotation(sel)
            refreshImageOverlay()

        case .ended, .cancelled:
            pinchAnnPage = nil

        default:
            break
        }
    }

    // MARK: - Image gesture handling

    private func handleImageGesture(_ gesture: UIPanGestureRecognizer, page: PDFPage, pageLocation: CGPoint) {
        let r = handleHitRadius

        switch gesture.state {
        case .began:
            // Check selected image's handles
            if let sel = selectedImageAnnotation {
                let b = sel.bounds

                // Confirm: visual bottom-center → check via overlay view coordinates
                let location = gesture.location(in: pdfView)
                if let cfmCenter = overlayView.confirmButtonViewCenter() {
                    let cfmR = overlayView.confirmRadius + 8  // generous hit area
                    if hypot(location.x - cfmCenter.x, location.y - cfmCenter.y) <= cfmR {
                        imageDragMode = .confirmHit; return
                    }
                }

                // Delete: visual top-center → PDF (midX, maxY)
                let deletePt = CGPoint(x: b.midX, y: b.maxY)
                if imageDist(pageLocation, deletePt) <= r {
                    imageDragMode = .deleteHit; return
                }
                // Corner handles: TL, TR, BL, BR
                let cornerModes: [(CGPoint, ImageDragMode)] = [
                    (CGPoint(x: b.minX, y: b.maxY), .tl),
                    (CGPoint(x: b.maxX, y: b.maxY), .tr),
                    (CGPoint(x: b.minX, y: b.minY), .bl),
                    (CGPoint(x: b.maxX, y: b.minY), .br),
                ]
                for (pt, mode) in cornerModes {
                    if imageDist(pageLocation, pt) <= r {
                        imageDragMode = mode
                        imageDragStartPagePt = pageLocation
                        imageDragOrigBounds = b
                        return
                    }
                }
                // Body drag
                if b.contains(pageLocation) {
                    imageDragMode = .move
                    imageDragStartPagePt = pageLocation
                    imageDragOrigBounds = b
                    return
                }
                // Tapped outside — deselect
                selectedImageAnnotation = nil
                refreshImageOverlay()
            }

            // Hit-test all image annotations on this page
            for ann in page.annotations.reversed() {
                if let imgAnn = ann as? ImagePDFAnnotation, imgAnn.bounds.contains(pageLocation) {
                    selectedImageAnnotation = imgAnn
                    imageDragMode = .move
                    imageDragStartPagePt = pageLocation
                    imageDragOrigBounds = imgAnn.bounds
                    refreshImageOverlay()
                    return
                }
            }

        case .changed:
            guard imageDragMode != .none, imageDragMode != .deleteHit, imageDragMode != .confirmHit,
                  let sel = selectedImageAnnotation else { return }
            let dx = pageLocation.x - imageDragStartPagePt.x
            let dy = pageLocation.y - imageDragStartPagePt.y
            let orig = imageDragOrigBounds
            let minSz: CGFloat = 40

            var nb: CGRect
            switch imageDragMode {
            case .move:
                nb = orig.offsetBy(dx: dx, dy: dy)
            case .tl, .tr, .bl, .br:
                if aspectRatioLocked {
                    let aRight = (imageDragMode == .tl || imageDragMode == .bl)
                    let aBottom = (imageDragMode == .tl || imageDragMode == .tr)
                    nb = aspectLockedResize(orig: orig, dx: dx, dy: dy, anchorRight: aRight, anchorBottom: aBottom, minSize: minSz)
                } else {
                    nb = freeResize(orig: orig, dx: dx, dy: dy, minSize: minSz)
                }
            default:
                nb = orig
            }

            let annPage = sel.page ?? page
            annPage.removeAnnotation(sel)
            sel.bounds = nb
            annPage.addAnnotation(sel)
            refreshImageOverlay()

        case .ended:
            if imageDragMode == .deleteHit, let sel = selectedImageAnnotation {
                sel.page?.removeAnnotation(sel)
                annotationStack.removeAll { $0 === sel }
                selectedImageAnnotation = nil
                refreshImageOverlay()
            } else if imageDragMode == .confirmHit {
                // Save position for next image placement
                if let sel = selectedImageAnnotation {
                    lastConfirmedImageRect = sel.bounds
                }
                selectedImageAnnotation = nil
                refreshImageOverlay()
                // Exit image mode and release scroll lock
                isImageMode = false
                pdfView.gestureRecognizers = originalGestureRecognizers
                scrollView?.isScrollEnabled = true
                imageButton?.tintColor = .secondaryLabel
                hideImageToolbar()
            }
            imageDragMode = .none

        default:
            break
        }
    }

    /// Aspect-ratio-locked resize from a corner handle (PDF coordinate space: y-up).
    private func aspectLockedResize(orig: CGRect, dx: CGFloat, dy: CGFloat,
                                     anchorRight: Bool, anchorBottom: Bool,
                                     minSize: CGFloat) -> CGRect {
        let origW = orig.width
        let origH = orig.height
        guard origW > 1, origH > 1 else { return orig }
        let aspect = origW / origH

        // Project drag delta along the diagonal to get uniform scale
        let signX: CGFloat = anchorRight ? -1 : 1
        let signY: CGFloat = anchorBottom ? -1 : 1
        let projectedDelta = (signX * dx + signY * dy) / 2

        var newW = max(origW + projectedDelta * signX * 2, minSize)
        var newH = newW / aspect
        if newH < minSize {
            newH = minSize
            newW = newH * aspect
        }

        // Anchor the opposite corner
        let anchorX = anchorRight ? orig.maxX : orig.minX
        let anchorY = anchorBottom ? orig.minY : orig.maxY

        let newMinX = anchorRight ? anchorX - newW : anchorX
        let newMinY = anchorBottom ? anchorY : anchorY - newH

        return CGRect(x: newMinX, y: newMinY, width: newW, height: newH)
    }

    /// Free (non-aspect-locked) resize from the active corner.
    private func freeResize(orig: CGRect, dx: CGFloat, dy: CGFloat, minSize: CGFloat) -> CGRect {
        // PDF space: y-up. Visual TL=(minX,maxY), BR=(maxX,minY)
        switch imageDragMode {
        case .tl:
            let newMinX = min(orig.minX + dx, orig.maxX - minSize)
            let newMaxY = max(orig.maxY + dy, orig.minY + minSize)
            return CGRect(x: newMinX, y: orig.minY, width: orig.maxX - newMinX, height: newMaxY - orig.minY)
        case .tr:
            let newMaxX = max(orig.maxX + dx, orig.minX + minSize)
            let newMaxY = max(orig.maxY + dy, orig.minY + minSize)
            return CGRect(x: orig.minX, y: orig.minY, width: newMaxX - orig.minX, height: newMaxY - orig.minY)
        case .bl:
            let newMinX = min(orig.minX + dx, orig.maxX - minSize)
            let newMinY = min(orig.minY + dy, orig.maxY - minSize)
            return CGRect(x: newMinX, y: newMinY, width: orig.maxX - newMinX, height: orig.maxY - newMinY)
        case .br:
            let newMaxX = max(orig.maxX + dx, orig.minX + minSize)
            let newMinY = min(orig.minY + dy, orig.maxY - minSize)
            return CGRect(x: orig.minX, y: newMinY, width: newMaxX - orig.minX, height: orig.maxY - newMinY)
        default:
            return orig
        }
    }

    private func imageDist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Pan gesture dispatcher

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let page = pdfView.currentPage else { return }
        let location = gesture.location(in: pdfView)
        let pageLocation = pdfView.convert(location, to: page)

        if isImageMode {
            handleImageGesture(gesture, page: page, pageLocation: pageLocation)
            return
        }

        guard isDrawingEnabled || isEraserMode || isHighlightMode else { return }

        if isHighlightMode {
            switch gesture.state {
            case .began:
                highlightStartPoint = pageLocation
            case .ended:
                guard let start = highlightStartPoint else { return }
                let rect = CGRect(
                    x: min(start.x, pageLocation.x), y: min(start.y, pageLocation.y),
                    width: abs(pageLocation.x - start.x), height: abs(pageLocation.y - start.y))
                if let sel = page.selection(for: rect) {
                    for line in sel.selectionsByLine() {
                        guard let p = line.pages.first else { continue }
                        let ann = PDFAnnotation(bounds: line.bounds(for: p), forType: .highlight, withProperties: nil)
                        ann.color = highlightColor; p.addAnnotation(ann); annotationStack.append(ann)
                    }
                } else {
                    let ann = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                    ann.color = highlightColor; page.addAnnotation(ann); annotationStack.append(ann)
                }
                highlightStartPoint = nil; pdfView.setNeedsDisplay()
            default: break
            }
            return
        }

        if isEraserMode {
            if gesture.state == .began || gesture.state == .changed {
                let eraserRect = CGRect(x: pageLocation.x - 10, y: pageLocation.y - 10, width: 20, height: 20)
                annotationStack.removeAll { ann in
                    guard ann.bounds.intersects(eraserRect) else { return false }
                    ann.page?.removeAnnotation(ann); return true
                }
                pdfView.setNeedsDisplay()
            }
            return
        }

        // Drawing mode
        switch gesture.state {
        case .began:
            if let existing = currentAnnotation { page.removeAnnotation(existing) }
            currentPath = UIBezierPath()
            currentPath?.move(to: pageLocation)
            currentAnnotation = PDFAnnotation(bounds: page.bounds(for: .mediaBox), forType: .ink, withProperties: nil)
            currentAnnotation?.color = penColor
            let border = PDFBorder(); border.lineWidth = penThickness
            currentAnnotation?.border = border
            gesture.cancelsTouchesInView = true

        case .changed:
            guard let path = currentPath, let annotation = currentAnnotation else { return }
            path.addLine(to: pageLocation)
            annotation.add(path)
            page.removeAnnotation(annotation); page.addAnnotation(annotation)
            pdfView.setNeedsDisplay()

        case .ended:
            guard let annotation = currentAnnotation else { return }
            annotationStack.append(annotation)
            currentAnnotation = nil; currentPath = nil

        default: break
        }
    }

    @objc private func openColorPicker() {
        let picker = UIColorPickerViewController()
        picker.selectedColor = isHighlightMode ? highlightColor : penColor
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Save

    @objc private func savePDF() {
        guard let document = pdfView.document else {
            completion(nil); dismiss(animated: true); return
        }

        // Show saving indicator
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = overlay.center
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        spinner.startAnimating()
        overlay.addSubview(spinner)
        let savingLabel = UILabel()
        savingLabel.text = "Saving..."
        savingLabel.textColor = .label
        savingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        savingLabel.sizeToFit()
        savingLabel.center = CGPoint(x: overlay.center.x, y: overlay.center.y + 40)
        savingLabel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        overlay.addSubview(savingLabel)
        view.addSubview(overlay)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                guard let pdfData = document.dataRepresentation(),
                      let newDocument = PDFDocument(data: pdfData) else {
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        self.completion(nil)
                    }
                    return
                }

                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }

                    let pageBounds = page.bounds(for: .mediaBox)
                    let flatData = NSMutableData()
                    UIGraphicsBeginPDFContextToData(flatData, pageBounds, nil)
                    UIGraphicsBeginPDFPage()

                    if let context = UIGraphicsGetCurrentContext() {
                        // Flip to screen space so page.draw() renders correctly
                        context.translateBy(x: 0, y: pageBounds.height)
                        context.scaleBy(x: 1, y: -1)

                        // Temporarily remove ImagePDFAnnotations before page.draw()
                        let imageAnns = page.annotations.compactMap { $0 as? ImagePDFAnnotation }
                        imageAnns.forEach { page.removeAnnotation($0) }

                        page.draw(with: .mediaBox, to: context)

                        // Restore image annotations
                        imageAnns.forEach { page.addAnnotation($0) }

                        // Draw non-image annotations manually
                        for annotation in page.annotations where !(annotation is ImagePDFAnnotation) {
                            context.saveGState()
                            if annotation.type == PDFAnnotationSubtype.highlight.rawValue {
                                context.setFillColor(annotation.color.cgColor)
                                context.fill(annotation.bounds)
                            } else {
                                context.setStrokeColor(annotation.color.cgColor)
                                context.setLineWidth(annotation.border?.lineWidth ?? 2)
                                if let paths = annotation.paths {
                                    for path in paths {
                                        (path as? UIBezierPath)?.stroke()
                                    }
                                }
                            }
                            context.restoreGState()
                        }

                        // Draw image annotations — correct orientation, no handles.
                        for imgAnn in imageAnns {
                            let b = imgAnn.bounds
                            context.saveGState()
                            context.translateBy(x: b.minX, y: b.maxY)
                            context.scaleBy(x: 1, y: -1)
                            imgAnn.image.draw(in: CGRect(origin: .zero, size: b.size))
                            context.restoreGState()
                        }
                    }

                    UIGraphicsEndPDFContext()

                    if let newPageDoc = PDFDocument(data: flatData as Data),
                       let flattenedPage = newPageDoc.page(at: 0) {
                        newDocument.removePage(at: pageIndex)
                        newDocument.insert(flattenedPage, at: pageIndex)
                    }
                }

                if let finalData = newDocument.dataRepresentation() {
                    try finalData.write(to: self.saveURL)
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        self.dismiss(animated: true) { self.completion(self.saveURL.path) }
                    }
                } else {
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        self.completion(nil)
                    }
                }
            } catch {
                print("Save error: \(error)")
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.dismiss(animated: true) { self.completion(nil) }
                }
            }
        }
    }

    @objc private func dismissViewController() {
        dismiss(animated: true) { self.completion(nil) }
    }

    // MARK: - UIColorPickerViewControllerDelegate

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        applyPickedColor(viewController.selectedColor)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        applyPickedColor(viewController.selectedColor)
    }

    private func applyPickedColor(_ color: UIColor) {
        if isHighlightMode { highlightColor = color.withAlphaComponent(0.5) }
        else { penColor = color }
        updateColorSwatch()
    }
}

// MARK: - Comparable clamped helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - ImagePickerCollectionView

private class ImagePickerCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate {
    var images: [UIImage] = []
    var onImageSelected: ((UIImage) -> Void)?

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        dataSource = self; delegate = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        showsHorizontalScrollIndicator = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { images.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let iv = UIImageView(image: images[indexPath.item])
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.frame = cell.contentView.bounds
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cell.contentView.addSubview(iv)
        cell.layer.cornerRadius = 8
        cell.backgroundColor = .secondarySystemBackground
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onImageSelected?(images[indexPath.item])
    }
}
