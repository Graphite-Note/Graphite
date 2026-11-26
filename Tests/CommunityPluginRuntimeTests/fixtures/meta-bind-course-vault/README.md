# Course page demo

A made-up course for trying Meta Bind's buttons in Graphite. Install Meta Bind 1.5.1 and Templater 2.x from Settings › Community plugins, turn both on, and open `Signals and Systems/Signals and Systems.md`.

- **New assignment** makes a note in `Assignments` from `Templates/Assignment.md`, due in a week, and opens it.
- **Start lecture** counts the lecture on the course page (`lectures_held`), makes `Lecture N` in `Lectures` from `Templates/Lecture.md`, and opens it.
- The two buttons are Meta Bind's button templates, in its settings (`.obsidian/plugins/obsidian-meta-bind-plugin/data.json`), so every note can show them with `` `BUTTON[new-assignment, start-lecture]` ``.
- The status, credits and exam fields write the course page's properties.
- `Course work.base` lists the assignments and lectures.
