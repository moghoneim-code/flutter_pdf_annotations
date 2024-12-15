import PDFKit



extension PDFView {
    var visiblePages: [PDFPage] {
        guard let document = document else { return [] }

        return (0..<document.pageCount).compactMap { index in
            let page = document.page(at: index)
            return page
        }.filter { page in
            // Check if the page is at least partially visible
            let pageRect = convert(page.bounds(for: .mediaBox), from: page)
            return bounds.intersects(pageRect)
        }
    }
}