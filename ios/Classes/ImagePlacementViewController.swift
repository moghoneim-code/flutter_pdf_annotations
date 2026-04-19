import UIKit
import PDFKit

/// Data returned from the image placement screen.
struct ImagePlacement {
    let pageIndex: Int
    let image: UIImage
    let bounds: CGRect  // in PDF page coordinates
}

// MARK: - ImagePlacementViewController

class ImagePlacementViewController: UIViewController {

    // Inputs
    private let document: PDFDocument
    private let images: [UIImage]
    private var currentPageIndex: Int
    private let completion: ([ImagePlacement]) -> Void

    // State
    private var placements: [ImagePlacement] = []
    private var currentImage: UIImage?
    private var currentImageRect: CGRect = .zero  // in PDF coords
    private var aspectRatioLocked = false

    // Drag state
    private enum DragMode { case none, move, tl, tr, bl, br }
    private var dragMode: DragMode = .none
    private var dragStartPdf: CGPoint = .zero
    private var dragOrigRect: CGRect = .zero

    // Pinch state
    private var pinchBaseWidth: CGFloat = 0
    private var pinchBaseHeight: CGFloat = 0
    private var pinchBaseCenter: CGPoint = .zero

    // Layout constants
    private let handleRadius: CGFloat = 13
    private let minImageSize: CGFloat = 40
    private let handleHitRadius: CGFloat = 30

    // Views
    private var pageImageView: UIImageView!
    private var overlayView: ImagePlacementOverlayView!
    private var pageLabel: UILabel!
    private var imagePickerStack: UIStackView!
    private var actionRow: UIStackView!
    private var aspectToggleButton: UIButton!
    private var confirmButton: UIButton!
    private var deleteButton: UIButton!

    // Page render scale (view points per PDF point)
    private var renderScale: CGFloat = 1.0
    private var renderOrigin: CGPoint = .zero  // offset of rendered page in imageView
    private var currentPageBounds: CGRect = .zero

    init(document: PDFDocument, images: [UIImage], initialPage: Int, completion: @escaping ([ImagePlacement]) -> Void) {
        self.document = document
        self.images = images
        self.currentPageIndex = min(max(initialPage, 0), max(document.pageCount - 1, 0))
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        setupTopBar()
        setupPageView()
        setupBottomBar()
        renderCurrentPage()
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Back", style: .plain, target: self, action: #selector(backTapped))

        let prevBtn = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(prevPage))
        pageLabel = UILabel()
        pageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        pageLabel.textAlignment = .center
        let pageLabelItem = UIBarButtonItem(customView: pageLabel)
        let nextBtn = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(nextPage))
        let doneBtn = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))

        navigationItem.rightBarButtonItems = [doneBtn, nextBtn, pageLabelItem, prevBtn]
    }

    // MARK: - Page View

    private func setupPageView() {
        pageImageView = UIImageView()
        pageImageView.contentMode = .scaleAspectFit
        pageImageView.backgroundColor = .white
        pageImageView.translatesAutoresizingMaskIntoConstraints = false
        pageImageView.isUserInteractionEnabled = true
        view.addSubview(pageImageView)

        overlayView = ImagePlacementOverlayView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = true
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        // Pan gesture for drag
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        overlayView.addGestureRecognizer(pan)

        // Pinch gesture for resize
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        overlayView.addGestureRecognizer(pinch)

        // Tap for confirm/delete buttons
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        overlayView.addGestureRecognizer(tap)
    }

    // MARK: - Bottom Bar

    private func setupBottomBar() {
        let bottomBar = UIView()
        bottomBar.backgroundColor = .systemBackground
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(separator)

        // Image picker: horizontal scroll of thumbnails
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(scrollView)

        imagePickerStack = UIStackView()
        imagePickerStack.axis = .horizontal
        imagePickerStack.spacing = 12
        imagePickerStack.alignment = .center
        imagePickerStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imagePickerStack)

        for (idx, img) in images.enumerated() {
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = 8
            iv.backgroundColor = .secondarySystemBackground
            iv.isUserInteractionEnabled = true
            iv.tag = idx
            iv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iv.widthAnchor.constraint(equalToConstant: 64),
                iv.heightAnchor.constraint(equalToConstant: 64),
            ])
            let tapGR = UITapGestureRecognizer(target: self, action: #selector(imageThumbnailTapped(_:)))
            iv.addGestureRecognizer(tapGR)
            imagePickerStack.addArrangedSubview(iv)
        }

        // Action row (shown when image placed)
        actionRow = UIStackView()
        actionRow.axis = .horizontal
        actionRow.distribution = .fillEqually
        actionRow.spacing = 10
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.isHidden = true
        bottomBar.addSubview(actionRow)

        aspectToggleButton = UIButton(type: .system)
        aspectToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        aspectToggleButton.layer.cornerRadius = 8
        aspectToggleButton.layer.borderWidth = 1.5
        aspectToggleButton.addTarget(self, action: #selector(toggleAspectRatio), for: .touchUpInside)
        actionRow.addArrangedSubview(aspectToggleButton)
        updateAspectToggleUI()

        confirmButton = UIButton(type: .system)
        confirmButton.setTitle("Confirm", for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = .systemGreen
        confirmButton.layer.cornerRadius = 8
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        actionRow.addArrangedSubview(confirmButton)

        deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = .systemRed
        deleteButton.layer.cornerRadius = 8
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        actionRow.addArrangedSubview(deleteButton)

        // Layout
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            scrollView.heightAnchor.constraint(equalToConstant: 68),

            imagePickerStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imagePickerStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imagePickerStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imagePickerStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imagePickerStack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            actionRow.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            actionRow.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            actionRow.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            actionRow.heightAnchor.constraint(equalToConstant: 36),
            actionRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            pageImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            pageImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            pageImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            pageImageView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            overlayView.topAnchor.constraint(equalTo: pageImageView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: pageImageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: pageImageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: pageImageView.bottomAnchor),
        ])
    }

    // MARK: - Page Rendering

    private func renderCurrentPage() {
        guard currentPageIndex >= 0, currentPageIndex < document.pageCount,
              let page = document.page(at: currentPageIndex) else { return }

        pageLabel.text = "Page \(currentPageIndex + 1)/\(document.pageCount)"

        let pageBounds = page.bounds(for: .mediaBox)
        currentPageBounds = pageBounds

        // Render at screen scale for sharp output
        let screenScale = UIScreen.main.scale
        let maxW = (view.bounds.width - 16) * screenScale
        let maxH = (view.bounds.height - 200) * screenScale  // leave room for bars
        let scaleW = maxW / pageBounds.width
        let scaleH = maxH / pageBounds.height
        let scale = min(scaleW, scaleH)

        let renderWidth = pageBounds.width * scale
        let renderHeight = pageBounds.height * scale

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderWidth, height: renderHeight))
        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))

            // Draw the PDF page (requires flipped coordinates)
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: renderHeight)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()

            // Draw already-confirmed placements for this page in standard UIKit coords
            for p in placements where p.pageIndex == currentPageIndex {
                let imgRect = CGRect(
                    x: p.bounds.origin.x * scale,
                    y: (pageBounds.height - p.bounds.origin.y - p.bounds.height) * scale,
                    width: p.bounds.width * scale,
                    height: p.bounds.height * scale
                )
                p.image.draw(in: imgRect)
            }
        }

        pageImageView.image = image

        // Calculate render scale: how imageView displays the image
        // This gets updated after layout
        DispatchQueue.main.async { [weak self] in
            self?.updateRenderTransform()
            self?.overlayView.setNeedsDisplay()
        }
    }

    private func updateRenderTransform() {
        guard let image = pageImageView.image else { return }
        let ivSize = pageImageView.bounds.size
        guard ivSize.width > 0, ivSize.height > 0 else { return }

        let imgSize = image.size
        let scaleW = ivSize.width / imgSize.width
        let scaleH = ivSize.height / imgSize.height
        let fitScale = min(scaleW, scaleH)

        let displayW = imgSize.width * fitScale
        let displayH = imgSize.height * fitScale
        renderOrigin = CGPoint(
            x: (ivSize.width - displayW) / 2,
            y: (ivSize.height - displayH) / 2
        )

        // renderScale: view points per PDF point
        renderScale = displayW / currentPageBounds.width
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateRenderTransform()
        overlayView.setNeedsDisplay()
    }

    // MARK: - Coordinate Conversion

    /// Convert PDF page coordinates to view coordinates
    private func pdfToView(_ pdfPoint: CGPoint) -> CGPoint {
        // PDF: origin bottom-left, y-up. View: origin top-left, y-down.
        let viewX = renderOrigin.x + pdfPoint.x * renderScale
        let viewY = renderOrigin.y + (currentPageBounds.height - pdfPoint.y) * renderScale
        return CGPoint(x: viewX, y: viewY)
    }

    /// Convert view coordinates to PDF page coordinates
    private func viewToPdf(_ viewPoint: CGPoint) -> CGPoint {
        let pdfX = (viewPoint.x - renderOrigin.x) / renderScale
        let pdfY = currentPageBounds.height - (viewPoint.y - renderOrigin.y) / renderScale
        return CGPoint(x: pdfX, y: pdfY)
    }

    /// Convert PDF rect to view rect
    private func pdfRectToView(_ pdfRect: CGRect) -> CGRect {
        let topLeft = pdfToView(CGPoint(x: pdfRect.minX, y: pdfRect.maxY))
        let bottomRight = pdfToView(CGPoint(x: pdfRect.maxX, y: pdfRect.minY))
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: bottomRight.x - topLeft.x,
                      height: bottomRight.y - topLeft.y)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        // Warn if there's an unconfirmed image
        if currentImage != nil {
            let alert = UIAlertController(title: "Discard Image?", message: "You have an unconfirmed image placement.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.currentImage = nil
                self?.dismiss(animated: true) { self?.completion(self?.placements ?? []) }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        } else {
            dismiss(animated: true) { [weak self] in self?.completion(self?.placements ?? []) }
        }
    }

    @objc private func doneTapped() {
        // Auto-confirm current image if any
        if currentImage != nil { confirmCurrentImage() }
        dismiss(animated: true) { [weak self] in self?.completion(self?.placements ?? []) }
    }

    @objc private func prevPage() {
        guard currentPageIndex > 0 else { return }
        if currentImage != nil { confirmCurrentImage() }
        currentPageIndex -= 1
        currentImage = nil
        actionRow.isHidden = true
        renderCurrentPage()
    }

    @objc private func nextPage() {
        guard currentPageIndex < document.pageCount - 1 else { return }
        if currentImage != nil { confirmCurrentImage() }
        currentPageIndex += 1
        currentImage = nil
        actionRow.isHidden = true
        renderCurrentPage()
    }

    @objc private func imageThumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let iv = gesture.view else { return }
        let idx = iv.tag
        guard idx >= 0, idx < images.count else { return }

        let image = images[idx]
        currentImage = image

        // Place at center of page
        let pb = currentPageBounds
        let imgW = pb.width * 0.35
        let imgH = imgW * image.size.height / max(image.size.width, 1)
        currentImageRect = CGRect(x: pb.midX - imgW / 2, y: pb.midY - imgH / 2, width: imgW, height: imgH)

        actionRow.isHidden = false
        overlayView.setNeedsDisplay()
    }

    @objc private func confirmTapped() {
        confirmCurrentImage()
    }

    private func confirmCurrentImage() {
        guard let img = currentImage else { return }
        placements.append(ImagePlacement(pageIndex: currentPageIndex, image: img, bounds: currentImageRect))
        currentImage = nil
        actionRow.isHidden = true
        renderCurrentPage()  // re-render to show the confirmed image baked into the page
    }

    @objc private func deleteTapped() {
        currentImage = nil
        actionRow.isHidden = true
        overlayView.setNeedsDisplay()
    }

    @objc private func toggleAspectRatio() {
        aspectRatioLocked.toggle()
        updateAspectToggleUI()
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

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard currentImage != nil else { return }
        let location = gesture.location(in: overlayView)
        let pdfLoc = viewToPdf(location)

        switch gesture.state {
        case .began:
            let viewRect = pdfRectToView(currentImageRect)
            let corners: [(CGPoint, DragMode)] = [
                (CGPoint(x: viewRect.minX, y: viewRect.minY), .tl),
                (CGPoint(x: viewRect.maxX, y: viewRect.minY), .tr),
                (CGPoint(x: viewRect.minX, y: viewRect.maxY), .bl),
                (CGPoint(x: viewRect.maxX, y: viewRect.maxY), .br),
            ]
            for (pt, mode) in corners {
                if hypot(location.x - pt.x, location.y - pt.y) <= handleHitRadius {
                    dragMode = mode
                    dragStartPdf = pdfLoc
                    dragOrigRect = currentImageRect
                    return
                }
            }
            if viewRect.contains(location) {
                dragMode = .move
                dragStartPdf = pdfLoc
                dragOrigRect = currentImageRect
            }

        case .changed:
            guard dragMode != .none else { return }
            let dx = pdfLoc.x - dragStartPdf.x
            let dy = pdfLoc.y - dragStartPdf.y
            let orig = dragOrigRect

            switch dragMode {
            case .move:
                currentImageRect = orig.offsetBy(dx: dx, dy: dy)
            case .tl, .tr, .bl, .br:
                if aspectRatioLocked {
                    currentImageRect = aspectLockedResize(orig: orig, dx: dx, dy: dy)
                } else {
                    currentImageRect = freeResize(orig: orig, dx: dx, dy: dy)
                }
            case .none:
                break
            }
            overlayView.setNeedsDisplay()

        case .ended, .cancelled:
            dragMode = .none

        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard currentImage != nil else { return }

        switch gesture.state {
        case .began:
            pinchBaseWidth = currentImageRect.width
            pinchBaseHeight = currentImageRect.height
            pinchBaseCenter = CGPoint(x: currentImageRect.midX, y: currentImageRect.midY)

        case .changed:
            let scale = min(max(gesture.scale, 0.2), 5.0)
            var newW = max(pinchBaseWidth * scale, minImageSize)
            var newH: CGFloat
            if aspectRatioLocked {
                let aspect = pinchBaseWidth / max(pinchBaseHeight, 1)
                newH = newW / aspect
            } else {
                newH = max(pinchBaseHeight * scale, minImageSize)
            }
            if newH < minImageSize {
                newH = minImageSize
                newW = newH * pinchBaseWidth / max(pinchBaseHeight, 1)
            }
            currentImageRect = CGRect(
                x: pinchBaseCenter.x - newW / 2,
                y: pinchBaseCenter.y - newH / 2,
                width: newW, height: newH
            )
            overlayView.setNeedsDisplay()

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // No special tap handling needed — buttons are in the bottom bar
    }

    // MARK: - Resize Helpers

    private func aspectLockedResize(orig: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        let origW = orig.width, origH = orig.height
        guard origW > 1, origH > 1 else { return orig }
        let aspect = origW / origH

        let anchorRight = (dragMode == .tl || dragMode == .bl)
        let anchorBottom = (dragMode == .tl || dragMode == .tr)

        let signX: CGFloat = anchorRight ? -1 : 1
        let signY: CGFloat = anchorBottom ? -1 : 1
        let projectedDelta = (signX * dx + signY * dy) / 2

        var newW = max(origW + projectedDelta * signX * 2, minImageSize)
        var newH = newW / aspect
        if newH < minImageSize { newH = minImageSize; newW = newH * aspect }

        let anchorX = anchorRight ? orig.maxX : orig.minX
        let anchorY = anchorBottom ? orig.minY : orig.maxY
        let newMinX = anchorRight ? anchorX - newW : anchorX
        let newMinY = anchorBottom ? anchorY : anchorY - newH

        return CGRect(x: newMinX, y: newMinY, width: newW, height: newH)
    }

    private func freeResize(orig: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        let min = minImageSize
        switch dragMode {
        case .tl:
            let newMinX = Swift.min(orig.minX + dx, orig.maxX - min)
            let newMaxY = Swift.max(orig.maxY + dy, orig.minY + min)
            return CGRect(x: newMinX, y: orig.minY, width: orig.maxX - newMinX, height: newMaxY - orig.minY)
        case .tr:
            let newMaxX = Swift.max(orig.maxX + dx, orig.minX + min)
            let newMaxY = Swift.max(orig.maxY + dy, orig.minY + min)
            return CGRect(x: orig.minX, y: orig.minY, width: newMaxX - orig.minX, height: newMaxY - orig.minY)
        case .bl:
            let newMinX = Swift.min(orig.minX + dx, orig.maxX - min)
            let newMinY = Swift.min(orig.minY + dy, orig.maxY - min)
            return CGRect(x: newMinX, y: newMinY, width: orig.maxX - newMinX, height: orig.maxY - newMinY)
        case .br:
            let newMaxX = Swift.max(orig.maxX + dx, orig.minX + min)
            let newMinY = Swift.min(orig.minY + dy, orig.maxY - min)
            return CGRect(x: orig.minX, y: newMinY, width: newMaxX - orig.minX, height: orig.maxY - newMinY)
        default:
            return orig
        }
    }

    // MARK: - Overlay Drawing

    /// Custom overlay that draws the current image with selection handles.
    private class ImagePlacementOverlayView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ rect: CGRect) {
            guard let vc = findParentVC() as? ImagePlacementViewController,
                  let image = vc.currentImage,
                  let ctx = UIGraphicsGetCurrentContext() else { return }

            let viewRect = vc.pdfRectToView(vc.currentImageRect)
            image.draw(in: viewRect)

            // Selection overlay
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.06).cgColor)
            ctx.fill(viewRect)

            // Dashed border
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2.5)
            ctx.setLineDash(phase: 0, lengths: [8, 4])
            ctx.stroke(viewRect)
            ctx.restoreGState()
            ctx.setLineDash(phase: 0, lengths: [])

            // Corner handles
            let corners = [
                CGPoint(x: viewRect.minX, y: viewRect.minY),
                CGPoint(x: viewRect.maxX, y: viewRect.minY),
                CGPoint(x: viewRect.minX, y: viewRect.maxY),
                CGPoint(x: viewRect.maxX, y: viewRect.maxY),
            ]
            let r = vc.handleRadius
            for pt in corners {
                let cr = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                let path = UIBezierPath(roundedRect: cr, cornerRadius: 5)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                              color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.setFill()
                path.fill()
                ctx.restoreGState()
                UIColor.systemBlue.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }

        private func findParentVC() -> UIViewController? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return nil
        }
    }
}
