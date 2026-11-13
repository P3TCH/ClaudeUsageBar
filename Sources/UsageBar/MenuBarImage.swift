import AppKit

/// Draws the menu bar label: small values stacked two per column, as a template
/// image so the system tints it for light/dark menu bars and the highlighted state.
/// AppKit only, so it can be compiled on its own to render a preview.
enum MenuBarImage {
    static let fontSize: CGFloat = 9
    /// Status item height.
    static let height: CGFloat = 22
    /// Baseline-to-baseline distance between the two rows of a column.
    static let rowPitch: CGFloat = 10
    /// Space between columns.
    static let columnGap: CGFloat = 5
    /// Padding on each side; the system adds its own item padding.
    static let sidePadding: CGFloat = 1

    private struct Placed: Sendable {
        let text: String
        let x: CGFloat
        let baseline: CGFloat
    }

    static func make(columns: [[String]]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let capHeight = font.capHeight

        // Centre the digits (cap height) of a pair, or of a single value, vertically.
        let pairBottom = ((height - (rowPitch + capHeight)) / 2).rounded()
        let singleBaseline = ((height - capHeight) / 2).rounded()

        var placed: [Placed] = []
        var x = sidePadding
        for (index, column) in columns.enumerated() {
            if index > 0 { x += columnGap }
            let widths = column.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            let columnWidth = widths.max() ?? 0
            for (row, (text, width)) in zip(column, widths).enumerated() {
                let baseline: CGFloat
                if column.count == 1 {
                    baseline = singleBaseline
                } else {
                    baseline = pairBottom + rowPitch * CGFloat(column.count - 1 - row)
                }
                placed.append(Placed(text: text, x: x + columnWidth - width, baseline: baseline))
            }
            x += columnWidth
        }
        let size = NSSize(width: max(x + sidePadding, 1), height: height)
        let fontSize = fontSize

        let image = NSImage(size: size, flipped: false) { _ in
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            for item in placed {
                // Without .usesLineFragmentOrigin the rect origin is the baseline.
                (item.text as NSString).draw(
                    with: NSRect(x: item.x, y: item.baseline, width: size.width, height: 0),
                    options: [],
                    attributes: attributes
                )
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
