import SwiftUI

struct JSONStatsView: View {
    let parsedJSON: Any
    let characterCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overview
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        statRow("Type", value: typeName(parsedJSON))
                        statRow("Size", value: formattedSize)
                        statRow("Total Keys", value: "\(countKeys(parsedJSON))")
                        statRow("Max Depth", value: "\(maxDepth(parsedJSON))")
                        if let arr = parsedJSON as? [Any] {
                            statRow("Items", value: "\(arr.count)")
                            statRow("Item Types", value: itemUniformity(arr))
                        }
                        if let dict = parsedJSON as? [String: Any] {
                            statRow("Top-level Keys", value: "\(dict.count)")
                        }
                    }
                } header: {
                    Text("Overview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                // Schema
                if !schema.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            // Header
                            HStack(spacing: 0) {
                                Text("Key")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Type")
                                    .frame(width: 70, alignment: .leading)
                                Text("Count")
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)

                            Divider()

                            ForEach(Array(schema.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: 0) {
                                    Text(entry.key)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.type)
                                        .foregroundStyle(typeColor(entry.type))
                                        .frame(width: 70, alignment: .leading)
                                    Text("\(entry.count)/\(entry.total)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)

                                if entry.key != schema.last?.key {
                                    Divider().padding(.leading, 6)
                                }
                            }
                        }
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } header: {
                        Text("Schema")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }

                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Stat row

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Computed

    private var formattedSize: String {
        if characterCount < 1024 {
            return "\(characterCount) chars"
        } else if characterCount < 1024 * 1024 {
            return String(format: "%.1f KB", Double(characterCount) / 1024)
        } else {
            return String(format: "%.1f MB", Double(characterCount) / (1024 * 1024))
        }
    }

    private var schema: [(key: String, type: String, count: Int, total: Int)] {
        // For objects: list top-level keys
        if let dict = parsedJSON as? [String: Any] {
            return dict.sorted(by: { $0.key < $1.key }).map {
                (key: $0.key, type: typeName($0.value), count: 1, total: 1)
            }
        }
        // For arrays of objects: union of keys with counts
        if let arr = parsedJSON as? [Any] {
            let dicts = arr.compactMap { $0 as? [String: Any] }
            guard !dicts.isEmpty else { return [] }
            var keyTypes: [String: [String: Int]] = [:] // key -> type -> count
            for dict in dicts {
                for (k, v) in dict {
                    keyTypes[k, default: [:]][typeName(v), default: 0] += 1
                }
            }
            return keyTypes.keys.sorted().map { key in
                let types = keyTypes[key]!
                let dominant = types.max(by: { $0.value < $1.value })!.key
                let count = types.values.reduce(0, +)
                let typeLabel = types.count > 1 ? "Mixed" : dominant
                return (key: key, type: typeLabel, count: count, total: dicts.count)
            }
        }
        return []
    }

    // MARK: - Helpers

    private func typeName(_ value: Any) -> String {
        if value is [String: Any] { return "Object" }
        if value is [Any] { return "Array" }
        if value is String { return "String" }
        if let n = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(n) { return "Boolean" }
            return "Number"
        }
        if value is NSNull { return "Null" }
        return "Unknown"
    }

    private func countKeys(_ value: Any) -> Int {
        if let dict = value as? [String: Any] {
            return dict.count + dict.values.map { countKeys($0) }.reduce(0, +)
        }
        if let arr = value as? [Any] {
            return arr.map { countKeys($0) }.reduce(0, +)
        }
        return 0
    }

    private func maxDepth(_ value: Any, current: Int = 0) -> Int {
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return current + 1 }
            return dict.values.map { maxDepth($0, current: current + 1) }.max() ?? current + 1
        }
        if let arr = value as? [Any] {
            if arr.isEmpty { return current + 1 }
            return arr.map { maxDepth($0, current: current + 1) }.max() ?? current + 1
        }
        return current
    }

    private func itemUniformity(_ arr: [Any]) -> String {
        guard !arr.isEmpty else { return "Empty" }
        let types = Set(arr.map { typeName($0) })
        if types.count == 1 {
            return "All \(types.first!)"
        }
        return "Mixed (\(types.sorted().joined(separator: ", ")))"
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "String": return .green
        case "Number": return .orange
        case "Boolean", "Null": return .purple
        case "Object", "Array": return .blue
        default: return .secondary
        }
    }
}
