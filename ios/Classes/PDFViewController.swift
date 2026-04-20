import UIKit
import PDFKit

struct PDFAnnotationConfig {
    let title: String?
    let initialPenColor: UIColor?
    let initialHighlightColor: UIColor?
    let initialStrokeWidth: CGFloat?
    let imagePaths: [String]?
    let initialPage: Int
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
            let infoText = (aspectRatioLocked ? FPAStrings.current.aspectLockedShort : FPAStrings.current.aspectFreeShort) as NSString
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
    private var highlightPreviewView: UIView!
    private var currentPath: UIBezierPath?
    private var currentAnnotation: PDFAnnotation?
    private var panGesture: UIPanGestureRecognizer!
    private var drawingButton: UIButton!
    private var eraserButton: UIButton!
    private var highlightButton: UIButton!
    private var colorButton: UIButton!
    private var sizeSegmentedControl: UISegmentedControl!
    private var originalGestureRecognizers: [UIGestureRecognizer]?
    private var scrollView: UIScrollView?
    private var bottomBar: UIView!
    private var optionsPanel: UIView!
    private var optionsPanelStack: UIStackView!
    private var bottomBarTopConstraint: NSLayoutConstraint!

    // Undo stack
    private var annotationStack: [PDFAnnotation] = []

    // Image insertion state
    private var availableImages: [UIImage] = []
    private var imageButton: UIButton?

    // Image overlay for display-only rendering
    private var overlayView: ImageAnnotationOverlayView!
    private var scrollObservation: NSKeyValueObservation?

    private var normalToolStack: UIStackView!

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
        overlayView.selectedAnnotation = nil
        overlayView.setNeedsDisplay()
    }

    private func disableTextSelectionGestures(in view: UIView) {
        for gr in view.gestureRecognizers ?? [] {
            let className = NSStringFromClass(type(of: gr))
            // Remove long-press (text selection trigger) and any PDFKit selection recognizers
            if gr is UILongPressGestureRecognizer || className.contains("Selection") {
                view.removeGestureRecognizer(gr)
            }
        }
        for subview in view.subviews { disableTextSelectionGestures(in: subview) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // PDFKit can re-add selection gesture recognizers after layout changes
        disableTextSelectionGestures(in: pdfView)
    }

    private func applyConfig() {
        guard let cfg = config else { return }
        if let color = cfg.initialPenColor { penColor = color }
        if let color = cfg.initialHighlightColor { highlightColor = color }
        if let width = cfg.initialStrokeWidth { penThickness = width }
        cfg.imagePaths?.forEach { path in
            if let img = UIImage(contentsOfFile: path) {
                availableImages.append(downscaleIfNeeded(img))
            }
        }
    }

    /// Downscale an image if its longest edge exceeds `maxDimension` to prevent UI lag.
    private func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func setupView() {
        view.backgroundColor = .systemBackground
        navigationItem.title = config?.title ?? FPAStrings.current.defaultTitle
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

        // ── Options panel (color + size, shown when Draw/Highlight active) ──
        optionsPanel = UIView()
        optionsPanel.translatesAutoresizingMaskIntoConstraints = false
        optionsPanel.isHidden = true
        optionsPanel.alpha = 0
        bottomBar.addSubview(optionsPanel)

        let optionsSeparator = UIView()
        optionsSeparator.backgroundColor = .separator
        optionsSeparator.translatesAutoresizingMaskIntoConstraints = false
        optionsPanel.addSubview(optionsSeparator)

        optionsPanelStack = UIStackView()
        optionsPanelStack.axis = .horizontal
        optionsPanelStack.alignment = .center
        optionsPanelStack.spacing = 16
        optionsPanelStack.translatesAutoresizingMaskIntoConstraints = false
        optionsPanel.addSubview(optionsPanelStack)

        // Color swatch (enlarged 36pt)
        colorButton = UIButton(type: .custom)
        colorButton.addTarget(self, action: #selector(openColorPicker), for: .touchUpInside)
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorButton.widthAnchor.constraint(equalToConstant: 36),
            colorButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        optionsPanelStack.addArrangedSubview(colorButton)

        // Size segmented control (replaces S/M/L buttons)
        sizeSegmentedControl = UISegmentedControl(items: ["S", "M", "L"])
        sizeSegmentedControl.selectedSegmentTintColor = .systemTeal
        sizeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.systemTeal], for: .normal)
        sizeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        switch penThickness {
        case ..<3.5: sizeSegmentedControl.selectedSegmentIndex = 0
        case 14.0...: sizeSegmentedControl.selectedSegmentIndex = 2
        default: sizeSegmentedControl.selectedSegmentIndex = 1
        }
        sizeSegmentedControl.addTarget(self, action: #selector(sizeSegmentChanged(_:)), for: .valueChanged)
        sizeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        sizeSegmentedControl.heightAnchor.constraint(equalToConstant: 32).isActive = true
        optionsPanelStack.addArrangedSubview(sizeSegmentedControl)

        NSLayoutConstraint.activate([
            optionsPanelStack.leadingAnchor.constraint(equalTo: optionsPanel.leadingAnchor, constant: 16),
            optionsPanelStack.trailingAnchor.constraint(equalTo: optionsPanel.trailingAnchor, constant: -16),
            optionsPanelStack.topAnchor.constraint(equalTo: optionsPanel.topAnchor, constant: 6),
            optionsPanelStack.bottomAnchor.constraint(equalTo: optionsPanel.bottomAnchor, constant: -6),

            optionsSeparator.leadingAnchor.constraint(equalTo: optionsPanel.leadingAnchor),
            optionsSeparator.trailingAnchor.constraint(equalTo: optionsPanel.trailingAnchor),
            optionsSeparator.bottomAnchor.constraint(equalTo: optionsPanel.bottomAnchor),
            optionsSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // ── Primary tool row ────────────────────────────────────────────────
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

        let undoButton = makeSymbolButton(symbol: "arrow.uturn.backward", action: #selector(undoAnnotation))
        let trashButton = makeSymbolButton(symbol: "trash", action: #selector(clearAllAnnotations))

        if !availableImages.isEmpty {
            imageButton = makeSymbolButton(symbol: "photo", action: #selector(toggleImageMode))
        }

        // Tools group
        var items: [UIView] = [
            wrapButton(drawingButton),
            wrapButton(highlightButton),
            wrapButton(eraserButton),
        ]
        if let imgBtn = imageButton { items.append(wrapButton(imgBtn)) }

        // Actions group
        items.append(wrapButton(undoButton))
        items.append(wrapButton(trashButton))

        for item in items { normalToolStack.addArrangedSubview(item) }

        // ── Layout constraints ──────────────────────────────────────────────
        bottomBarTopConstraint = bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            optionsPanel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            optionsPanel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            optionsPanel.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            optionsPanel.heightAnchor.constraint(equalToConstant: 44),

            normalToolStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 4),
            normalToolStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -4),
            normalToolStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            normalToolStack.heightAnchor.constraint(equalToConstant: 44),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBarTopConstraint,
        ])

        updateColorSwatch()
    }

    // MARK: - Options panel show/hide

    private func showOptionsPanel() {
        guard optionsPanel.isHidden else { return }
        optionsPanel.isHidden = false
        bottomBarTopConstraint.constant = -100 // expanded: options panel + tool row
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.optionsPanel.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private func hideOptionsPanel() {
        guard !optionsPanel.isHidden else { return }
        bottomBarTopConstraint.constant = -56 // collapsed: tool row only
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.optionsPanel.alpha = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.optionsPanel.isHidden = true
        }
    }

    @objc private func sizeSegmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: penThickness = 2.0
        case 1: penThickness = 5.0
        case 2: penThickness = 10.0
        default: break
        }
    }



    private func makeSymbolButton(symbol: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: symbol), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func wrapButton(_ button: UIButton) -> UIView {
        let stack = UIStackView(arrangedSubviews: [button])
        stack.axis = .vertical
        stack.alignment = .center
        return stack
    }

    private func updateColorSwatch() {
        let c = isHighlightMode ? highlightColor : penColor
        let size: CGFloat = 36
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            c.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.separator.setStroke()
            ctx.cgContext.setLineWidth(1.5)
            ctx.cgContext.strokeEllipse(in: CGRect(x: 0.75, y: 0.75, width: size - 1.5, height: size - 1.5))
        }
        colorButton.setImage(img, for: .normal)
        colorButton.tintColor = .clear
    }

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

        // Navigate to initial page if specified
        if let cfg = config, cfg.initialPage > 0,
           cfg.initialPage < document.pageCount,
           let targetPage = document.page(at: cfg.initialPage) {
            pdfView.go(to: targetPage)
        }

        // Aggressively disable all text selection mechanisms
        disableTextSelectionGestures(in: pdfView)
        DispatchQueue.main.async { self.disableTextSelectionGestures(in: self.pdfView) }

        // Remove PDFKit's text-selection tap and selection-related recognizers
        for recognizer in pdfView.gestureRecognizers ?? [] {
            let className = NSStringFromClass(type(of: recognizer))
            if className.contains("Selection") || className.contains("Tap") {
                pdfView.removeGestureRecognizer(recognizer)
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

        // Highlight preview overlay (shown during drag)
        highlightPreviewView = UIView()
        highlightPreviewView.isUserInteractionEnabled = false
        highlightPreviewView.isHidden = true
        highlightPreviewView.layer.cornerRadius = 2
        highlightPreviewView.layer.borderWidth = 1.5
        pdfView.addSubview(highlightPreviewView)

        // Refresh overlay on scroll
        if let sv = findScrollView(in: pdfView) {
            scrollObservation = sv.observe(\.contentOffset, options: .new) { [weak self] _, _ in
                self?.overlayView.setNeedsDisplay()
            }
        }
    }

    private func setupToolbar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: FPAStrings.current.cancel, style: .plain, target: self, action: #selector(dismissViewController))
        let shareBtn = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
            target: self, action: #selector(sharePDF))
        let saveBtn = UIBarButtonItem(
            title: FPAStrings.current.save, style: .done, target: self, action: #selector(savePDF))
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
            drawingButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            drawingButton.tintColor = .systemBlue
            showOptionsPanel()
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers
            scrollView?.isScrollEnabled = true
            drawingButton.setImage(UIImage(systemName: "pencil.slash"), for: .normal)
            drawingButton.tintColor = .secondaryLabel
            hideOptionsPanel()
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
            eraserButton.tintColor = .systemOrange
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            eraserButton.tintColor = .secondaryLabel
        }
        hideOptionsPanel()
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
            highlightButton.tintColor = .systemYellow
            showOptionsPanel()
        } else {
            pdfView.gestureRecognizers = originalGestureRecognizers; scrollView?.isScrollEnabled = true
            highlightButton.tintColor = .secondaryLabel
            hideOptionsPanel()
        }
        updateColorSwatch()
    }

    @objc private func toggleImageMode() {
        guard let document = pdfView.document else { return }

        let currentIdx = pdfView.currentPage.flatMap { document.index(for: $0) } ?? 0
        let vc = ImagePlacementViewController(
            document: document,
            images: availableImages,
            initialPage: currentIdx
        ) { [weak self] placements in
            self?.applyImagePlacements(placements)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func applyImagePlacements(_ placements: [ImagePlacement]) {
        guard let document = pdfView.document else { return }
        for p in placements {
            guard p.pageIndex < document.pageCount,
                  let page = document.page(at: p.pageIndex) else { continue }
            let ann = ImagePDFAnnotation(image: p.image, bounds: p.bounds)
            page.addAnnotation(ann)
            annotationStack.append(ann)
        }
        pdfView.setNeedsDisplay()
        refreshImageOverlay()
    }

    @objc private func undoAnnotation() {
        guard let annotation = annotationStack.popLast() else { return }
        annotation.page?.removeAnnotation(annotation)
        pdfView.setNeedsDisplay()
        refreshImageOverlay()
    }

    @objc private func clearAllAnnotations() {
        let s = FPAStrings.current
        let alert = UIAlertController(title: s.clearAllTitle,
                                      message: s.clearAllMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: s.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: s.clear, style: .destructive) { [weak self] _ in
            guard let self else { return }
            for ann in self.annotationStack { ann.page?.removeAnnotation(ann) }
            self.annotationStack.removeAll()
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

    // MARK: - Pan gesture dispatcher

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return }
        let pageLocation = pdfView.convert(location, to: page)

        guard isDrawingEnabled || isEraserMode || isHighlightMode else { return }

        if isHighlightMode {
            switch gesture.state {
            case .began:
                highlightStartPoint = pageLocation
            case .changed:
                guard let start = highlightStartPoint else { return }
                let startView = pdfView.convert(start, from: page)
                let currentView = gesture.location(in: pdfView)
                let previewRect = CGRect(
                    x: min(startView.x, currentView.x),
                    y: min(startView.y, currentView.y),
                    width: abs(currentView.x - startView.x),
                    height: abs(currentView.y - startView.y))
                highlightPreviewView.frame = previewRect
                highlightPreviewView.backgroundColor = highlightColor
                highlightPreviewView.layer.borderColor = highlightColor.withAlphaComponent(0.8).cgColor
                highlightPreviewView.isHidden = false
            case .ended:
                highlightPreviewView.isHidden = true
                guard let start = highlightStartPoint else { return }
                let rect = CGRect(
                    x: min(start.x, pageLocation.x), y: min(start.y, pageLocation.y),
                    width: abs(pageLocation.x - start.x), height: abs(pageLocation.y - start.y))
                if rect.width > 2 && rect.height > 2 {
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
                }
                highlightStartPoint = nil; pdfView.setNeedsDisplay()
            case .cancelled:
                highlightPreviewView.isHidden = true
                highlightStartPoint = nil
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
        savingLabel.text = FPAStrings.current.saving
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



