import SwiftUI
import AppKit

/// Finder-style multi-column JSON browser.
/// Each column has its own independent data source and scroll position.
struct JSONColumnBrowserView: NSViewRepresentable {
    let parsedJSON: Any

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stack

        // Pin stack height to clip view so columns fill available vertical space
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.stackView = stack
        context.coordinator.setRoot(parsedJSON)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.setRoot(parsedJSON)
    }

    // MARK: - Column entry model

    struct ColumnEntry {
        let label: String
        let value: Any
        let isLeaf: Bool
    }

    // MARK: - Per-column data source (independent rows per column)

    final class ColumnDataSource: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        let entries: [ColumnEntry]
        weak var coordinator: Coordinator?
        let columnIndex: Int

        init(entries: [ColumnEntry], coordinator: Coordinator, columnIndex: Int) {
            self.entries = entries
            self.coordinator = coordinator
            self.columnIndex = columnIndex
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < entries.count else { return nil }
            let entry = entries[row]

            let cellID = NSUserInterfaceItemIdentifier("browserCell")
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                let view = NSTableCellView()
                view.identifier = cellID

                let textField = NSTextField(labelWithString: "")
                textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                textField.lineBreakMode = .byTruncatingTail
                textField.translatesAutoresizingMaskIntoConstraints = false

                let chevron = NSImageView()
                chevron.translatesAutoresizingMaskIntoConstraints = false
                chevron.setContentHuggingPriority(.required, for: .horizontal)

                view.addSubview(textField)
                view.addSubview(chevron)
                view.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                    textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
                    chevron.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    textField.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -2),
                    chevron.widthAnchor.constraint(equalToConstant: 10),
                ])

                cell = view
            }

            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let keyColor: NSColor = isDark
                ? NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0)
                : NSColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1.0)

            let attributed = NSMutableAttributedString()
            let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

            // Label (key name or array index)
            attributed.append(NSAttributedString(string: entry.label, attributes: [
                .font: boldFont, .foregroundColor: keyColor,
            ]))

            if entry.isLeaf {
                // Leaf: show value inline after label
                attributed.append(NSAttributedString(string: ": ", attributes: [
                    .font: baseFont, .foregroundColor: NSColor.secondaryLabelColor,
                ]))
                attributed.append(NSAttributedString(string: Helpers.summaryString(entry.value), attributes: [
                    .font: baseFont, .foregroundColor: Helpers.leafColor(entry.value),
                ]))
            } else {
                // Container: show count summary
                attributed.append(NSAttributedString(string: "  \(Helpers.summaryString(entry.value))", attributes: [
                    .font: baseFont, .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
            }

            cell.textField?.attributedStringValue = attributed
            cell.textField?.toolTip = "\(entry.label): \(Helpers.summaryString(entry.value))"

            // Chevron for expandable entries
            let chevron = cell.subviews.compactMap { $0 as? NSImageView }.first
            if !entry.isLeaf {
                chevron?.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                chevron?.contentTintColor = .tertiaryLabelColor
            } else {
                chevron?.image = nil
            }

            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < entries.count else { return }
            coordinator?.handleSelection(at: row, inColumn: columnIndex)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var scrollView: NSScrollView?
        var stackView: NSStackView?
        private var root: Any?

        /// Each column: (data source, scroll view wrapper)
        private var columns: [(dataSource: ColumnDataSource, scrollWrapper: NSScrollView)] = []

        func setRoot(_ value: Any) {
            let isSame: Bool
            if let oldDict = root as? NSDictionary, let newDict = value as? NSDictionary {
                isSame = oldDict == newDict
            } else if let oldArr = root as? NSArray, let newArr = value as? NSArray {
                isSame = oldArr == newArr
            } else {
                isSame = false
            }
            guard !isSame || columns.isEmpty else { return }

            root = value
            removeColumnsFrom(0)
            addColumn(for: value)
        }

        func handleSelection(at row: Int, inColumn columnIndex: Int) {
            guard columnIndex < columns.count else { return }
            let entry = columns[columnIndex].dataSource.entries[row]

            // Remove all columns after this one
            removeColumnsFrom(columnIndex + 1)

            // Add new column for the selected value
            addColumn(for: entry.value)
        }

        // MARK: - Column management

        private func addColumn(for value: Any) {
            guard let stackView else { return }

            let entries = Helpers.entriesFor(value)
            guard !entries.isEmpty else {
                addLeafColumn(for: value)
                return
            }

            let colIndex = columns.count
            let dataSource = ColumnDataSource(entries: entries, coordinator: self, columnIndex: colIndex)

            let tableView = NSTableView()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.rowHeight = 22
            tableView.style = .plain
            tableView.selectionHighlightStyle = .regular

            let colScroll = NSScrollView()
            colScroll.documentView = tableView
            colScroll.hasVerticalScroller = true
            colScroll.hasHorizontalScroller = false
            colScroll.drawsBackground = false
            colScroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                colScroll.widthAnchor.constraint(equalToConstant: 220),
            ])

            // Separator line between columns
            if !columns.isEmpty {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                stackView.addArrangedSubview(sep)
            }

            stackView.addArrangedSubview(colScroll)
            pinToFullHeight(colScroll, in: stackView)

            // Each column gets its own delegate/dataSource — fully independent
            tableView.delegate = dataSource
            tableView.dataSource = dataSource

            columns.append((dataSource: dataSource, scrollWrapper: colScroll))
            tableView.reloadData()

            // Scroll horizontally to reveal new column
            DispatchQueue.main.async { [weak self] in
                self?.scrollView?.contentView.scrollToVisible(colScroll.frame)
            }
        }

        private func addLeafColumn(for value: Any) {
            guard let stackView else { return }

            let text = NSTextField(wrappingLabelWithString: Helpers.leafDisplayString(value))
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textColor = Helpers.leafColor(value)
            text.isSelectable = true

            let container = NSScrollView()
            let clipView = NSClipView()
            clipView.documentView = text
            container.contentView = clipView
            container.hasVerticalScroller = true
            container.drawsBackground = false
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: 220),
            ])
            text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            ])

            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(sep)
            stackView.addArrangedSubview(container)
            pinToFullHeight(container, in: stackView)
        }

        private func removeColumnsFrom(_ index: Int) {
            guard let stackView else { return }
            // Remove all arranged subviews from the stack
            while stackView.arrangedSubviews.count > max(index * 2 - 1, 0) {
                let view = stackView.arrangedSubviews.last!
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            if index < columns.count {
                columns.removeSubrange(index...)
            }
        }

        private func pinToFullHeight(_ view: NSView, in stack: NSStackView) {
            if let docView = scrollView?.documentView {
                view.topAnchor.constraint(equalTo: docView.topAnchor).isActive = true
                view.bottomAnchor.constraint(equalTo: docView.bottomAnchor).isActive = true
            }
        }
    }

    // MARK: - Shared helpers

    enum Helpers {
        static func entriesFor(_ value: Any) -> [ColumnEntry] {
            if let dict = value as? [String: Any] {
                return dict.sorted(by: { $0.key < $1.key }).map { pair in
                    ColumnEntry(label: pair.key, value: pair.value, isLeaf: isLeafValue(pair.value))
                }
            }
            if let arr = value as? [Any] {
                return arr.enumerated().map { (i, val) in
                    ColumnEntry(label: "[\(i)]", value: val, isLeaf: isLeafValue(val))
                }
            }
            return []
        }

        static func isLeafValue(_ value: Any) -> Bool {
            if value is [String: Any] { return false }
            if value is [Any] { return false }
            return true
        }

        static func leafDisplayString(_ value: Any) -> String {
            if let s = value as? String { return "\"\(s)\"" }
            if let n = value as? NSNumber {
                if CFBooleanGetTypeID() == CFGetTypeID(n) { return n.boolValue ? "true" : "false" }
                return n.stringValue
            }
            if value is NSNull { return "null" }
            return "\(value)"
        }

        static func summaryString(_ value: Any) -> String {
            if let dict = value as? [String: Any] {
                return "{\(dict.count) \(dict.count == 1 ? "key" : "keys")}"
            }
            if let arr = value as? [Any] {
                return "[\(arr.count) \(arr.count == 1 ? "item" : "items")]"
            }
            return leafDisplayString(value)
        }

        static func leafColor(_ value: Any) -> NSColor {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if value is String {
                return isDark ? NSColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1) : NSColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1)
            }
            if let n = value as? NSNumber, CFBooleanGetTypeID() == CFGetTypeID(n) {
                return isDark ? NSColor(red: 0.8, green: 0.6, blue: 1, alpha: 1) : NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1)
            }
            if value is NSNumber {
                return isDark ? NSColor(red: 0.95, green: 0.7, blue: 0.4, alpha: 1) : NSColor(red: 0.8, green: 0.4, blue: 0, alpha: 1)
            }
            if value is NSNull {
                return isDark ? NSColor(red: 0.8, green: 0.6, blue: 1, alpha: 1) : NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1)
            }
            return .labelColor
        }
    }
}
