---
tags:
  - guide/connecting
---
# Daily notes and templates

## A note for each day

A daily note is one note per day, named by its date: a place for what happened, what to do, and links to everything else. This guide keeps them in *6 Everyday examples/Daily*; open [[2026-11-16]] for one.

- **Today's note**: **New** › **Today's Daily Note** (on the Mac, the menu of the **New Note** button, or Go › **Today's Daily Note**). It opens the note, or makes it first.
- Settings › Daily Notes sets the folder, the date format, the template and **Open Daily Note on Startup**.

## The calendar

The left sidebar's **Calendar** panel shows a month, with a dot on the days that have a note; a tap opens that day. Once you allow it, it also shows Apple Calendar's events, and a template can list them with `{{events}}`. Settings › Calendar chooses where notes for events go and which Reminders list tasks are sent to.

## Templates

A template is a note you copy into others. This guide's templates are in the folder *Templates*: [[Daily note]], [[Recipe]] and [[Lecture]].

A template can fill in the title, the date and the time:

**Copy this**

```markdown
# {{title}}
Started {{date:YYYY-MM-DD}} at {{time}}
```

1. Tell Graphite where your templates are: Settings › Templates › **Template Folder Location**.
2. In a note, choose **Insert** › **Template…** (on iPad and iPhone in the note's **More** menu) and pick one. It goes in at the cursor.

Next: [[Search]].
