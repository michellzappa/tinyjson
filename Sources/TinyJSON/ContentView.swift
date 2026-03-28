import SwiftUI
import TinyKit

enum PreviewMode: String, CaseIterable, Identifiable {
    case tree = "Tree"
    case table = "Table"
    case stats = "Stats"
    case columns = "Columns"

    var id: Self { self }
}

struct ContentView: View {
    @Bindable var state: AppState
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @AppStorage("wordWrap") private var wordWrap = false
    @AppStorage("previewUserPref") private var previewUserPref = true
    @AppStorage("previewMode") private var previewMode: PreviewMode = .tree
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @State private var showQuickOpen = false
    @State private var eventMonitor: Any?
    @State private var jumpToRange: NSRange?
    @State private var treeExpanded = true
    @State private var aiState = AIState()
    @State private var editorBridge = EditorBridge()

    private var showPreview: Bool {
        previewUserPref && state.isJSONFile
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            TinyFileList(state: state)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if state.tabs.count > 1 {
                    TinyTabBar(state: state)
                    Divider()
                }
                if showPreview {
                    EditorSplitView {
                        TinyEditorView(
                            text: $state.content,
                            wordWrap: $wordWrap,
                            fontSize: $fontSize,
                            showLineNumbers: $showLineNumbers,
                            shouldHighlight: state.isJSONFile,
                            highlighterProvider: { JSONHighlighter() },
                            commentStyle: .lineSlash,
                            jumpToRange: $jumpToRange,
                            editorBridge: editorBridge
                        )
                    } right: {
                        VStack(spacing: 0) {
                            if let error = state.jsonError {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .padding(.top, 1)
                                    Text(error)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                    Spacer()
                                    if state.errorOffset != nil {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.red.opacity(0.08))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let offset = state.errorOffset {
                                        jumpToRange = NSRange(location: offset, length: 0)
                                    }
                                }
                                .help("Click to jump to error")
                                Divider()
                            }
                            // Lenient warning banner
                            if state.parsedJSON == nil && !state.jsonWarnings.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Showing repaired preview")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(state.jsonWarnings.joined(separator: " · "))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.orange.opacity(0.08))
                                Divider()
                            }

                            // Mode picker + tree controls
                            HStack(spacing: 8) {
                                Picker("", selection: $previewMode) {
                                    ForEach(PreviewMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .fixedSize()

                                if previewMode == .tree {
                                    Button {
                                        treeExpanded = true
                                    } label: {
                                        Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(treeExpanded)
                                    Button {
                                        treeExpanded = false
                                    } label: {
                                        Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(!treeExpanded)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Divider()

                            // Preview content
                            if let parsed = state.parsedJSON ?? state.lenientParsedJSON {
                                switch previewMode {
                                case .tree:
                                    JSONTreeView(rootNode: JSONNode.from(parsed), expandAll: treeExpanded)
                                case .table:
                                    JSONTableView(parsedJSON: parsed)
                                case .stats:
                                    JSONStatsView(parsedJSON: parsed, characterCount: state.content.count)
                                case .columns:
                                    JSONColumnBrowserView(parsedJSON: parsed)
                                }
                            } else {
                                ContentUnavailableView("No Valid JSON", systemImage: "curlybraces", description: Text("Edit the file to see the tree preview"))
                            }
                        }
                    }
                } else {
                    TinyEditorView(
                        text: $state.content,
                        wordWrap: $wordWrap,
                        fontSize: $fontSize,
                        showLineNumbers: $showLineNumbers,
                        shouldHighlight: state.isJSONFile,
                        highlighterProvider: { JSONHighlighter() },
                        commentStyle: .lineSlash,
                        jumpToRange: $jumpToRange,
                        editorBridge: editorBridge
                    )
                }

                StatusBarView(text: state.content)
            }
            .modifier(CmdKOverlay(aiState: aiState, editorBridge: editorBridge, content: state.content, fileExtension: state.selectedFile?.pathExtension))
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers ?? ""

                if flags == .option && chars == "z" {
                    wordWrap.toggle()
                    return nil
                }
                if flags == .option && chars == "p" {
                    previewUserPref.toggle()
                    return nil
                }
                if flags == .option && chars == "l" {
                    showLineNumbers.toggle()
                    return nil
                }
                if flags == .option && chars == "f" {
                    state.formatJSON()
                    return nil
                }
                if flags == .command && chars == "p" {
                    showQuickOpen.toggle()
                    return nil
                }
                if flags == .command && chars == "w" && state.tabs.count > 1 {
                    state.closeActiveTab()
                    return nil
                }
                if flags == .command && (chars == "=" || chars == "+") {
                    fontSize = min(fontSize + 1, 32)
                    return nil
                }
                if flags == .command && chars == "-" {
                    fontSize = max(fontSize - 1, 9)
                    return nil
                }
                if flags == .command && chars == "0" {
                    fontSize = 13
                    return nil
                }
                if flags == .command && chars == "k" {
                    aiState.activate(selection: editorBridge.currentSelection, range: editorBridge.currentSelectedRange, bridge: editorBridge, folderURL: state.folderURL, supportedExtensions: state.supportedExtensions)
                    return nil
                }
                if flags == .command && (chars == "f" || chars == "g") {
                    return event
                }
                if flags == [.command, .shift] && chars == "g" {
                    return event
                }
                return event
            }
        }
        .sheet(isPresented: $showQuickOpen) {
            QuickOpenView(state: state, isPresented: $showQuickOpen)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        wordWrap.toggle()
                    } label: {
                        Image(systemName: wordWrap ? "text.word.spacing" : "arrow.left.and.right.text.vertical")
                    }
                    .help("Toggle Word Wrap (\u{2325}Z)")
                    Button {
                        showLineNumbers.toggle()
                    } label: {
                        Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                    }
                    .help("Toggle Line Numbers (\u{2325}L)")
                    Button {
                        withAnimation { previewUserPref.toggle() }
                    } label: {
                        Image(systemName: previewUserPref ? "rectangle.righthalf.filled" : "rectangle.righthalf.inset.filled")
                    }
                    .help("Toggle Preview (\u{2325}P)")
                    Button {
                        state.formatJSON()
                    } label: {
                        Image(systemName: "text.alignleft")
                    }
                    .help("Format JSON (\u{2325}F)")
                }
            }
        }
    }
}
