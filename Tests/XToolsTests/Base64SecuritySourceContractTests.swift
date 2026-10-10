import Foundation
import AppKit
@testable import XTools
import Testing

/// Base64/security page source contracts.
///
/// Retained anchors are security-critical (no sensitive-value persistence,
/// no direct pasteboard/panel writes, no dual-mirrored state, bounded reads,
/// stale-generation rejection) plus symbol-level wiring. Multi-line
/// indentation-sensitive needles, verbatim help/copy labels, and layout
/// value anchors covered by behavior tests were retired.
struct Base64SecuritySourceContractTests {
    @Test func stringObfuscatorUsesCompactSharedControls() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift")

        doesNotContain(source, "IndexPanel(\"设置\")", "String obfuscator settings must not live in a separate settings panel")
        doesNotContain(source, "Stepper(\"", "String obfuscator must not use the native Stepper")
        contains(source, "IndexWorkbenchControlBar", "String obfuscator settings must use the shared workbench control area")
        occurrenceCount(source, "IndexOptionGroup", 4, "String obfuscator must keep preserve-spaces and replacement-character controls in separate option groups")
        contains(source, "IndexOptionSwitch(title: \"保留空格\", style: .standalone", "String obfuscator must keep the app-style preserve-spaces switch")
        contains(source, "set: { workspace.setReplacementCharacter($0) }", "String masking replacement-character input must normalize typed and pasted text before persistence")
        contains(source, "String(newValue.prefix(1))", "String obfuscator replacement-character input must allow only one character")
        contains(source, "replacementChar.first ?? \"*\"", "String obfuscator must keep first replacement character with star fallback")
        doesNotContain(source, "Label(\"混淆\", systemImage: \"play.fill\")", "String obfuscator must not retain an explicit execution button")
        contains(source, "static let synchronousInputByteLimit = 64 * 1_024", "String masking must keep benchmark-bounded small input on the immediate path")
        contains(source, "static let backgroundDebounce: Duration = IndexDebouncer.keystrokeDebounce", "String masking must debounce large-input background work on the unified keystroke cadence")
        contains(source, "@Published var input = \"\" {", "String masking input changes must be model-owned")
        contains(source, "func setReplacementCharacter(_ newValue: String)", "Replacement-character normalization must remain model-owned")
        contains(source, "outputPresentation: workspace.usesNativeOutput ? .nativeReadOnlyText : .standard", "Large string masking must avoid SwiftUI Text layout while preserving the ordinary short-output surface")
        contains(source, "inputRenderingMode: .textKit2Viewport", "Large string masking input must use the shared TextKit 2 viewport")
        contains(source, "inputCountPresentation: .charactersOrUTF8Size(", "Large string masking must replace expensive large grapheme counts with bounded UTF-8 size feedback")
        doesNotContain(source, ".onChange(of: workspace.input)", "String masking execution must not remain View-owned")
        doesNotContain(source, "didSet { clearOutput() }", "Real-time obfuscation must not clear output between recipe edits")
    }

    @Test func base64ConverterUsesAutomaticEmbeddedControls() throws {
        let converterSource = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let base64Source = try readSource("Sources/XTools/ToolPages/Converter/Base64StringPage.swift")

        contains(converterSource, "backfillsOutputOnModeChange: Bool = false", "Shared converter must keep the common boolean backfill convenience at the interface")
        contains(converterSource, "let backfillModeTransition: (String, String) -> Bool", "Shared converter must support pair-aware mode backfill transitions")
        contains(converterSource, "backfillModeTransition ?? { _, _ in backfillsOutputOnModeChange }", "Shared converter must keep the existing boolean backfill behavior as the default policy")
        contains(converterSource, "workspace.changeMode(to: $0, backfillModeTransition: backfillModeTransition)", "Shared converter must route mode changes through the workspace execution model")
        contains(converterSource, "completedRequest == IndexConverterRequest(input: input, mode: mode)", "Shared converter must only backfill a completed result for the current request identity")
        doesNotContain(converterSource, "ConverterModeBackfill.currentValidOutput", "Shared converter must not re-execute the previous conversion while backfilling a mode switch")
        contains(converterSource, "onClear: workspace.clear", "Shared converter must keep clear in the unified workbench toolbar via IndexFormatWorkbench")
        doesNotContain(converterSource, "embedsClearButtonInInputPanel", "Shared converter must not expose a switch for clear placement — clear is always embedded")
        doesNotContain(converterSource, "Label(\"清空\"", "Shared converter must not render a separate action-row clear button")

        doesNotContain(base64Source, "showsConvertButton:", "Base64 must inherit the settled no-primary-button behavior from the shared converter")
        contains(base64Source, "backfillsOutputOnModeChange: true", "Base64 must backfill the current valid output when switching direction")
        doesNotContain(base64Source, "embedsClearButtonInInputPanel", "Base64 must not pass the removed clear-placement switch")
        contains(base64Source, "isEmptyInputForMode:", "Decode-only whitespace must resolve to the empty state instead of a Base64 parse error")
    }

    @Test func base64FilePageSupportsForwardConversionModes() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let workflow = try readSource("Sources/XTools/ToolPages/Converter/Base64FileWorkflow.swift")
        let filePanel = try readSource("Sources/XTools/Shared/FileInputPanel.swift")
        let core = try readSource("Sources/XToolsCore/Encoding/Base64Conversion.swift")

        contains(workflow, "static let maxFileBytes = 50 * 1024 * 1024", "Base64 file workflow session must allow files up to 50MB")
        doesNotContain(source, "演示限制 2MB", "Base64 file page must remove the old 2MB demo limit")
        contains(source, "ToolWorkspaceHost(key: Base64FileWorkflowSession.workspaceKey)", "Base64 file page must resolve its retained workflow session")
        contains(source, "@ObservedObject var session: Base64FileWorkflowSession", "Base64 file content must observe the retained workflow session")
        contains(workflow, "var outputMode: Base64Conversion.FileOutputMode { state.outputMode }", "Base64 file session must project output mode from pure state")
        contains(workflow, "preferences?.value(for: MediaToolPreferenceKeys.base64FileOutputMode) ?? .dataURL", "Base64 file session must restore only the approved output-mode preference")
        contains(source, "items: [(\"base64\", \"Base64\"), (\"dataURL\", \"Data URL\")]", "Base64 file page must expose Base64 and Data URL output modes")
        contains(source, "session.changeOutputMode(to: Base64Conversion.FileOutputMode(rawValue: value) ?? .dataURL)", "Base64 file page must route output-mode changes through the session")
        contains(workflow, "func refreshOutputPreview(", "Base64 file session must own preview refresh")
        contains(workflow, "processor.outputPreview(for: selectedFile, mode: mode)", "Base64 file session must route preview generation through the workflow seam")
        contains(workflow, "processor.fullOutput(for: selectedFile, mode: mode)", "Base64 file session must generate full output only for explicit copy/save actions")
        contains(workflow, "isCurrentEncodedOutput(selection: selectedFile, mode: mode, generation: generation)", "Base64 full-output actions must reject stale mode or selection results")
        contains(source, "viewDecodeResultButton", "Base64 file page must expose current-output direct decode")
        contains(source, "session.sendCurrentOutputToDecodeResult()", "Base64 current-output direct decode must route through the session")
        contains(workflow, "func sendCurrentOutputToDecodeResult(", "Base64 file session must own current-output direct decode")
        contains(workflow, "processor.decodedPayload(for: selectedFile)", "Base64 current-output direct decode must use the source file payload instead of parsing generated Base64")
        contains(workflow, "$0.direction = .decode", "Base64 current-output direct decode must switch to the decode workspace after success")
        contains(source, "copyFullOutputButton", "Base64 file page must expose full-output copy")
        contains(source, "saveEncodedOutputButton", "Base64 file page must expose full-output save")
        contains(source, "session.outputPreview?.isTruncated == true", "Base64 file page must visibly mark large-output previews")

        // Import paths run through the shared window-scoped panel and workflow seam.
        doesNotContain(source, "NSPasteboard.general", "Base64 file page must not write pasteboard directly")
        doesNotContain(source, "NSOpenPanel()", "Base64 file page must not construct import panels directly")
        doesNotContain(source, ".fileImporter", "Base64 file page must use the reusable window-scoped panel instead of a per-request SwiftUI importer")
        contains(source, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "Base64 file page must receive the shared window-scoped panel client")
        contains(source, "session.selectSourceFile(filePanel: fileInputPanelClient)", "Base64 source selection must route through the session and shared panel client")
        contains(filePanel, "private let panel: NSOpenPanel", "The shared AppKit backend must own the reusable open panel")
        contains(filePanel, "panel.beginSheetModal(for: window)", "File input must use an async window-attached sheet")
        contains(workflow, "Base64FileWorkflowClient", "Base64 file workflow must expose an adapter seam for pasteboard and save panels")
        contains(workflow, "pasteboard.writeUTF8(data)", "Base64 file workflow client must own pasteboard writes")
        doesNotContain(workflow, "pasteboard.readString()", "Base64 file workflow must not keep clipboard-read plumbing after removing clipboard decode")
        doesNotContain(workflow, "func selectEncodedTextInputURL()", "Base64 save/pasteboard client must not construct encoded-text input panels")

        // File reads stay bounded and validated.
        contains(workflow, ".isPackageKey", "Base64 workflow must check packages separately from regular files")
        contains(workflow, "values.isRegularFile == true, values.isPackage != true", "Base64 workflow must accept only regular non-package files")
        occurrenceCount(workflow, "BoundedFileReader.read(from: url, maxBytes: maxBytes)", 2, "Both Base64 import paths must enforce the read budget")
        contains(workflow, "Base64Conversion.encodedOutputPreview(", "Base64 workflow must use the core large-output preview policy")
        contains(workflow, "Base64Conversion.encodedOutput(", "Base64 workflow must support full raw Base64 and Data URL output")
        contains(workflow, "values.contentType?.preferredMIMEType", "Base64 workflow must use the system-provided MIME type when available")
        contains(workflow, "Base64Conversion.inferredFileType(for: data)?.mimeType", "Base64 workflow must infer MIME type from file signature")
        contains(workflow, "\"application/octet-stream\"", "Base64 workflow must fall back to application/octet-stream")
        contains(core, "public enum FileOutputMode", "Core Base64 conversion must own file output modes")
        contains(core, "public struct EncodedFileOutputPreview", "Core Base64 conversion must own preview summary data")
    }

    @Test func base64FilePageSupportsReverseSaveAndPreview() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let projection = try readSource("Sources/XToolsCore/Encoding/Base64FileWorkspaceProjection.swift")
        let workflow = try readSource("Sources/XTools/ToolPages/Converter/Base64FileWorkflow.swift")

        contains(workflow, "@Published private(set) var state: Base64FileWorkspaceSessionState", "Base64 file session must own pure workspace state as the single source of truth")
        contains(workflow, "var direction: Base64FileWorkflowDirection { state.direction }", "Base64 file session must project encode/decode direction from pure state")
        contains(source, "selection: directionBinding", "Base64 file page must offer a top-level encode/decode mode switch")
        contains(source, "if session.direction == .encode {", "Base64 file page must show only the workflow for the active direction")
        contains(workflow, "var reverseInput: String { state.reverseInput }", "Base64 file session must project reverse Base64/Data URL input from pure state")
        contains(workflow, "var decodedPayload: Base64Conversion.FilePayload? { state.decodedPayload }", "Base64 file session must project decoded file payload from pure state")
        contains(workflow, "@Published private(set) var previewImage: NSImage?", "Base64 file session must keep optional image preview state")
        doesNotContain(workflow, "pureStateSnapshot", "Base64 file session must not dual-mirror pure state through snapshot helpers")
        doesNotContain(workflow, "applyPureState", "Base64 file session must not dual-mirror pure state through apply helpers")
        doesNotContain(source, "IndexTextConversionWorkbench(", "Base64 file page must stay a mixed file workflow, not the text conversion editor workbench")
        doesNotContain(source, "workspaceSemantic: .copyTransformWorkspace", "Base64 file page must not inherit Base64 string copy-transform semantics")
        doesNotContain(source, "workspaceSemantic: .structuredEditorTransform", "Base64 file page must not inherit structured formatter editor-transform semantics")

        // Reverse input stays bounded through the shared input policy.
        contains(source, "IndexWorkspaceTextArea(", "Base64 file page must provide reverse input through the workspace semantic text area")
        contains(source, "minHeight: Base64FileLayout.primaryContentMinHeight", "Base64 reverse input must use the shared workbench content minimum")
        doesNotContain(source, "minHeight: 260", "Base64 reverse input must not keep the old oversized editor height")
        contains(source, "inputPolicy: .init(", "Base64 reverse input must opt into the shared input policy")
        contains(source, "maxUTF8Bytes: Base64FileWorkflowSession.editableReverseInputByteLimit", "Base64 reverse input must enforce the workflow-owned editable byte limit")
        contains(source, "undoLevels: Base64FileWorkflowSession.reverseInputUndoLevels", "Base64 reverse input must use the workflow-owned finite undo depth")
        contains(source, "session.rejectReverseInputLimit(maxBytes: rejection.maxUTF8Bytes)", "Base64 reverse input must surface rejected paste attempts through the session diagnostic")
        contains(source, "workspaceSemantic: .base64FileWorkspace", "Base64 reverse input must explicitly select the mixed file workspace semantic")
        contains(source, "session.decodeReverseInput()", "Base64 file page must delegate decode action to the session")
        contains(workflow, "processor.decodePayload(inputSnapshot)", "Base64 file session must decode through the async workflow seam")
        contains(workflow, "func updateReverseInput(_ newValue: String)", "Base64 file session must mark pasted input dirty instead of decoding every edit")
        contains(workflow, "static let editableReverseInputByteLimit = 1 * 1024 * 1024", "Base64 file session must keep a 1MB editable reverse-input boundary")
        contains(workflow, "static let externalEncodedTextByteLimit = 16 * 1024 * 1024", "Base64 file session must cap first-version encoded text file input at 16MB")
        contains(workflow, "guard newValue.utf8.count <= Self.editableReverseInputByteLimit else", "Base64 file session must reject oversized reverse input even if UI interception is bypassed")
        contains(workflow, "func rejectReverseInputLimit(maxBytes: Int = editableReverseInputByteLimit)", "Base64 file session must own the rejected-input diagnostic state transition")
        contains(workflow, "generation = $0.beginDecodeAttempt(activity)", "Base64 file session must invalidate stale decode work through pure-state beginDecodeAttempt")
        contains(workflow, "Base64Conversion.normalizedFileName(outputFileName, fileExtension: payload.fileExtension)", "Base64 file session must append missing filename extensions")
        contains(workflow, "processor.previewImage(for: payload)", "Base64 file session must route preview image creation through the workflow policy")

        // Saves go through the sheet dialog and shared seams, never direct panels.
        doesNotContain(source, "NSSavePanel()", "Base64 file page must not construct save panels directly")
        doesNotContain(workflow, "NSSavePanel()", "Base64 file workflow must not construct save panels — saves go through the sheet output panel")
        contains(workflow, "SheetBase64FileWorkflowDialog", "Base64 file workflow must use the sheet-based save dialog")
        contains(workflow, "allowedContentTypes: [.plainText]", "Base64 encoded-text saves must constrain content types to plain text")
        contains(workflow, "UTType(filenameExtension: fileExtension)", "Base64 decoded saves must map the payload extension to a content type")
        contains(workflow, "processor.write(payload.data, to: url)", "Base64 file session must write decoded bytes through the async workflow seam")
        contains(workflow, "Base64FileLimits.maxDecodedPayloadBytes", "Base64 workflow must use shared decoded payload size limit")
        let models = try readSource("Sources/XToolsCore/Encoding/Base64FileModels.swift")
        contains(models, "maxDecodedPayloadBytes = 50 * 1024 * 1024", "Base64 Core limits must keep the 50MB decoded payload cap")
        contains(workflow, "Base64Conversion.decodedByteCountUpperBound(forBase64Payload: encodedPayload)", "Base64 workflow must estimate decoded size before allocating decoded data")
        contains(workflow, "Base64Conversion.decodeFilePayload(trimmed)", "Base64 workflow must decode trimmed Base64/Data URL through the core helper")

        // Clipboard decode stays removed; import runs through the session.
        contains(source, "importEncodedTextFileButton", "Base64 reverse workspace must keep encoded text file import as a separate header button")
        doesNotContain(source, "解码剪贴板", "Base64 reverse workspace must not expose clipboard direct decode copy")
        doesNotContain(source, "session.decodeClipboard()", "Base64 clipboard direct decode must not remain wired from the page")
        doesNotContain(workflow, "func decodeClipboard(", "Base64 file session must remove clipboard direct decode")
        contains(source, "session.importEncodedTextFile(filePanel: fileInputPanelClient)", "Base64 encoded text import must route through the session and shared panel client")
        contains(workflow, "func importEncodedTextFile(", "Base64 file session must own encoded text file import")
        contains(workflow, "func decodeExternalEncodedText(", "Base64 file session must share external encoded text decode state transitions")
        contains(workflow, "processor.readEncodedText(", "Base64 encoded text file import must read through the workflow seam")
        contains(workflow, "guard text.utf8.count <= Self.externalEncodedTextByteLimit else", "Base64 external encoded text decode must reject oversized strings before decode")

        // Previews decode off the main actor and write atomically.
        contains(workflow, "CGImageSourceCreateThumbnailAtIndex", "Base64 workflow must decode image previews through an off-main thumbnail pipeline")
        contains(workflow, "kCGImageSourceShouldCacheImmediately", "Base64 workflow must force preview image decoding off the main actor")
        contains(workflow, "data.write(to: url, options: .atomic)", "Base64 workflow must write decoded bytes atomically")

        contains(source, "Base64DecodedMetadataList(rows: metadataRows(projection.reverseRows))", "Base64 file page must render decoded MIME, size, and status summary from the workspace projection")
        contains(projection, "label: \"MIME 类型\"", "Base64 decoded metadata projection must keep MIME, size, and status labels")
        contains(workflow, "var decodedResultSource: Base64FileDecodedResultSource? { state.decodedResultSource }", "Base64 file session must project decoded result source from pure state")
        contains(projection, "value: payload.mimeType", "Base64 decoded summary must include MIME type")
        contains(projection, "ByteSizeFormatter.format(bytes: payload.data.count)", "Base64 decoded summary must include file size")
        doesNotContain(source, "rows.append((\"来源\"", "Base64 decoded metadata must retain the prototype's focused three-row hierarchy")
        doesNotContain(source, "decodedPreviewSummary", "Base64 decoded metadata must not repeat the preview state")
        contains(projection, "hasPrefix(\"image/\")", "Base64 decoded summary must classify image payloads from MIME type")
        contains(source, "Base64DecodedNoticeSurface(", "Base64 decoded static notices must not reuse the loading surface")
        contains(source, "projection.decodedPreviewNoticeText", "Base64 decoded notices must come from the workspace projection")
        contains(projection, "isImagePayload(payload)", "Base64 image-preview notices must classify image MIME types in the projection")
    }

    @Test func base64FilePageSupportsP1InteractionEnhancements() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let projection = try readSource("Sources/XToolsCore/Encoding/Base64FileWorkspaceProjection.swift")
        let workflow = try readSource("Sources/XTools/ToolPages/Converter/Base64FileWorkflow.swift")

        contains(source, "@Environment(\\.toolToastCenter) private var toastCenter", "Base64 file page must use the shared toast center")
        contains(workflow, "var isReadingFile: Bool { state.isReadingFile }", "Base64 file session must project file-reading busy state from pure state")
        contains(source, "@State private var isFileDropTargeted = false", "Base64 file page must track drag targeting state")
        contains(source, ".indexDropZone(", "Base64 file page must support dragging ordinary files through the shared drop zone")
        contains(source, "onMultipleFiles: { session.rejectMultipleSourceFileDrop() }", "Base64 file drag/drop must clear stale state and diagnose a rejected multi-file batch")
        contains(source, "onFile: { session.readSelectedFile(from: $0) }", "Base64 file page must reuse one file-reading path for picker and drag/drop")
        contains(source, "IndexProgressSpinner()", "Base64 file page must show a loading indicator while reading files")
        contains(workflow, "mutate { $0.beginFileRead() }", "Base64 file session must enter pure-state busy read before async IO")
        contains(workflow, "mutate { $0.applySuccessfulFileRead(selection: selection, preview: preview) }", "Base64 file import must commit selection and preview together through pure state")
        contains(workflow, "applyFileReadFailure(failure.errorDescription ?? \"无法读取所选文件。\")", "Base64 file import must publish read failures through pure state")
        doesNotContain(workflow, "selectedFile = nil", "Base64 replacement import must not clear the visible selection before reading")
        doesNotContain(workflow, "outputPreview = nil", "Base64 replacement import must not clear the visible preview before reading")
        let pureState = try readSource("Sources/XToolsCore/Encoding/Base64FileWorkspaceSessionState.swift")
        contains(pureState, "isReadingFile = true", "Base64 pure state must enter busy state before reading")
        contains(pureState, "isReadingFile = false", "Base64 pure state must leave busy state after async read finishes")
        contains(pureState, "encodedWorkspaceState = Base64FileEncodedWorkspaceState(selection: selection, preview: preview)", "Base64 pure state must commit selection and preview together")
        doesNotContain(source, "Button { session.clearOutput() }", "Base64 file page must not keep a duplicate output-only clear action")
        doesNotContain(source, "encodeStatusBadge", "Base64 encode header must not repeat derived processing or save-ready state")
        doesNotContain(source, "decodeStatusBadge", "Base64 decode header must not repeat derived processing or save-ready state")
        doesNotContain(source, "Base64StatusBadge", "Base64 file page must not retain the removed multi-purpose status badge")
        contains(source, "Base64OutputCountBadge(", "Base64 output character count and truncation must share one compact factual badge")
        contains(source, "isTruncated ? \" · 截断\" : \"\"", "Base64 truncated previews must state that visible output is incomplete")
        contains(source, "Button { session.resetOutputFileName() }", "Base64 file page must provide a filename reset action")
        contains(source, "projection.fileClearDisabled", "Base64 file page must bind file clear enablement to the workspace projection")
        contains(projection, "let fileClearDisabled =", "Base64 file clear enablement must stay explicit in the workspace projection")
        contains(projection, "selectedFile == nil &&", "Base64 file clear action must stay enabled when no selection is visible")
        contains(projection, "fileError == nil &&", "Base64 file clear action must stay enabled when an error is visible")
        doesNotContain(workflow, "func clearOutput()", "Base64 file session must remove the unused output-only clearing path")
        contains(workflow, "func resetOutputFileName()", "Base64 file session must implement filename reset")
        contains(source, "toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)", "Base64 file page must show a success toast after saving")
    }

    @Test func base64OutputModeSwitchKeepsAStablePreviewFrame() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let projection = try readSource("Sources/XToolsCore/Encoding/Base64FileWorkspaceProjection.swift")
        let workflow = try readSource("Sources/XTools/ToolPages/Converter/Base64FileWorkflow.swift")
        let previewRefresh = sourceSlice(
            workflow,
            from: "func refreshOutputPreview(",
            to: "func clearSelection()"
        )

        contains(source, "private var encodedOutputPreviewSurface: some View", "Base64 output preview must render through one named stable surface")
        contains(source, "Base64EncodedOutputPreviewSurface(", "Base64 mode changes must update the dedicated bounded preview surface in place")
        contains(source, "scrollsInternally: projection.encodedOutputUsesBoundedScrolling", "Base64 short output must avoid an internal scroll container")
        contains(projection, "outputPreview.characterCount > inlinePreviewCharacterLimit", "Base64 output scrolling must follow the currently visible preview instead of rebuilding for a pending mode")
        contains(source, "inlinePreviewCharacterLimit: Base64FileLayout.inlinePreviewCharacterLimit", "Base64 page must pass the approved inline preview character limit into the projection")
        contains(previewRefresh, "mutate { $0.beginOutputPreviewRefresh() }", "Base64 mode refresh must keep its real busy state through pure state")
        doesNotContain(previewRefresh, "preview: nil", "Base64 mode refresh must retain the ready preview until its replacement is available")
        let pureState = try readSource("Sources/XToolsCore/Encoding/Base64FileWorkspaceSessionState.swift")
        contains(pureState, "isPreparingOutput = true", "Base64 pure state must mark preparing output while refreshing previews")
        doesNotContain(source, "正在生成输出预览", "Fast Base64 mode changes must not flash a full processing surface")
        doesNotContain(source, "IndexResultPresence(", "Large Base64 output must not gain a content-presence crossfade")
    }

    @Test func base64FilePageUsesContainerResponsiveWorkflowLayout() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let panelShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        let workbench = sourceSlice(
            source,
            from: "private struct Base64FileWorkbench<Leading: View, Trailing: View>: View",
            to: "private struct Base64OutputCountBadge: View"
        )

        contains(source, "private var forwardWorkflow: some View", "Base64 file page must define a forward file-to-output workflow")
        contains(source, "private var reverseWorkflow: some View", "Base64 file page must define a reverse input-to-file workflow")
        contains(source, "private struct Base64FileWorkbenchLayout: Layout", "Base64 file page must use one layout tree for stacked and horizontal modes")
        contains(workbench, "Base64FileWorkbenchLayout()", "Base64 workbench must delegate geometry to its container-responsive layout")
        occurrenceCount(workbench, "Base64FileWorkbenchPane {", 2, "Base64 workbench must build exactly one stable wrapper for each business pane")
        doesNotContain(workbench, "ViewThatFits", "Base64 workbench must not duplicate AppKit editor trees across responsive branches")
        contains(workbench, "GeometryReader { proxy in", "Base64 workbench must measure residual IndexPage height so wide panes can fill")
        contains(workbench, "ScrollView {", "Base64 stacked mode must retain one outer vertical scroll owner")
        contains(workbench, "if isHorizontal", "Base64 wide mode must fill residual height without forcing an outer scroll slab")
        doesNotContain(source, "selectedFileRows", "Base64 source panel must not repeat selected-file metadata below the picker")
        doesNotContain(source, "outputRows", "Base64 output panel must not repeat format, count, and preview state")
        doesNotContain(source, "IndexPairLayout(collapseWidth: 0, fillsHeight: true)", "Base64 file page must not keep the old equal-width pair layout")
        contains(source, "IndexPanel(\"源文件\")", "Base64 forward workflow must have a dedicated content-first source panel")
        contains(source, "IndexPanel(\"编码输出\")", "Base64 forward workflow must have a dedicated content-first output panel")
        contains(source, "IndexPanel(\"Base64 输入\")", "Base64 reverse workflow must have a dedicated content-first input panel")
        contains(source, "IndexPanel(\"解码结果\")", "Base64 reverse workflow must keep decoded preview and metadata together")
        contains(source, "private var encodedOutputHeaderActions: some View", "Base64 output format and result actions must share one named output header")
        doesNotContain(source, "private var encodedOutputCompactActionButtons", "Base64 encoded output actions must not duplicate a second compact toolbar")
        doesNotContain(source, "IndexOptionLabel(\"格式\")", "Base64/Data URL segmented options must not repeat a redundant format label")
        doesNotContain(source, "private var decodeActionCompactButton", "Base64 decode toolbar must not keep a duplicate compact implementation")
        doesNotContain(source, "private var importEncodedTextFileCompactButton", "Base64 import action must not keep a duplicate compact implementation")
        doesNotContain(source, "private struct Base64PanelActionRow", "Base64 file page must not place primary actions in isolated full-width content rows")
        contains(source, "IndexClearButton(isDisabled: projection.fileClearDisabled, iconOnly: true)", "Base64 source clear must use the prototype-aligned icon-only header action without changing its shared symbol")
        contains(source, "Base64FileWorkbenchFooter(", "Base64 workbench panes must expose their real state at the bottom edge")
        contains(source, "Base64DecodedFilePreview(", "Base64 decoded files must keep a stable preview surface for non-image payloads and empty state")
        doesNotContain(source, "hello.txt", "Base64 production UI must not hard-code the prototype's sample filename")
        doesNotContain(source, "WebView", "Base64 file page must not introduce WebView for file previews")

        contains(panelShell, "var reservesDiagnosticStatusSlot = true", "Panels must retain their diagnostic slot by default")
        contains(panelShell, "func withoutDiagnosticStatusSlot() -> IndexPanel", "Panels must opt out through one shared layout capability")
        doesNotContain(panelShell, "chromeDensity", "Panels must stay single-density — no standard/workbench fork")
    }

    @Test func base64FileWorkbenchLayoutPolicyUsesActualContainerWidth() throws {
        let policy = Base64FileWorkbenchLayoutPolicy()

        #expect(policy.mode(for: 680) == .stacked)
        #expect(policy.mode(for: 899.5) == .stacked)
        #expect(policy.mode(for: 900) == .horizontal)
        #expect(policy.mode(for: 920) == .horizontal)
        #expect(policy.columnWidths(for: 680) == nil)

        let widths = try #require(policy.columnWidths(for: 900))
        #expect(widths.trailing > widths.leading)
        #expect(abs(
            widths.leading
                + Base64FileWorkbenchLayoutPolicy.columnSpacing
                + widths.trailing
                - 900
        ) < 0.001)
        #expect(abs(widths.trailing / widths.leading - 1.05) < 0.001)
    }

    @Test func base64DecodeToolbarKeepsOneStableActionHierarchy() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let decodeHeader = sourceSlice(
            source,
            from: "private var decodeInputHeaderActions: some View",
            to: "private var decodedFileNameEditor: some View"
        )
        let decodedSave = sourceSlice(
            source,
            from: "private var saveDecodedButton: some View",
            to: "private var resetOutputFileNameButton: some View"
        )

        contains(decodeHeader, "IndexInputCountLabel(count: session.reverseInput.count)", "Base64 decode header must keep the input count visible")
        contains(decodeHeader, "title: \"解码\"", "Manual decode must remain the clearly labelled primary action")
        contains(decodeHeader, "private var importEncodedTextFileButton", "Encoded-text import must remain a separate secondary action")
        contains(decodeHeader, "private var clearReverseInputButton", "Decode clear must use a page-scoped labelled compact action")
        contains(decodeHeader, "IndexClearButton(", "Decode clear must use the shared clear button component")
        doesNotContain(decodeHeader, "IndexInputHeaderAccessory(", "Base64 decode header must not switch between responsive action branches")
        doesNotContain(decodeHeader, "compactControl:", "Base64 decode header must render one stable action composition at every supported width")

        contains(decodedSave, "Base64FileActivityLabel(", "Decoded save must keep progress feedback in the fixed icon slot")
        contains(decodedSave, "systemImage: IndexActionSymbol.save", "Decoded save must use the shared file-save symbol owner")
        contains(decodedSave, ".buttonStyle(IndexIconActionButtonStyle())", "Decoded save must use the shared fixed-size icon action style")
        doesNotContain(decodedSave, "ViewThatFits", "Decoded save must not maintain duplicate responsive button branches")
        doesNotContain(decodedSave, "IndexMotionLabel", "Decoded save must not keep the old text-labelled branch")
    }

    @Test func textEncryptionUsesIndexControlsAndModeBackfill() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/TextEncryptionPage.swift")
        let service = try readSource("Sources/XToolsCore/Crypto/TextEncryption.swift")
        let modernDecrypt = sourceSlice(service, from: "private static func decryptModern", to: "private static func modernMetadata")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexOptionControls.swift")

        contains(source, "@Published var algorithm = TextEncryptionService.Algorithm.aesGCM.rawValue", "Text encryption retained workspace must default to the modern authenticated algorithm")
        contains(source, "@Published var password = \"\"", "Text encryption retained workspace must not prefill an encryption key")
        contains(source, "@State private var showsPassword = false", "Text encryption key input must start hidden")
        contains(source, "IndexWorkbenchControlBar", "Text encryption controls must use the shared workbench control area")
        doesNotContain(source, "IndexOptionPicker(", "Text encryption must not expand all algorithms into a wide segmented selector")
        occurrenceCount(source, "IndexOptionMenu(", 1, "Text encryption must use one stable compact algorithm selector at every width")
        contains(source, "TextEncryptionService.Algorithm(rawValue: algorithm) ?? .aesGCM", "Text encryption invalid algorithm state must fall back to the modern authenticated algorithm")
        contains(source, "private func changeAlgorithm(to newAlgorithm: String)", "Text encryption must handle algorithm changes explicitly")
        contains(controls, "Picker(title, selection: $selection)", "The shared algorithm selector must use Picker selection semantics")
        contains(controls, ".pickerStyle(.menu)", "The shared algorithm selector must delegate menu presentation to the native menu picker")
        contains(controls, ".tag(item.0)", "Every native picker item must bind its stable algorithm ID")
        doesNotContain(source, "IndexOptionLabel(\"口令\")", "Text encryption must remove the visible password label")
        contains(source, "IndexSecureInput(", "Text encryption key input must use the shared secure input component")
        contains(source, "showsSecret: $showsPassword", "Text encryption key input must bind visibility to the shared reveal state")

        // Weak-algorithm warnings are contextual, typed, and accessibility-safe.
        doesNotContain(source, "inputWarning: selectedAlgorithm.isInsecure", "Text encryption must not attach legacy algorithm risk to the editor diagnostic")
        contains(source, "private var showsWeakAlgorithmWarning: Bool", "Text encryption must derive contextual security warning visibility explicitly")
        contains(source, "mode == \"enc\" && selectedAlgorithm.isInsecure", "Text encryption must warn only when creating new ciphertext with a weak compatibility algorithm")
        contains(source, "private var weakAlgorithmDiagnostic: IndexWorkspaceDiagnosticPayload?", "Text encryption must model the weak-algorithm warning with the shared typed diagnostic payload")
        contains(source, "private var algorithmControlGroup: some View", "Text encryption must keep the algorithm selector and contextual warning in one control group")
        contains(source, "IndexDiagnosticStatusButton(payload: weakAlgorithmDiagnostic)", "Text encryption weak-algorithm diagnostics must remain reopenable from the algorithm control group")
        doesNotContain(source, "IndexDiagnosticStatusSlot", "Text encryption must not reserve an invisible warning slot when AES-GCM is selected")
        contains(source, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Text encryption warning must use the shared diagnostic transition")
        contains(source, "@State private var weakAlgorithmPresentation = IndexWorkspaceDiagnosticPresentationState()", "Text encryption must gate weak-algorithm HUD feedback")
        doesNotContain(source, "Text(\"安全性弱\")", "Text encryption must not render persistent weak-algorithm prose beside the control")
        doesNotContain(source, "weakAlgorithmIndicator", "Text encryption must not keep a fixed optional indicator beside the algorithm selector")

        contains(source, "Binding(get: { mode }, set: { changeMode(to: $0) })", "Text encryption mode control must intercept mode changes for backfill")
        contains(source, "let nextInput = error == nil && !output.isEmpty ? output : nil", "Text encryption must only backfill current valid non-empty output")
        contains(service, "guard rounds == modernPBKDF2Rounds else { throw Error.invalidFormat }", "AES-GCM v1 must reject non-contract rounds")
        appearsBefore(modernDecrypt, "guard rounds == modernPBKDF2Rounds else { throw Error.invalidFormat }", "let keyBytes = try pbkdf2SHA256", "AES-GCM v1 rounds must be validated before PBKDF2")
        contains(source, "IndexTextConversionWorkbench(", "Text encryption must use the shared text conversion editor workbench")
        contains(source, "Button { run() } label: { Label(primaryActionTitle, systemImage: \"play.fill\") }", "Text encryption must use an explicit primary action instead of realtime security output")
        contains(source, "inputError: error", "Text encryption errors must route into the workbench diagnostic instead of floating over the page")
        doesNotContain(source, "outputFileName:", "Text encryption must not retain the removed generic text-save capability")
        contains(source, "private func clearSensitiveState()", "Text encryption must provide one clear path for sensitive visible state")
        contains(source, "password = \"\"", "Text encryption clear must remove the visible key from memory-backed UI state")
        contains(source, "showsPassword = false", "Text encryption clear must reset key visibility to hidden")
        doesNotContain(source, "IndexWarning(", "Text encryption must not show algorithm warnings as inline rows")
        doesNotContain(source, ".indexFloatingError(error)", "Text encryption errors must not use the old floating-error API")
    }

    @Test func securityTransformPagesUseSharedWorkbenchWithIntentionalExecutionPolicies() throws {
        let textEncryption = try readSource("Sources/XTools/ToolPages/Crypto/TextEncryptionPage.swift")
        let stringObfuscator = try readSource("Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift")

        contains(textEncryption, "IndexTextConversionWorkbench(", "Text encryption must delegate input/output panes to the shared workbench")
        contains(stringObfuscator, "IndexTextConversionWorkbench(", "String obfuscator must delegate input/output panes to the shared workbench")
        contains(textEncryption, ".keyboardShortcut(.return, modifiers: .command)", "Text encryption primary action must support Cmd-Enter")
        doesNotContain(stringObfuscator, ".keyboardShortcut(.return, modifiers: .command)", "String obfuscator must not retain a shortcut for a removed explicit action")
        contains(textEncryption, "didSet { if !input.utf8.elementsEqual(oldValue.utf8) { clearResult() } }", "Text encryption input edits must invalidate when encrypted bytes change, including canonically equivalent Unicode")
        contains(textEncryption, "didSet { if !password.utf8.elementsEqual(oldValue.utf8) { clearResult() } }", "Text encryption key edits must invalidate when password bytes change, including canonically equivalent Unicode")
        contains(textEncryption, "private let execution = SupersedingExecutionSession(cancelInFlight: true)", "Text encryption must share the background latest-wins execution gate")
        contains(textEncryption, "execution.schedule(operation:", "Text encryption must run only after an explicit action on the shared background executor")
        doesNotContain(textEncryption, ".onChange(of: input) { _ in clearResult() }", "Late SwiftUI input callbacks must not clear a newer completed run")
        doesNotContain(textEncryption, ".onChange(of: password) { _ in clearResult() }", "Late SwiftUI password callbacks must not clear a newer completed run")
        contains(stringObfuscator, "guard request.inputByteCount > synchronousInputByteLimit else", "String masking small input edits must project a fresh output immediately")
        contains(stringObfuscator, "preferences.set(keepFirst", "String masking parameter edits must retain the validated recipe")
        doesNotContain(stringObfuscator, "outputFileName:", "String masking must not retain the removed generic text-save capability")
        contains(textEncryption, "workspaceSemantic: .securityTransformWorkspace", "Text encryption must use the security-transform workbench semantic")
        contains(stringObfuscator, "workspaceSemantic: .securityTransformWorkspace", "String obfuscator must use the security-transform workbench semantic")
        doesNotContain(textEncryption, ".onChange(of: input) { _ in run() }", "Text encryption must not regenerate output on every input keystroke")
        doesNotContain(textEncryption, ".onChange(of: password) { _ in run() }", "Text encryption must not regenerate output on every key keystroke")
        doesNotContain(stringObfuscator, "private var output: String", "String obfuscator output must be stored result state, not a recomputed body property")

        // Sensitive values must never persist across launches.
        for (name, source) in [("Text encryption", textEncryption), ("String obfuscator", stringObfuscator)] {
            doesNotContain(source, "@AppStorage", "\(name) must not persist sensitive values")
            doesNotContain(source, "SceneStorage", "\(name) must not persist sensitive values")
            doesNotContain(source, "UserDefaults", "\(name) must not persist sensitive values")
        }
    }

    @Test func securityTransformToolsUseWorkbenchControlAreaAndWrapping() throws {
        let sharedComponents = try readSharedBagComponents()
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let scrollGeometry = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextScrollGeometry.swift")
        let textEncryption = try readSource("Sources/XTools/ToolPages/Crypto/TextEncryptionPage.swift")
        let stringObfuscator = try readSource("Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift")

        contains(sharedComponents, "struct IndexWorkbenchControlBar", "Text conversion workbench pages must have a shared responsive control area")
        contains(sharedComponents, "var semanticLineBreakMode: NSLineBreakMode", "IO pair inputs and outputs must take wrapping behavior from one workspace semantic adapter")
        contains(sharedComponents, "wrapsLongTokensToAvailableWidth ? .byCharWrapping : .byWordWrapping", "IO pair inputs and outputs must take wrapping behavior from the workspace semantic contract")
        contains(sharedComponents, "scrollsInternally: behavior.outputScrollsInternally", "Long-single-line wrapping must preserve semantic fixed/internal vertical scroll ownership")

        // Long single-line secrets wrap; they never get horizontal scroll or clipped insets.
        contains(textComponents, "scrollView.hasHorizontalScroller = false", "Text inputs must not expose horizontal scrolling for long single lines")
        contains(textComponents, "textView.isHorizontallyResizable = false", "Text inputs must stay constrained to the panel width")
        contains(textComponents, "let scrollView = IndexTextAreaScrollView(frame: .zero)", "Text inputs must use the geometry-synchronizing scroll view")
        contains(textComponents, "scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)", "Text inputs must prevent hidden horizontal clip scrolling when AppKit reveals the insertion point")
        contains(scrollGeometry, "final class IndexLeadingLockedClipView: NSClipView", "Text inputs must define a clip view that locks horizontal origin while preserving vertical scrolling")
        contains(textComponents, "textContainer.widthTracksTextView = false", "Text inputs must not wrap against the full text-view bounds when insets are present")
        contains(scrollGeometry, "IndexTextKitGeometry.wrappingContainerWidth", "Text inputs must use the shared inset-aware wrapping width")
        contains(scrollGeometry, "static let trailingWrapGuard: CGFloat = 16", "Text inputs must leave a visible trailing reading guard so edge glyphs do not hug the border")
        contains(textComponents, "nextResponder?.scrollWheel(with: event)", "Naturally growing text inputs must hand wheel scrolling to the page-level scroll owner")
        doesNotContain(textComponents, "ScrollView(.horizontal", "Output surfaces must not add horizontal scrolling to reveal long single lines")

        appearsBefore(textEncryption, "IndexWorkbenchControlBar", "IndexTextConversionWorkbench(", "Text encryption controls must remain above the input/output workbench")
        appearsBefore(stringObfuscator, "IndexWorkbenchControlBar", "IndexTextConversionWorkbench(", "String obfuscator controls must remain above the input/output workbench")
        contains(stringObfuscator, "IndexFlowLayout(spacing: 8, lineSpacing: 8)", "String obfuscator compact controls must flow instead of forcing vertical spacer gaps")
    }

    @Test func basicAuthBidirectionalCredentialsAndRevealControlsStaySafe() throws {
        let source = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        let basicSession = try readSource("Sources/XToolsCore/Web/BasicAuthWorkspaceSession.swift")

        contains(source, "ToolWorkspaceHost(key: BasicAuthToolWorkspaceModel.key)", "Basic Auth page must resolve its retained per-tool workspace")
        contains(source, "@Binding var session: BasicAuthWorkspaceSession", "Basic Auth workspace content must keep binding the Core value session")
        contains(basicSession, "mode: Mode = .generate", "Basic Auth session must preserve generation as its initial mode")
        contains(source, "IndexGenerateParseModeBar(", "Basic Auth must expose the shared generate/parse mode bar")
        contains(basicSession, "BasicAuthCodec.authorizationHeader(username: username, password: password)", "Basic Auth generation must delegate to the bidirectional Core codec")
        contains(basicSession, "BasicAuthCodec.validationIssue(username: username, password: password)", "Basic Auth session must delegate credential validation to Core")
        contains(basicSession, "BasicAuthCodec.parse(trimmed)", "Basic Auth parsing must delegate to Core")
        contains(basicSession, "public var outputDiagnostic: String?", "Basic Auth session must surface invalid generation credentials")
        contains(source, ".indexWorkspaceDiagnostic(session.outputDiagnostic)", "Basic Auth generation errors must use the shared diagnostic anchor")
        contains(source, ".indexWorkspaceDiagnostic(session.parseError)", "Basic Auth parse errors must use the shared diagnostic anchor")
        contains(source, "credentialRow(\"用户名\")", "Basic Auth username and password inputs must use the same row layout")
        contains(source, "credentialRow(\"密码\")", "Basic Auth username and password inputs must use the same row layout")
        contains(source, "IndexSecureInput(", "Basic Auth generation password must use the shared secure input")
        contains(source, "showsSecret: $showsPassword", "Basic Auth generation password must bind the shared reveal state")
        contains(source, "showsParsedPassword = false", "Basic Auth parsed password must return to hidden after input changes or clear")
        contains(source, "if showsParsedPassword", "Basic Auth parsed password copy must stay behind explicit reveal")
        contains(source, "IndexIconButton(", "Basic Auth must use shared reveal controls")
        contains(source, "在解析中打开", "Basic Auth generation must expose explicit parse transfer")
        contains(source, "用于生成", "Basic Auth parsing must expose explicit generation transfer")
        doesNotContain(source, "PendingConfirmation", "Basic Auth explicit transfers must remain direct and nonmodal")
        doesNotContain(source, ".alert(item:", "Basic Auth transfer must not interrupt the workflow with an alert")
        contains(source, "Base64 不是加密，请仅通过 HTTPS 使用", "Basic Auth must explain its transport-security boundary")
        contains(source, "IndexCopyButton(text: session.output)", "Basic Auth must keep copying the generated Authorization header")
        contains(source, "onClearAll: clearAll", "Basic Auth clear must reset generation and parsing together")
        doesNotContain(source, "localClearButton", "Basic Auth must expose one unambiguous clear action")
        doesNotContain(source, "requestClearAll", "Basic Auth clear must not require confirmation for ephemeral local form state")
        doesNotContain(source, "@AppStorage", "Basic Auth must not persist credential drafts")
        doesNotContain(source, "@SceneStorage", "Basic Auth must not persist credential drafts")
        contains(textComponents, "var allowsCopy = true", "Shared single-line inputs must expose copy control")
        contains(textComponents, "commandSelector == #selector(NSText.copy(_:)) && !allowsCopy", "Shared single-line inputs must block copy when disabled")
        contains(textComponents, ".id(secure)", "Shared single-line inputs must recreate AppKit field when secure mode changes")
    }
}
