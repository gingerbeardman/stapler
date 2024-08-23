import SwiftUI
import UniformTypeIdentifiers
import Quartz
import os

// Define an enum for the different document opening scenarios
enum DocumentOpeningScenario {
	case launchedWithDocument
	case resumedBySystem
	case openedThroughFileMenu
	case openedFromFinderWhileRunning
	case unknown
}

// Modify the AppDelegate to work with the new AppStateManager
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

class AppStateManager: ObservableObject {
	@Published var hasActiveDocument: Bool = false
	@Published var wasJustLaunched: Bool = true
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

	func launchAliases(at offsets: IndexSet) {
		for index in offsets {
			if let url = document.aliases[index].resolveURL() {
				let coordinator = NSFileCoordinator()
				var error: NSError?
				coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
					NSWorkspace.shared.open(url)
				}
				if let error = error {
					handleError(error)
				}
			}
		}
	}
	
	func showFinderInfo(at offsets: IndexSet) {
		for index in offsets {
			if let url = document.aliases[index].resolveURL() {
				let coordinator = NSFileCoordinator()
				var error: NSError?
				coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
					NSWorkspace.shared.activateFileViewerSelecting([url])
				}
				if let error = error {
					handleError(error)
				}
			}
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

class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	var previewItems: [AliasItem] = []
	var currentPreviewItemIndex: Int = 0

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

struct ContentView: View {
	@ObservedObject private var viewModel: StaplerViewModel
	@Binding var document: StaplerDocument
	@Binding var hasSelection: Bool
	@State private var selection = Set<UUID>()
	@State private var showingErrorAlert = false
	@FocusState private var isViewFocused: Bool
	private let quickLookPreviewController = QuickLookPreviewController()

	@Environment(\.appStateManager) private var appStateManager

	init(document: Binding<StaplerDocument>, hasSelection: Binding<Bool>) {
		self._document = document
		self._hasSelection = hasSelection
		self.viewModel = StaplerViewModel(document: document.wrappedValue)
	}

	var body: some View {
		VStack {
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
				.onTapGesture(count: 2) {
					toggleSelection(for: alias)
					launchAlias(alias)
				}
				.onTapGesture(count: 1) {
					toggleSelection(for: alias)
				}
			}
			.onChange(of: selection) { newValue in
				hasSelection = !newValue.isEmpty
			}
			.listStyle(InsetListStyle())
			.frame(minHeight: 200)
		}
		.frame(minWidth: 300, minHeight: 200)
		.focused($isViewFocused)
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
//		.onKeyPress(.return) {
//			launchSelected()
//			return .handled
//		}
//		.onKeyPress(.space) {
//			showQuickLook()
//			return .handled
//		}
		.onAppear {
			NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
				if event.keyCode == 36 { // Return key
					launchSelected()
				} else if event.keyCode == 49 { // Space key
					showQuickLook()
					return nil
				}
				return event
			}

			setupNotificationObservers()
			DispatchQueue.main.async {
				self.isViewFocused = true
			}
			appStateManager.hasActiveDocument = true
		}
		.onDisappear {
			updateDocument()
			removeNotificationObservers()
			appStateManager.hasActiveDocument = false
		}
		.modifier(KeyPressModifier(launchAction: launchSelected, quickLookAction: showQuickLook))
	}

	private func toggleSelection(for alias: AliasItem) {
		if selection.contains(alias.id) {
			selection.remove(alias.id)
		} else {
			selection.insert(alias.id)
		}
	}

	private func launchAlias(_ alias: AliasItem) {
		if let url = alias.resolveURL() {
			defer {
				url.stopAccessingSecurityScopedResource()
			}
			
			let coordinator = NSFileCoordinator()
			var error: NSError?
			coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
				NSWorkspace.shared.open(url)
			}
			if let error = error {
				viewModel.handleError(error)
			}
		}
	}

	// Define a custom modifier to handle key presses
	struct KeyPressModifier: ViewModifier {
		let launchAction: () -> Void
		let quickLookAction: () -> Void
		
		func body(content: Content) -> some View {
			if #available(macOS 14.0, *) {
				content
					.onKeyPress(.return) {
						launchAction()
						return .handled
					}
					.onKeyPress(.space) {
						quickLookAction()
						return .handled
					}
			} else {
				content
			}
		}
	}

	private func showQuickLook() {
		guard let selectedID = selection.first,
			  let selectedIndex = viewModel.document.aliases.firstIndex(where: { $0.id == selectedID }) else {
			return
		}

		quickLookPreviewController.previewItems = viewModel.document.aliases
		quickLookPreviewController.currentPreviewItemIndex = selectedIndex

		if let panel = QLPreviewPanel.shared() {
			panel.dataSource = quickLookPreviewController
			panel.delegate = quickLookPreviewController
			panel.currentPreviewItemIndex = selectedIndex
			panel.makeKeyAndOrderFront(nil)
		}
	}

	private func setupNotificationObservers() {
		NotificationCenter.default.addObserver(forName: .addAlias, object: nil, queue: .main) { _ in
			if viewModel.addAliasesViaFileSelector() {
				updateDocument()
			}
		}
		NotificationCenter.default.addObserver(forName: .removeAlias, object: nil, queue: .main) { _ in
			removeSelectedAliases()
		}
		NotificationCenter.default.addObserver(forName: .getInfo, object: nil, queue: .main) { _ in
			showFinderInfo()
		}
		NotificationCenter.default.addObserver(forName: .launchAlias, object: nil, queue: .main) { _ in
			launchSelected()
		}
		NotificationCenter.default.addObserver(forName: .quickLookAlias, object: nil, queue: .main) { _ in
			showQuickLook()
		}
	}
	
	private func removeNotificationObservers() {
		NotificationCenter.default.removeObserver(self)
	}

	private func removeSelectedAliases() {
		let indicesToRemove = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
		if indicesToRemove.count != 0 {
			viewModel.removeAliases(at: IndexSet(indicesToRemove))
			selection.removeAll()
			updateDocument()
		}
	}
	
	private func launchSelected() {
		guard !NSEvent.modifierFlags.contains(.command) else { return }

		if selection.isEmpty {
			// If no items are selected, launch all items
			viewModel.launchAliases(at: IndexSet(integersIn: 0..<viewModel.document.aliases.count))
		} else {
			// Launch only the selected items
			let indicesToLaunch = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
			viewModel.launchAliases(at: IndexSet(indicesToLaunch))
		}
	}

	private func showFinderInfo() {
		let indicesToShow = viewModel.document.aliases.indices.filter { selection.contains(viewModel.document.aliases[$0].id) }
		viewModel.showFinderInfo(at: IndexSet(indicesToShow))
	}
	
	private func updateDocument() {
		do {
			let encoder = JSONEncoder()
			let data = try encoder.encode(viewModel.document.aliases)
			if String(data: data, encoding: .utf8) != nil {
				document.aliases = viewModel.document.aliases
				viewModel.hasUnsavedChanges = false
				viewModel.markDocumentAsEdited()
			} else {
				throw NSError(domain: "StaplerApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode document data"])
			}
		} catch {
			viewModel.handleError(error)
		}
	}
}

@main
struct StaplerApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@StateObject private var appStateManager = AppStateManager()
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "info")
	@State private var hasSelection: Bool = false
	@State private var showNewDocumentSelector: Bool = UserDefaults.standard.bool(forKey: "ShowNewDocumentSelector")

	// Add a computed property to get the delay from UserDefaults
	private var commandKeyDelay: Double {
		UserDefaults.standard.double(forKey: "CommandKeyDelay") / 1000.0 // Convert milliseconds to seconds
	}

	func handleDocumentOpening(_ url: URL) {
		let scenario = determineOpeningScenario()

		switch scenario {
		case .launchedWithDocument:
			logger.info("Document Opening Scenario: launchedWithDocument")
			handleLaunchedWithDocument(url)
		case .resumedBySystem:
			logger.info("Document Opening Scenario: resumedBySystem")
			// Handle resumed by system scenario
			break
		case .openedThroughFileMenu:
			logger.info("Document Opening Scenario: openedThroughFileMenu")
			// Handle opened through file menu scenario
			break
		case .openedFromFinderWhileRunning:
			logger.info("Document Opening Scenario: openedFromFinderWhileRunning")
			// Handle opened through Finder whilst running scenario
			handleOpenedFromFinderWhileRunning(url)
		case .unknown:
			logger.info("Document Opening Scenario: unknown")
			// Handle unknown scenarios
			break
		}
		
		// Reset the wasJustLaunched flag
		appStateManager.wasJustLaunched = false
	}

	private func determineOpeningScenario() -> DocumentOpeningScenario {
		let currentEvent = NSApplication.shared.currentEvent
		let isOpenedFromFinder = currentEvent != nil && currentEvent?.type == .appKitDefined && currentEvent?.subtype.rawValue == NSEvent.EventSubtype.applicationActivated.rawValue
		
		if appStateManager.wasJustLaunched && isOpenedFromFinder {
			return .launchedWithDocument
		} else if isOpenedFromFinder && NSApp.isActive {
			return .openedFromFinderWhileRunning
		} else if NSApp.isActive {
			return .openedThroughFileMenu
		} else if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)) {
			// Check if the app was resumed by the system (macOS 10.15+)
			return .resumedBySystem
		} else {
			return .unknown
		}
	}

	private func handleLaunchedWithDocument(_ url: URL) {
		DispatchQueue.main.asyncAfter(deadline: .now() + commandKeyDelay) {
			let commandKeyPressed = NSEvent.modifierFlags.contains(.command)
			
			if !commandKeyPressed {
				do {
					guard url.startAccessingSecurityScopedResource() else {
						logger.error("Failed to access security-scoped resource")
						return
					}
					defer { url.stopAccessingSecurityScopedResource() }
					
					let document = try StaplerDocument(contentsOf: url)
					let viewModel = StaplerViewModel(document: document)
					viewModel.launchAliases(at: IndexSet(integersIn: 0..<document.aliases.count))
					
					// Close the document
					if let windowController = NSDocumentController.shared.document(for: url)?.windowControllers.first {
						windowController.close()
					}
					
					// If this was the only document and the app was just launched, quit the app
					if NSDocumentController.shared.documents.count == 1 {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
							NSApp.terminate(nil)
						}
					}
				} catch {
					logger.error("Error handling document opening: \(error.localizedDescription)")
				}
			}
		}
	}

	private func handleOpenedFromFinderWhileRunning(_ url: URL) {
		DispatchQueue.main.asyncAfter(deadline: .now() + commandKeyDelay) {
			let commandKeyPressed = NSEvent.modifierFlags.contains(.command)
			
			if !commandKeyPressed {
				do {
					guard url.startAccessingSecurityScopedResource() else {
						logger.error("Failed to access security-scoped resource")
						return
					}
					defer { url.stopAccessingSecurityScopedResource() }
					
					let document = try StaplerDocument(contentsOf: url)
					let viewModel = StaplerViewModel(document: document)
					viewModel.launchAliases(at: IndexSet(integersIn: 0..<document.aliases.count))
					
					// Close the document
					if let windowController = NSDocumentController.shared.document(for: url)?.windowControllers.first {
						windowController.close()
					}
				} catch {
					logger.error("Error handling document opening: \(error.localizedDescription)")
				}
			}
		}
	}

	var body: some Scene {
		DocumentGroup(newDocument: StaplerDocument()) { file in
			ContentView(document: file.$document, hasSelection: $hasSelection)
				.modifier(AppStateManagerModifier(appStateManager: appStateManager))
				.onAppear {
					appStateManager.hasActiveDocument = true
					if let url = file.fileURL {
						handleDocumentOpening(url)
					}
				}
				.onDisappear {
					appStateManager.hasActiveDocument = false
				}
		}
		.commands {
			TextEditingCommands()
			
			CommandMenu("Items") {
				Button("Add…") {
					NotificationCenter.default.post(name: .addAlias, object: nil)
				}
				.keyboardShortcut(.return, modifiers: .command)
				.disabled(!appStateManager.hasActiveDocument)
				
				Button("Remove") {
					NotificationCenter.default.post(name: .removeAlias, object: nil)
				}
				.keyboardShortcut(.delete, modifiers: [])
				.disabled(!appStateManager.hasActiveDocument || !hasSelection)
				
				Divider()
				
				Button("Quick Look") {
					NotificationCenter.default.post(name: .quickLookAlias, object: nil)
				}
				.keyboardShortcut(.space, modifiers: [])
				.disabled(!appStateManager.hasActiveDocument || !hasSelection)
				
				Button("Reveal in Finder") {
					NotificationCenter.default.post(name: .getInfo, object: nil)
				}
				.keyboardShortcut("r", modifiers: .command)
				.disabled(!appStateManager.hasActiveDocument || !hasSelection)
				
				Divider()
				
				Button("Launch") {
					NotificationCenter.default.post(name: .launchAlias, object: nil)
				}
				.keyboardShortcut(.return, modifiers: [])
				.disabled(!appStateManager.hasActiveDocument)
			}
			// Add the About menu item with linked credits
			CommandGroup(replacing: .appInfo) {
				Button("About Stapler") {
					let creditString = "Inspired by: Stapler (1992) & LaunchList (2009)\n\ngithub.com/gingerbeardman/stapler"
					let attributedString = NSMutableAttributedString(string: creditString)
					
					// Apply the base attributes to the entire string
					let baseAttributes: [NSAttributedString.Key: Any] = [
						.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
						.foregroundColor: NSColor.secondaryLabelColor
					]
					attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: creditString.count))
					
					// Find the range of the text and apply the link attribute
					if let range = creditString.range(of: "github.com/gingerbeardman/stapler") {
						let nsRange = NSRange(range, in: creditString)
						attributedString.addAttribute(.link, value: "https://github.com/gingerbeardman/stapler", range: nsRange)
					}
					
					NSApp.orderFrontStandardAboutPanel(options: [
						NSApplication.AboutPanelOptionKey.credits: attributedString
					])
				}
			}
			// Replace the default Help menu
			CommandGroup(replacing: .help) {
				Button("Stapler Help") {
					if let url = URL(string: "https://github.com/gingerbeardman/stapler/blob/main/README.md") {
						NSWorkspace.shared.open(url)
					}
				}
			}
			// Add toggle in Stapler menu
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

extension EnvironmentValues {
	var appStateManager: AppStateManager {
		get { self[AppStateManagerKey.self] }
		set { self[AppStateManagerKey.self] = newValue }
	}
}

extension Notification.Name {
	static let addAlias = Notification.Name("addAlias")
	static let removeAlias = Notification.Name("removeAlias")
	static let getInfo = Notification.Name("getInfo")
	static let launchAlias = Notification.Name("launchAlias")
	static let quickLookAlias = Notification.Name("quickLookAlias")
}

extension Scene {
	func disableTextEditingCommands() -> some Scene {
		self.commands {
			TextEditingCommands()
		}
	}
}

extension StaplerViewModel {
	func markDocumentAsEdited() {
		if let document = NSDocumentController.shared.document(for: document.fileURL ?? URL(fileURLWithPath: "/")) {
			document.updateChangeCount(.changeDone)
		}
	}
}

extension UserDefaults {
	@objc dynamic var commandKeyDelay: Int {
		get { integer(forKey: "CommandKeyDelay") }
		set { set(newValue, forKey: "CommandKeyDelay") }
	}
}

extension UTType {
	static var staplerDocument: UTType {
		UTType(exportedAs: "com.gingerbeardman.Stapler.stapled")
	}
}

private struct AppStateManagerKey: EnvironmentKey {
	static let defaultValue = AppStateManager()
}

struct AppStateManagerModifier: ViewModifier {
	let appStateManager: AppStateManager
	
	func body(content: Content) -> some View {
		#if os(macOS)
		if #available(macOS 14.0, *) {
			return AnyView(content.environmentObject(appStateManager))
		} else {
			return AnyView(content.environment(\.appStateManager, appStateManager))
		}
		#else
		return AnyView(content.environment(\.appStateManager, appStateManager))
		#endif
	}
}

//#Preview {
//	ContentView(document: .constant(StaplerDocument()))
//		.environmentObject(AppStateManager())
//}
