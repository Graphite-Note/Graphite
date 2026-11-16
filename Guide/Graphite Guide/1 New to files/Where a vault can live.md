---
tags:
  - guide/new-to-files
---
# Where a vault can live

A vault is a folder, so it can live anywhere a folder can. Where you put it decides which devices see it and who can share it.

| Where | Good for | How it syncs |
| --- | --- | --- |
| **On this device** (Graphite's own folder) | trying Graphite, notes that stay on one iPad | it does not; back it up (see [[Backups]]) |
| **iCloud Drive** | the same notes on your iPad, iPhone and Mac | iCloud keeps every device up to date |
| **Another cloud drive** (Google Drive, OneDrive, Dropbox, Nextcloud…) | people who already use one | that drive's app keeps the folder in step |
| **A USB stick or an external drive** (Mac) | a vault you carry between computers | it does not; the drive is the vault |
| **A network folder** (Mac) | a shared drive at school or work | the server keeps it |

Graphite has no account and no sync service of its own. **Your vault syncs the way its folder does.**

## The same notes on all your devices

1. On the first device, when you make the vault, choose **Choose Folder…** and pick a folder in **iCloud Drive**.
2. On each other device, choose **Open Folder as Vault** and pick the same folder.
3. That is all. A note changed on the iPad appears on the Mac a few moments later.

> [!tip] Already using Obsidian with iCloud?
> Obsidian keeps its vaults in iCloud Drive › **Obsidian**. Open that folder's vault in Graphite with **Open Folder as Vault**, and both apps read and write the same files. See [[Using both apps]].

> [!warning] If a note changes in two places at once
> Two devices editing the same note while offline can both win. Graphite notices when that happens and shows both versions rather than overwriting one, so you can keep the right one.

## Moving a vault later

Because it is only a folder, you can move it with the Files app or the Finder, then open it again from its new place with **Open Folder as Vault**. Links between notes keep working: they name notes, not places on the disk.

Next: [[What the files are]].
