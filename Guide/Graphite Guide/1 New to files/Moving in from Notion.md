---
tags:
  - guide/new-to-files
---
# Moving in from Notion

Your Notion pages come with you, and they keep their look. Graphite imports a Notion workspace into ordinary Markdown notes: each page a note, each database a base with its rows as notes, and the files beside them. Covers, icons, columns and colours come along, so a course page from Notion opens in Graphite looking much as it did, like the dashboards in [[Everyday examples]].

## Step 1: get your pages out of Notion

There are two ways. Both import the same thing.

- **An export file.** In Notion's **Settings**, choose **Export all workspace content** (or **Export** in a page's **•••** menu), with the format **HTML** and **Include subpages** on. Notion sends a `.zip` file, or several **Part** zips for a large workspace: keep them all together.
- **Notion's API, with a token.** In Notion, open **Settings** › **Connections** › **Develop or manage integrations**, make an internal integration for your workspace and copy its token. Then share each page you want with it: the page's **•••** menu › **Connections**, and choose the integration. The pages and databases inside a shared page come with it. The token stays in this device's keychain, never in the vault, and goes to Notion alone.

> [!tip] 💡
> The API also updates an earlier import: import again into the same folder, and pages you have not changed in Graphite are brought up to date while the ones you edited are kept.

## Step 2: import

Choose **New** › **Import from Notion…**, in the menu of the **New Note** button (on the Mac also **File** › **Import from Notion…**), then pick **Export File** or **Notion's API** at the top of the sheet:

- **Export File**: **Choose Export…**, then pick the zip, all the Part zips, or the unpacked folder.
- **Notion's API**: paste the token and choose **Import from Notion**.

Everything goes into a new folder called **Notion**, and nothing already in the vault is changed. A card at the top of the window shows the pages written, with **Pause** and **Cancel**; you can keep working while it runs.

## What comes over

| In Notion | In Graphite |
| --- | --- |
| A page | A note, in the folders Notion nests it in |
| The page's cover and icon | The `banner` and `icon` properties, drawn above the title in the reading view |
| Columns | A `[!multi-column]` callout, one `[!blank]` column each, wider ones as `wide-2` to `wide-5` |
| Links to pages, one under another | A list of links, each with its page's icon |
| Coloured text | `~={#hex}text=~`, readable in light and dark; a yellow background as `==highlight==` |
| A callout | A callout with its emoji first, `> [!tip] 💡`, or with `no-title` and its type's icon |
| A toggle | A folded callout; a toggle heading stays a heading, which folds too |
| Equations | `$…$` and `$$…$$` |
| A database | A base over its rows, with its columns in Notion's order, and each row a note with typed properties and its whole title |
| A database's views (API) | Table, board, gallery and list views; filters, sorts and groups where Bases can express them |
| A database's view on another page | The database's base, embedded there with the rows that view shows |
| Pictures and files | Copied beside the note and embedded |

An imported page is written in exactly the Markdown that [[Building a dashboard]] teaches, so a page you bring from Notion and one you build by hand are the same kind of note: change either the same way.

A made-up example of what a page becomes:

```markdown
---
icon: 🧪
banner: "[[Lab bench.png]]"
---
# Chemistry lab

> [!info|no-title]
> Goggles on before anything is poured.

> [!multi-column]
> > [!blank]
> > ## ~={#337EA9}Experiments=~
> > [[Titration]]  
> > [[Flame tests]]
>
> > [!blank]
> > ## ~={#448361}Reports=~
> > [[Report template]]

![[Results.base]]
```

## What does not come over

Some of Notion has no Markdown form. The import keeps the content and tells you what it simplified:

- the colour of blocks that are not text, such as a table or a picture, and colour inside code or a formula;
- calendar, timeline and chart views, which become tables;
- formulas and rollups that Bases cannot compute, kept as the values Notion showed;
- a linked view's own filter in an export file: Notion does not write it there, so the table lists the rows the view showed;
- pictures or files missing from the export, marked where they were.

## The import report

At the end the sheet says how many notes, bases and attachments were written, and **Open the Import Report** opens a note in the import's folder, **Notion import report**. It lists every note and base written, with a link to each, then everything that was simplified or left out and why. Read it once: it is the list of things to check by hand.

> [!info] Turn it off
> Import from Notion is a feature you can switch off in Settings › Core Plugins › **Notion Import**.

Next: [[Backups]].
