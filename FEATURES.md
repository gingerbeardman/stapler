# Stapler Features

## Document Management

- **Custom Document Format**: Uses `.stapled` file extension with JSON-based storage
- **Standard File Operations**: New, Open, Save, Save As, Close, Revert
- **Open Recent**: Quick access to recently opened documents
- **Auto-Save**: Automatic change tracking with save prompts on quit
- **Undo/Redo**: Standard macOS document editing support

## Alias Management

- **Add Files/Folders/Apps**: Add any item to a document via file picker or drag-and-drop
- **Security-Scoped Bookmarks**: Securely stores references to files without copying them
- **Automatic Sorting**: Items are sorted alphabetically (case-insensitive)
- **File Icons**: Displays the actual file/folder icon for each item
- **Multi-Selection**: Select multiple items for batch operations

## Item Operations

- **Launch Items**: Open files with their default applications, launch apps, or open folders in Finder
- **Batch Launch**: Launch all items in a document, or only selected items
- **Quick Look**: Preview selected items using macOS Quick Look (Space bar)
- **Reveal in Finder**: Show selected item's location in Finder
- **Remove Items**: Delete selected items from the document

## Auto-Launch Behavior

- **Document Auto-Launch**: Opening a `.stapled` file automatically launches all contained items
- **Edit Mode Override**: Hold Command key while opening to prevent auto-launch and edit instead
- **Smart App Closing**: App closes after auto-launch if it wasn't already running
- **Configurable Delay**: Adjustable delay before auto-launch (CommandKeyDelay setting)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Return | Add items |
| Backspace | Remove selected items |
| Space | Quick Look preview |
| Cmd+R | Reveal in Finder |
| Return | Launch items |
| Double-click | Launch item |

## Drag and Drop

- **Drop Files**: Drag files, folders, or apps directly into the document list
- **Multiple Items**: Drop several items at once
- **Automatic Conversion**: Dropped items are converted to aliases

## Preferences

- **Show New Document Selector**: Toggle whether to show document selector on app launch

## Security

- **Sandboxed Application**: Runs with macOS sandbox protection
- **Security-Scoped Resources**: Proper file access permissions
- **Read-Only Bookmarks**: Files are referenced, not modified
- **Signed Application**: Digitally signed for security

## macOS Integration

- **Finder Integration**: Open `.stapled` files directly from Finder
- **Quick Look Panel**: Native macOS preview system
- **NSWorkspace**: Proper file launching and icon retrieval
- **File Coordination**: Safe concurrent file access

## Use Cases

- **Work Projects**: Bundle editors, IDEs, project tools, and documentation
- **Creative Workflows**: Combine relevant apps for specific tasks
- **Entertainment**: Group games, media apps, and browsing apps
- **System Utilities**: Quick access to utility apps and scripts
- **Task-Based Computing**: One document per project or context
