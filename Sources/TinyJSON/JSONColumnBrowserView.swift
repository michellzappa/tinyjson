import SwiftUI
import AppKit

/// Finder-style multi-column JSON browser.
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

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var scrollView: NSScrollView?
        var stackView: NSStackView?
        private var root: Any?
        /// Each column: (value being displayed, table view, entries)
        private var columns: [(value: Any, table: NSTableView, entries: [ColumnEntry])] = []

        struct ColumnEntry {
            let label: String
            let value: Any
            let isLeaf: Bool
        }

        func setRoot(_ value: Any) {
            // Avoid full rebuild if root identity hasn't changed
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

        // MARK: - Column management

        private func addColumn(for value: Any) {
            guard let stackView else { return }

            let entries = entriesFor(value)
            guard !entries.isEmpty else {
                // Leaf value: show detail pane
                addLeafColumn(for: value)
                return
            }

            let tableView = NSTableView()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.rowHeight = 22
            tableView.style = .plain
            tableView.tag = columns.count

            let colScroll = NSScrollView()
            colScroll.documentView = tableView
            colScroll.hasVerticalScroller = true
            colScroll.hasHorizontalScroller = false
            colScroll.drawsBackground = false
            colScroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                colScroll.widthAnchor.constraint(equalToConstant: 220),
            ])

            // Separator line
            if !columns.isEmpty {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                stackView.addArrangedSubview(sep)
            }

            stackView.addArrangedSubview(colScroll)
            pinToFullHeight(colScroll, in: stackView)

            tableView.delegate = self
            tableView.dataSource = self

            self.columns.append((value: value, table: tableView, entries: entries))
            tableView.reloadData()

            // Scroll to reveal new column
            DispatchQueue.main.async { [weak self] in
                self?.scrollView?.contentView.scrollToVisible(colScroll.frame)
            }
        }

        private func addLeafColumn(for value: Any) {
            guard let stackView else { return }

            let text = NSTextField(wrappingLabelWithString: leafDisplayString(value))
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textColor = leafColor(value)
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
            columns.removeSubrange(index...)
        }

        private func pinToFullHeight(_ view: NSView, in stack: NSStackView) {
            if let docView = scrollView?.documentView {
                view.topAnchor.constraint(equalTo: docView.topAnchor).isActive = true
                view.bottomAnchor.constraint(equalTo: docView.bottomAnchor).isActive = true
            }
        }

        // MARK: - Data

        private func entriesFor(_ value: Any) -> [ColumnEntry] {
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

        private func isLeafValue(_ value: Any) -> Bool {
            if value is [String: Any] { return false }
            if value is [Any] { return false }
            return true
        }

        private func leafDisplayString(_ value: Any) -> String {
            if let s = value as? String { return "\"\(s)\"" }
            if let n = value as? NSNumber {
                if CFBooleanGetTypeID() == CFGetTypeID(n) { return n.boolValue ? "true" : "false" }
                return n.stringValue
            }
            if value is NSNull { return "null" }
            return "\(value)"
        }

        private func summaryString(_ value: Any) -> String {
            if let dict = value as? [String: Any] {
                return "{\(dict.count) \(dict.count == 1 ? "key" : "keys")}"
            }
            if let arr = value as? [Any] {
                return "[\(arr.count) \(arr.count == 1 ? "item" : "items")]"
            }
            return leafDisplayString(value)
        }

        private func leafColor(_ value: Any) -> NSColor {
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

// MARK: - NSTableView delegate/datasource

extension JSONColumnBrowserView.Coordinator: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        let idx = tableView.tag
        guard idx < columns.count else { return 0 }
        return columns[idx].entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let idx = tableView.tag
        guard idx < columns.count, row < columns[idx].entries.count else { return nil }
        let entry = columns[idx].entries[row]

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
                textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
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
        let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

        attributed.append(NSAttributedString(string: entry.label, attributes: [
            .font: boldFont, .foregroundColor: keyColor,
        ]))

        if entry.isLeaf {
            attributed.append(NSAttributedString(string: ": ", attributes: [
                .font: baseFont, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            attributed.append(NSAttributedString(string: summaryString(entry.value), attributes: [
                .font: baseFont, .foregroundColor: leafColor(entry.value),
            ]))
        } else {
            attributed.append(NSAttributedString(string: "  \(summaryString(entry.value))", attributes: [
                .font: baseFont, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }

        cell.textField?.attributedStringValue = attributed
        cell.textField?.toolTip = "\(entry.label): \(summaryString(entry.value))"

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
        let colIdx = tableView.tag
        let row = tableView.selectedRow
        guard colIdx < columns.count, row >= 0, row < columns[colIdx].entries.count else { return }

        let entry = columns[colIdx].entries[row]

        // Remove columns after this one
        removeColumnsFrom(colIdx + 1)

        // Add new column for the selected value
        addColumn(for: entry.value)
    }
}
