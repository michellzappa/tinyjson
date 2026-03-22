import SwiftUI
import AppKit

struct JSONTableView: View {
    let parsedJSON: Any

    var body: some View {
        if let array = asArrayOfObjects {
            JSONTableNSView(objects: array)
        } else {
            ContentUnavailableView(
                "Table view requires an array of objects",
                systemImage: "tablecells",
                description: Text("The current JSON is not an array of objects")
            )
        }
    }

    private var asArrayOfObjects: [[String: Any]]? {
        guard let arr = parsedJSON as? [Any] else { return nil }
        let dicts = arr.compactMap { $0 as? [String: Any] }
        guard !dicts.isEmpty else { return nil }
        return dicts
    }
}

// MARK: - NSTableView wrapper

struct JSONTableNSView: NSViewRepresentable {
    let objects: [[String: Any]]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.rowHeight = 20
        tableView.headerView = NSTableHeaderView()
        tableView.gridStyleMask = [.solidVerticalGridLineMask]

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.updateData(objects: objects)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateData(objects: objects)
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var tableView: NSTableView?
        private var headers: [String] = []
        private var dataRows: [[String]] = []
        private var sortedRows: [[String]] = []
        private var sortColumn: Int?
        private var sortAscending = true

        func updateData(objects: [[String: Any]]) {
            guard let tableView else { return }

            // Compute columns: sorted union of all keys
            let allKeys = objects.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
            let newHeaders = allKeys.sorted()

            // Compute rows
            let newRows = objects.map { dict in
                newHeaders.map { key in
                    guard let val = dict[key] else { return "\u{2014}" } // em dash
                    return displayValue(val)
                }
            }

            if newHeaders != headers {
                headers = newHeaders
                dataRows = newRows
                sortColumn = nil
                sortAscending = true

                for col in tableView.tableColumns.reversed() {
                    tableView.removeTableColumn(col)
                }

                for (i, header) in headers.enumerated() {
                    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(i)"))
                    col.title = header
                    col.minWidth = 60
                    col.width = max(CGFloat(header.count * 9 + 20), 80)
                    col.maxWidth = 600
                    col.sortDescriptorPrototype = NSSortDescriptor(key: "\(i)", ascending: true)
                    tableView.addTableColumn(col)
                }

                sortedRows = dataRows
            } else {
                dataRows = newRows
                applySorting()
            }

            tableView.reloadData()
        }

        private func displayValue(_ value: Any) -> String {
            if let dict = value as? [String: Any] {
                return "{\(dict.count) \(dict.count == 1 ? "key" : "keys")}"
            }
            if let arr = value as? [Any] {
                return "[\(arr.count) \(arr.count == 1 ? "item" : "items")]"
            }
            if let s = value as? String { return s }
            if let n = value as? NSNumber {
                if CFBooleanGetTypeID() == CFGetTypeID(n) {
                    return n.boolValue ? "true" : "false"
                }
                return n.stringValue
            }
            if value is NSNull { return "null" }
            return "\(value)"
        }

        private func applySorting() {
            if let col = sortColumn, col < headers.count {
                sortedRows = dataRows.sorted { a, b in
                    let va = col < a.count ? a[col] : ""
                    let vb = col < b.count ? b[col] : ""
                    if let na = Double(va), let nb = Double(vb) {
                        return sortAscending ? na < nb : na > nb
                    }
                    return sortAscending
                        ? va.localizedCompare(vb) == .orderedAscending
                        : va.localizedCompare(vb) == .orderedDescending
                }
            } else {
                sortedRows = dataRows
            }
        }

        // MARK: - DataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            sortedRows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            guard let colStr = tableColumn.identifier.rawValue.split(separator: "_").last,
                  let colIndex = Int(colStr),
                  row < sortedRows.count else { return nil }

            let value = colIndex < sortedRows[row].count ? sortedRows[row][colIndex] : ""

            let cellID = NSUserInterfaceItemIdentifier("cell")
            let cell: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField(labelWithString: "")
                cell.identifier = cellID
                cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.cell?.truncatesLastVisibleLine = true
            }

            cell.stringValue = value
            cell.lineBreakMode = .byTruncatingTail
            cell.maximumNumberOfLines = 1
            cell.toolTip = value

            // Dim special values
            if value == "\u{2014}" || value == "null" {
                cell.textColor = .tertiaryLabelColor
            } else if value.hasPrefix("{") || value.hasPrefix("[") {
                cell.textColor = .secondaryLabelColor
            } else {
                cell.textColor = .labelColor
            }

            return cell
        }

        // MARK: - Sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let colIndex = Int(key) else { return }
            sortColumn = colIndex
            sortAscending = descriptor.ascending
            applySorting()
            tableView.reloadData()
        }
    }
}
