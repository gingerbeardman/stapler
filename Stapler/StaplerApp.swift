import SwiftUI
import UniformTypeIdentifiers
import Quartz
import os

class AppDelegate: NSObject, NSApplicationDelegate {
	func setupDefaultCommandKeyDelay() {
		if UserDefaults.standard.object(forKey: "CommandKeyDelay") == nil {
			UserDefaults.standard.set(0, forKey: "CommandKeyDelay") // Default wait 0ms
		}
	}
	
	func setupDefaultShowNewDocumentSelector() {
		if UserDefaults.standard.object(forKey: "ShowNewDocumentSelector") == nil {
			UserDefaults.standard.set(true, forKey: "ShowNewDocumentSelector") // Default to Show
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		setupDefaultCommandKeyDelay()
		setupDefaultShowNewDocumentSelector()
		
		// Check if we should show the new document selector and if no documents are already open
		if !UserDefaults.standard.bool(forKey: "ShowNewDocumentSelector") && NSDocumentController.shared.documents.isEmpty {
			// If not, create a new blank document
			DispatchQueue.main.async {
				NSDocumentController.shared.newDocument(nil)
			}
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		// Handle opening of documents from Finder
		for url in urls {
			NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { (document, documentWasAlreadyOpen, error) in
				if let error = error {
					print("Error opening document: \(error.localizedDescription)")
				}
			}
		}
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		let unsavedDocuments = NSDocumentController.shared.documents.filter { $0.isDocumentEdited }
		
		if unsavedDocuments.isEmpty {
			return .terminateNow
		}
		
		for document in unsavedDocuments {
			let panel = NSSavePanel()
			panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "Untitled.stapled"
			
			let response = panel.runModal()
			
			if response == .OK {
				if let url = panel.url {
					do {
						try document.write(to: url, ofType: UTType.staplerDocument.identifier)
					} catch {
						let alert = NSAlert()
						alert.messageText = "Error Saving Document"
						alert.informativeText = "Failed to save the document: \(error.localizedDescription)"
						alert.addButton(withTitle: "OK")
						alert.runModal()
						return .terminateCancel
					}
				}
			} else {
				return .terminateCancel
			}
		}
		
		return .terminateNow
	}
}

struct DocumentActions {
	let addAlias: () -> Void
	let removeAlias: () -> Void
	let launchAlias: () -> Void
	let quickLook: () -> Void
	let revealInFinder: () -> Void
	let hasSelection: Bool
}

private struct FocusedDocumentActionsKey: FocusedValueKey {
	typealias Value = DocumentActions
}

extension FocusedValues {
	var documentActions: DocumentActions? {
		get { self[FocusedDocumentActionsKey.self] }
		set { self[FocusedDocumentActionsKey.self] = newValue }
	}
}

struct AliasItem: Identifiable, Codable, Hashable {
	let id: UUID
	let bookmarkData: Data
	
	var name: String {
		resolveURL()?.lastPathComponent ?? "Unknown"
	}
	
	var icon: NSImage {
		if let url = resolveURL() {
			return NSWorkspace.shared.icon(forFile: url.path)
		}
		return NSImage(named: NSImage.cautionName) ?? NSImage()
	}
	
	init(id: UUID = UUID(), url: URL) throws {
		self.id = id
		self.bookmarkData = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
	}
	
	func resolveURL() -> URL? {
		var isStale = false
		do {
			let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
			if isStale {
				// If the bookmark is stale, we need to create a new one
				_ = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
				if let aliasItem = try? AliasItem(id: id, url: url) {
					return aliasItem.resolveURL()
				}
			}
			if !url.startAccessingSecurityScopedResource() {
				print("Failed to access security scoped resource")
				return nil
			}
			return url
		} catch {
			print("Error resolving bookmark: \(error)")
			return nil
		}
	}
}

struct StaplerDocument: FileDocument, Equatable {
	static var readableContentTypes: [UTType] { [.staplerDocument] }
	static var writableContentTypes: [UTType] { [.staplerDocument] }

	var fileURL: URL?
	var aliases: [AliasItem]
	
	init() {
		self.aliases = []
		self.fileURL = nil
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let decodedData = try JSONDecoder().decode(StaplerDocumentData.self, from: data)
		self.aliases = decodedData.aliases
		self.fileURL = configuration.file.filename.flatMap { URL(fileURLWithPath: $0) }
	}
	
	init(contentsOf url: URL) throws {
		let data = try Data(contentsOf: url)
		let decodedData = try JSONDecoder().decode(StaplerDocumentData.self, from: data)
		self.aliases = decodedData.aliases
		self.fileURL = url
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let documentData = StaplerDocumentData(aliases: aliases)
		let data = try JSONEncoder().encode(documentData)
		let wrapper = FileWrapper(regularFileWithContents: data)
		wrapper.preferredFilename = configuration.existingFile?.filename ?? "Untitled.stapled"
		return wrapper
	}

	static func == (lhs: StaplerDocument, rhs: StaplerDocument) -> Bool {
		lhs.aliases == rhs.aliases
	}
}

struct StaplerDocumentData: Codable {
	let aliases: [AliasItem]
}

class StaplerViewModel: ObservableObject {
	@Published var document: StaplerDocument
	@Published var errorMessage: String?
	@Published var hasUnsavedChanges: Bool = false

	init(document: StaplerDocument) {
		self.document = document
	}
	
	func addAlias(_ alias: AliasItem) {
		document.aliases.append(alias)
		sortAliases()
		hasUnsavedChanges = true
		objectWillChange.send()
	}

	func removeAliases(at offsets: IndexSet) {
		document.aliases.remove(atOffsets: offsets)
		sortAliases()
		hasUnsavedChanges = true
		objectWillChange.send()
	}

	private func sortAliases() {
		document.aliases.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	private func coordinateAliases(at offsets: IndexSet, action: @escaping (URL) -> Void) {
		for index in offsets {
			if let url = document.aliases[index].resolveURL() {
				let coordinator = NSFileCoordinator()
				var error: NSError?
				coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
					action(url)
				}
				if let error = error {
					handleError(error)
				}
			}
		}
	}

	func launchAliases(at offsets: IndexSet) {
		coordinateAliases(at: offsets) { url in
			NSWorkspace.shared.open(url)
		}
	}

	func showFinderInfo(at offsets: IndexSet) {
		coordinateAliases(at: offsets) { url in
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}
	}
	
	func updateFromDocument(_ newDocument: StaplerDocument) {
		self.document = newDocument
		hasUnsavedChanges = false
		objectWillChange.send()
	}
	
	func addAliasesViaFileSelector() -> Bool {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		
		if panel.runModal() == .OK {
			var addedAliases = false
			for url in panel.urls {
				do {
					let newAlias = try AliasItem(url: url)
					addAlias(newAlias)
					addedAliases = true
				} catch {
					handleError(error)
				}
			}
			
			if addedAliases {
				hasUnsavedChanges = true
				objectWillChange.send()
				return true
			}
		}
		return false
	}
	
	func handleError(_ error: Error) {
		DispatchQueue.main.async {
			self.errorMessage = error.localizedDescription
		}
	}
}

class QuickLookResponder: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	var previewItems: [AliasItem] = []

	override var acceptsFirstResponder: Bool { true }

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
		return true
	}

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = self
		panel.delegate = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = nil
		panel.delegate = nil
	}

	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
		return previewItems.count
	}

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		guard let url = previewItems[index].resolveURL() else {
			return nil
		}
		let coordinator = NSFileCoordinator()
		var previewItem: QLPreviewItem?
		var error: NSError?
		coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
			previewItem = url as QLPreviewItem
		}
		if let error = error {
			print("StaplerApp: QuickLookPreviewController: Error coordinating file access: \(error)")
		}
		return previewItem
	}

	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		if event.type == .keyDown {
			if event.keyCode == 49 { // Space key
				panel.orderOut(nil)
				return true
			}
		}
		return false
	}
}

struct QuickLookBridge: NSViewRepresentable {
	let responder: QuickLookResponder

	func makeNSView(context: Context) -> QuickLookResponder {
		return responder
	}

	func updateNSView(_ nsView: QuickLookResponder, context: Context) {}
}

struct ContentView: View {
	@ObservedObject private var viewModel: StaplerViewModel
	@Binding var document: StaplerDocument
	@State private var selection = Set<UUID>()
	@State private var showingErrorAlert = false
	@State private var eventMonitor: Any?
	@FocusState private var isViewFocused: Bool
	private let quickLookResponder = QuickLookResponder()

	init(document: Binding<StaplerDocument>) {
		self._document = document
		self.viewModel = StaplerViewModel(document: document.wrappedValue)
	}

	var body: some View {
		VStack {
			ZStack {
				List(viewModel.document.aliases, id: \.id, selection: $selection) { alias in
					HStack {
						Image(nsImage: alias.icon)
							.resizable()
							.frame(width: 20, height: 20)
						Text(alias.name)
						Spacer()
					}
					.padding(.vertical, 3)
					.contentShape(Rectangle())
					.gesture(TapGesture(count: 2).onEnded {
						launchAliasItem(alias)
					})
					.contextMenu {
						Button("Launch") {
							launchAliasItem(alias)
						}
						Button("Quick Look") {
							selection = [alias.id]
							showQuickLook()
						}
						Button("Reveal in Finder") {
							if let url = alias.resolveURL() {
								NSWorkspace.shared.activateFileViewerSelecting([url])
							}
						}
						Divider()
						Button("Remove") {
							if let index = viewModel.document.aliases.firstIndex(where: { $0.id == alias.id }) {
								viewModel.removeAliases(at: IndexSet(integer: index))
								selection.remove(alias.id)
								updateDocument()
							}
						}
					}
				}
				.listStyle(InsetListStyle())
				.frame(minHeight: 200)

				if viewModel.document.aliases.isEmpty {
					VStack(spacing: 8) {
						Text("No Items")
							.font(.headline)
							.foregroundColor(.secondary)
						Text("Use Items \u{2192} Add or drag files here")
							.font(.subheadline)
							.foregroundColor(.secondary)
					}
				}
			}
		}
		.background(QuickLookBridge(responder: quickLookResponder).frame(width: 0, height: 0))
		.frame(minWidth: 300, minHeight: 200)
		.focused($isViewFocused)
		.focusedValue(\.documentActions, DocumentActions(
			addAlias: {
				if viewModel.addAliasesViaFileSelector() {
					updateDocument()
				}
			},
			removeAlias: { removeSelectedAliases() },
			launchAlias: { launchSelected() },
			quickLook: { showQuickLook() },
			revealInFinder: { showFinderInfo() },
			hasSelection: !selection.isEmpty
		))
		.onDrop(of: [.fileURL], isTargeted: nil) { providers in
			let wasEmpty = viewModel.document.aliases.isEmpty
			for provider in providers {
				_ = provider.loadObject(ofClass: URL.self) { url, error in
					if let error = error {
						viewModel.handleError(error)
					} else if let url = url {
						DispatchQueue.main.async {
							do {
								let newAlias = try AliasItem(url: url)
								viewModel.addAlias(newAlias)
								if wasEmpty {
									updateDocument()
								} else {
									document.aliases = viewModel.document.aliases
								}
							} catch {
								viewModel.handleError(error)
							}
						}
					}
				}
			}
			return true
		}
		.alert(isPresented: $showingErrorAlert) {
			Alert(
				title: Text("Error"),
				message: Text(viewModel.errorMessage ?? "An unknown error occurred."),
				dismissButton: .default(Text("OK"))
			)
		}
		.onChange(of: viewModel.errorMessage) { newValue in
			showingErrorAlert = newValue != nil
		}
		.onChange(of: document) { newValue in
			viewModel.updateFromDocument(newValue)
		}
		.onAppear {
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
				if event.keyCode == 36 { // Return key
					launchSelected()
				} else if event.keyCode == 49 { // Space key
					showQuickLook()
					return nil
				}
				return event
			}
			DispatchQueue.main.async {
				self.isViewFocused = true
			}
		}
		.onDisappear {
			updateDocument()
			if let monitor = eventMonitor {
				NSEvent.removeMonitor(monitor)
				eventMonitor = nil
			}
		}
	}

	private func launchAliasItem(_ alias: AliasItem) {
		if let index = viewModel.document.aliases.firstIndex(where: { $0.id == alias.id }) {
			viewModel.launchAliases(at: IndexSet(integer: index))
		}
	}

	private func showQuickLook() {
		guard let selectedID = selection.first,
			  let selectedIndex = viewModel.document.aliases.firstIndex(where: { $0.id == selectedID }) else {
			return
		}

		quickLookResponder.previewItems = viewModel.document.aliases
		if let panel = QLPreviewPanel.shared() {
			panel.dataSource = quickLookResponder
			panel.delegate = quickLookResponder
			panel.currentPreviewItemIndex = selectedIndex
			panel.makeKeyAndOrderFront(nil)
		}
	}

	private func removeSelectedAliases() {
		let indicesToRemove = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
		if !indicesToRemove.isEmpty {
			viewModel.removeAliases(at: IndexSet(indicesToRemove))
			selection.removeAll()
			updateDocument()
		}
	}

	private func launchSelected() {
		guard !NSEvent.modifierFlags.contains(.command) else { return }

		if selection.isEmpty {
			viewModel.launchAliases(at: IndexSet(integersIn: 0..<viewModel.document.aliases.count))
		} else {
			let indicesToLaunch = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
			viewModel.launchAliases(at: IndexSet(indicesToLaunch))
		}
	}

	private func showFinderInfo() {
		let indicesToShow = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
		viewModel.showFinderInfo(at: IndexSet(indicesToShow))
	}

	private func updateDocument() {
		document.aliases = viewModel.document.aliases
		viewModel.hasUnsavedChanges = false
		viewModel.markDocumentAsEdited()
	}
}

@main
struct StaplerApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@FocusedValue(\.documentActions) private var actions
	@State private var wasJustLaunched = true
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "info")
	@State private var showNewDocumentSelector: Bool = UserDefaults.standard.bool(forKey: "ShowNewDocumentSelector")

	// Add a computed property to get the delay from UserDefaults
	private var commandKeyDelay: Double {
		UserDefaults.standard.double(forKey: "CommandKeyDelay") / 1000.0 // Convert milliseconds to seconds
	}

	func handleDocumentOpening(_ url: URL) {
		let currentEvent = NSApplication.shared.currentEvent
		let isOpenedFromFinder = currentEvent?.type == .appKitDefined
			&& currentEvent?.subtype.rawValue == NSEvent.EventSubtype.applicationActivated.rawValue

		defer { wasJustLaunched = false }

		guard isOpenedFromFinder else { return }

		let shouldQuitIfOnly = wasJustLaunched
		DispatchQueue.main.asyncAfter(deadline: .now() + commandKeyDelay) {
			guard !NSEvent.modifierFlags.contains(.command) else { return }

			do {
				guard url.startAccessingSecurityScopedResource() else {
					logger.error("Failed to access security-scoped resource")
					return
				}
				defer { url.stopAccessingSecurityScopedResource() }

				let document = try StaplerDocument(contentsOf: url)
				let viewModel = StaplerViewModel(document: document)
				viewModel.launchAliases(at: IndexSet(integersIn: 0..<document.aliases.count))

				if let windowController = NSDocumentController.shared.document(for: url)?.windowControllers.first {
					windowController.close()
				}

				if shouldQuitIfOnly && NSDocumentController.shared.documents.count == 1 {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						NSApp.terminate(nil)
					}
				}
			} catch {
				logger.error("Error handling document opening: \(error.localizedDescription)")
			}
		}
	}

	var body: some Scene {
		DocumentGroup(newDocument: StaplerDocument()) { file in
			ContentView(document: file.$document)
				.onAppear {
					if let url = file.fileURL {
						handleDocumentOpening(url)
					}
				}
		}
		.commands {
			TextEditingCommands()

			CommandMenu("Items") {
				Button("Add…") {
					actions?.addAlias()
				}
				.keyboardShortcut(.return, modifiers: .command)
				.disabled(actions == nil)

				Button("Remove") {
					actions?.removeAlias()
				}
				.keyboardShortcut(.delete, modifiers: [])
				.disabled(actions == nil || !(actions?.hasSelection ?? false))

				Divider()

				Button("Quick Look") {
					actions?.quickLook()
				}
				.keyboardShortcut(.space, modifiers: [])
				.disabled(actions == nil || !(actions?.hasSelection ?? false))

				Button("Reveal in Finder") {
					actions?.revealInFinder()
				}
				.keyboardShortcut("r", modifiers: .command)
				.disabled(actions == nil || !(actions?.hasSelection ?? false))

				Divider()

				Button("Launch") {
					actions?.launchAlias()
				}
				.keyboardShortcut(.return, modifiers: [])
				.disabled(actions == nil)
			}
			CommandGroup(replacing: .help) {
				Button("Stapler Help") {
					if let url = URL(string: "https://github.com/gingerbeardman/stapler/blob/main/README.md") {
						NSWorkspace.shared.open(url)
					}
				}
			}
			CommandGroup(after: .appInfo) {
				Divider()
				Toggle("Show New Document Selector on Launch", isOn: $showNewDocumentSelector)
					.onChange(of: showNewDocumentSelector) { newValue in
						UserDefaults.standard.set(newValue, forKey: "ShowNewDocumentSelector")
					}
			}
		}
		.handlesExternalEvents(matching: [UTType.staplerDocument.identifier])
	}
}

extension StaplerViewModel {
	func markDocumentAsEdited() {
		if let document = NSDocumentController.shared.document(for: document.fileURL ?? URL(fileURLWithPath: "/")) {
			document.updateChangeCount(.changeDone)
		}
	}
}

extension UTType {
	static var staplerDocument: UTType {
		UTType(exportedAs: "com.gingerbeardman.Stapler.stapled")
	}
}
