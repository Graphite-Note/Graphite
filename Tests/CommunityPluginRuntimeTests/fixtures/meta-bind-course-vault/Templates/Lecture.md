<%*
const course = tp.file.find_tfile("Signals and Systems/Signals and Systems.md");
let lectureNumber = 1;
await app.fileManager.processFrontMatter(course, (frontmatter) => {
    lectureNumber = (Number(frontmatter.lectures_held) || 0) + 1;
    frontmatter.lectures_held = lectureNumber;
});
await tp.file.rename("Lecture " + lectureNumber);
tR += "---\ncourse: \"[[Signals and Systems]]\"\ntype: lecture\nnumber: " + lectureNumber + "\ndate: " + tp.date.now("YYYY-MM-DD") + "\n---\n# Lecture " + lectureNumber + "\n";
-%>

## Notes

