# Stapler

My take on the classic Macintosh app [Stapler](https://macintoshgarden.org/apps/stapler-11) (Chris Patterson, Patterson Software Works, 1992).

With a little bit of the early Mac OS X app [LaunchList](http://hasseg.org/launchList/) (Ali Rantakari, hasseg.org, 2009).

More info in [the accompanying blog post](https://blog.gingerbeardman.com/2024/08/10/stapler-i-remade-a-32-year-old-classic-macintosh-app/).

## Download

[https://github.com/gingerbeardman/stapler/releases/latest](https://github.com/gingerbeardman/stapler/releases/latest)

## What is it?

The idea is you set up a *Stapler Document* per project containing related apps, files, folders, etc.

Then you can open them all at once by launching the single document.

Each document contains a list of aliases that can be managed, inspected, launched using the app.

Task-based computing.

<img width="442" alt="screenshot" src="https://github.com/user-attachments/assets/9b5482f9-48f0-4609-bf66-8b54ae148132">

## Use cases
- Work: text editor, run current game, pixel art editor, bitmap font app, todo list
- Play: Music app, Hacker News app, Twitter app, script to position windows
- Movie: run Caffeine to keep your computer on, shortcut to put displays to sleep

----

## Usage

### Opening the app

- The app is digitally signed by me and my Apple developer account
- The app is *not* Notarised and I currently have no plans to do so
- You may need to do the right-click-choose-open Gatekeeper dance a couple of times to open it

### Editing a list

1. Open `Stapler.app`
2. Create a New Document
3. Add some items
   - using drag and drop from Finder or other apps
   - or using the menu `Items` > `Add`
4. Items can be removed (they are aliases so files on disk are not affected)
5. Save your list as a *Stapler Document*

All standard macOS Document-Based App conventions are supported through the File menu. And things like Undo just works!

### Launching a list

1. Open your *Stapler Document*
2. All items in the list will be launched automatically
3. `Stapler.app` will close (if it was not already open)

*Tip*: hold the <kbd>Cmd</kbd> key whilst launching a *Stapler Document* to open it in edit mode.

### Launching specific items

1. Open `Stapler.app`
2. Open a *Stapler Document*
3. Select the items you want to launch
4. Select `Items` > `Launch` (or press <kbd>Return</kbd>)

### Working with a list

1. Open `Stapler.app`
2. Open a *Stapler Document*
   - use `File` > `Open…`
   - use `File` > `Open Recent`
3. Use the `Items` menu

*Tip*: hold the <kbd>Cmd</kbd> key whilst launching a *Stapler Document* to open it in edit mode.

### Keyboard controls

|Key |Function|
|--|----|
|<kbd>Cmd</kbd> + <kbd>Return</kbd>|Add… (open file selector)|
|<kbd>Backspace</kbd>|Remove|
|<kbd>Space</kbd>|Quick Look|
|<kbd>Cmd</kbd> + <kbd>R</kbd>|Reveal in Finder|
|<kbd>Return</kbd>|Launch|

### Permissions

- All files you select or drop are recorded only as macOS bookmarks
- The only files that are written to are Stapler Documents
- Network permission is required to Quick Look .webloc files
- File access permission may be prompted for some folders
- You can grant additional file access permissions at:
    - `System Settings > Privacy & Security > Files and Folders` for specific folders
    - `System Settings > Privacy & Security > Full Disk Access` for full disk

---

## Bonus tip

System Preferences > Desktop & Dock > Windows > Close windows when quitting an application = OFF

Then leave the windows of an app open as you quit it. When you next launch the app its windows will restore to their previous size and position. If you close the windows first, then the app will restore to having no windows open.

----

## Get involved

- Bug reports and PRs are very welcome!

## Licence

[MIT](/LICENSE)
