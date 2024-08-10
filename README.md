# Stapler

A remake of classic Macintosh app [Stapler](https://macintoshgarden.org/apps/stapler-11) (Chris Patterson, Patterson Software Works, 1992).

You might remember a similar app for Mac OS X called [LaunchList](http://hasseg.org/launchList/) (Ali Rantakari, hasseg.org, 2009).

## What is it?

The idea is you set up a *Stapler Document* per project containing related apps, files, folders, etc.

Then you can open them all at once by launching the single *Stapler Document*.

Each *Stapler Document* contains lists of aliases which can be managed, inspected and launched through `Stapler.app`.

<img width="442" alt="screenshot" src="https://github.com/user-attachments/assets/9b5482f9-48f0-4609-bf66-8b54ae148132">

## Use cases
- Work: open Nova editor, run current game, pixel art editor, bitmap font app, Taskpaper todo list
- Play: Music app, Hacker News app, Twitter app
- Movie: run Caffeine to keep your computer on, shortcut to Sleep Displays

## Download

[https://github.com/gingerbeardman/stapler/releases/latest](https://github.com/gingerbeardman/stapler/releases/latest)

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

*Tip*: hold the <kbd>Cmd</kbd> key as the *Stapler Document* is being launching to open it in edit mode.

### Working with a list

1. Open `Stapler.app`
2. Open a *Stapler Document*
   - use `File` > `Open…`
   - use `File` > `Open Recent`
3. Use the `Items` menu

### Keyboard controls

|Key |Function|
|--|----|
|<kbd>Cmd</kbd> + <kbd>Return</kbd>|Add… (open file selector)|
|<kbd>Backspace</kbd>|Remove|
|<kbd>Space</kbd>|Quick Look|
|<kbd>Cmd</kbd> + <kbd>R</kbd>|Reveal in Finder|
|<kbd>Return</kbd>|Launch|

### Permissions

- All files you select or drop are recorded only as system bookmarks
- The only files that are written are through the file save selector
- Read-only permission may be prompted for some folders
- Network permission is required to Quick Look .webloc files

