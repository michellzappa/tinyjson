import SwiftUI
import AppKit

/// A node in the parsed JSON tree.
final class JSONNode: NSObject {
    enum Kind {
        case object([(key: String, value: JSONNode)])
        case array([JSONNode])
        case string(String)
        case number(String)
        case bool(Bool)
        case null
    }

    let kind: Kind
    let label: String // display label (key name or array index)

    init(kind: Kind, label: String = "") {
        self.kind = kind
        self.label = label
    }

    var isExpandable: Bool {
        switch kind {
        case .object(let pairs): return !pairs.isEmpty
        case .array(let items): return !items.isEmpty
        default: return false
        }
    }

    var childCount: Int {
        switch kind {
        case .object(let pairs): return pairs.count
        case .array(let items): return items.count
        default: return 0
        }
    }

    func child(at index: Int) -> JSONNode {
        switch kind {
        case .object(let pairs): return pairs[index].value
        case .array(let items): return items[index]
        default: fatalError("No children")
        }
    }

    var displayValue: String {
        switch kind {
        case .object(let pairs): return "{\(pairs.count) \(pairs.count == 1 ? "key" : "keys")}"
        case .array(let items): return "[\(items.count) \(items.count == 1 ? "item" : "items")]"
        case .string(let s): return "\"\(s)\""
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// Build a JSONNode tree from a parsed JSON object.
    static func from(_ value: Any, label: String = "root") -> JSONNode {
        if let dict = value as? [String: Any] {
            let pairs = dict.sorted(by: { $0.key < $1.key }).map { (key: $0.key, value: from($0.value, label: $0.key)) }
            return JSONNode(kind: .object(pairs), label: label)
        } else if let arr = value as? [Any] {
            let items = arr.enumerated().map { from($0.element, label: "[\($0.offset)]") }
            return JSONNode(kind: .array(items), label: label)
        } else if let s = value as? String {
            return JSONNode(kind: .string(s), label: label)
        } else if let n = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return JSONNode(kind: .bool(n.boolValue), label: label)
            }
            return JSONNode(kind: .number(n.stringValue), label: label)
        } else if value is NSNull {
            return JSONNode(kind: .null, label: label)
        }
        return JSONNode(kind: .null, label: label)
    }
}

/// Renders a JSON tree as a collapsible NSOutlineView.
struct JSONTreeView: NSViewRepresentable {
    let rootNode: JSONNode?
    let expandAll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("json"))
        column.title = "JSON"
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 18
        outlineView.autoresizesOutlineColumn = true

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        context.coordinator.outlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let rootChanged = coordinator.rootNode !== rootNode
        coordinator.rootNode = rootNode
        coordinator.expandAllFlag = expandAll

        if rootChanged {
            coordinator.outlineView?.reloadData()
        }

        // Apply expand/collapse
        if let outlineView = coordinator.outlineView, rootNode != nil {
            if expandAll {
                outlineView.expandItem(nil, expandChildren: true)
            } else {
                outlineView.collapseItem(nil, collapseChildren: true)
                // Always keep root expanded
                if let root = rootNode {
                    outlineView.expandItem(root)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        var outlineView: NSOutlineView?
        var rootNode: JSONNode?
        var expandAllFlag = true

        // MARK: - DataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return rootNode != nil ? 1 : 0
            }
            guard let node = item as? JSONNode else { return 0 }
            return node.childCount
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return rootNode!
            }
            guard let node = item as? JSONNode else { fatalError() }
            return node.child(at: index)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? JSONNode else { return false }
            return node.isExpandable
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? JSONNode else { return nil }

            let cellID = NSUserInterfaceItemIdentifier("jsonCell")
            let cell: NSTextField
            if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField(labelWithString: "")
                cell.identifier = cellID
                cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.lineBreakMode = .byTruncatingTail
                cell.cell?.truncatesLastVisibleLine = true
            }

            let attributed = NSMutableAttributedString()
            let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Key label
            if !node.label.isEmpty && node.label != "root" {
                let keyColor: NSColor = isDark
                    ? NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1.0)
                attributed.append(NSAttributedString(string: node.label, attributes: [
                    .font: boldFont,
                    .foregroundColor: keyColor,
                ]))
                attributed.append(NSAttributedString(string: ": ", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }

            // Value
            let valueStr: String
            let valueColor: NSColor

            switch node.kind {
            case .object, .array:
                valueStr = node.displayValue
                valueColor = NSColor.secondaryLabelColor
            case .string(let s):
                valueStr = "\"\(s)\""
                valueColor = isDark
                    ? NSColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1.0)
                    : NSColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1.0)
            case .number(let n):
                valueStr = n
                valueColor = isDark
                    ? NSColor(red: 0.95, green: 0.7, blue: 0.4, alpha: 1.0)
                    : NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
            case .bool(let b):
                valueStr = b ? "true" : "false"
                valueColor = isDark
                    ? NSColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0)
            case .null:
                valueStr = "null"
                valueColor = isDark
                    ? NSColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0)
            }

            attributed.append(NSAttributedString(string: valueStr, attributes: [
                .font: baseFont,
                .foregroundColor: valueColor,
            ]))

            cell.attributedStringValue = attributed
            cell.toolTip = "\(node.label): \(valueStr)"

            return cell
        }
    }
}
