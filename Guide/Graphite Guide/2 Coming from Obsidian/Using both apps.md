---
tags:
  - guide/obsidian
---
# Using both apps

Graphite and Obsidian can work on the same vault, even on the same device. They read and write the same files, so a note written in one is there in the other.

## Set it up

1. Keep the vault where Obsidian looks for it, such as iCloud Drive › **Obsidian** › your vault.
2. In Graphite, choose **Open Folder as Vault** and pick that folder.
3. Use either app whenever you like.

## What each app sees of the other's work

| Made in Graphite | Seen in Obsidian |
| --- | --- |
| A note, a link, a callout, a table | the same note, link, callout and table |
| A drawing in a note | a picture (PNG, PDF or SVG); edit it again in Graphite |
| Ink and highlights on a PDF | the PDF with your marks, as any PDF reader shows them |
| A notebook | a PDF with its paper and ink |
| A recording | an `.m4a` or `.mp4` file, playable from the note |
| A base, a canvas | the same `.base` or `.canvas` file |

## Good habits

- **Edit a note in one app at a time.** If both change it at once, Graphite notices and shows both versions instead of overwriting one.
- **Let the theme follow.** Turn on Settings › Appearance › **Use the Vault's Obsidian Theme** to see notes as Obsidian draws them.
- **Links between apps.** Graphite understands `graphite://` links with Obsidian's actions, so an `obsidian://open?vault=…&file=…` link works in Graphite once `obsidian` is changed to `graphite`.

You have reached the end of the *Coming from Obsidian* path. Carry on with [[Handwriting and PDFs]] or the [[Everyday examples]].
