#!/usr/bin/env python3
# File: make-measurement-vault.py
# Layer: Tests
# Description: Writes a made-up vault of a real vault's shape for measuring the community plugin runtime.
# Authors: Bahey Shalash
# Version: 0.1
# Date: 28/11/2026
"""A made-up vault of a real vault's shape for measuring community plugins:
1,363 notes, about 76 MB of Markdown, words drawn by Zipf's law from the system dictionary,
with frontmatter, headings, links, tags and tasks, and a Dashboard note with several plugin blocks."""
import json, os, random, sys

destination = sys.argv[1]
note_count = int(sys.argv[2]) if len(sys.argv) > 2 else 1363
target_bytes = int(sys.argv[3]) if len(sys.argv) > 3 else 76_000_000
generator = random.Random(20261128)
words = [line.strip().lower() for line in open('/usr/share/dict/words') if line.strip().isalpha()]
generator.shuffle(words)
words = words[:161_000]
weights = [1.0 / (rank + 1) for rank in range(len(words))]
cumulative = []
total = 0.0
for weight in weights:
    total += weight
    cumulative.append(total)

import bisect
def word():
    return words[bisect.bisect_left(cumulative, generator.random() * total)]

def sentence(length):
    text = ' '.join(word() for _ in range(length))
    return text[0].upper() + text[1:] + '.'

folders = ['Courses/Physics', 'Courses/Mathematics', 'Courses/Chemistry', 'Projects', 'Journal', 'Reading', 'Inbox', 'Archive/2025', 'Archive/2024']
titles = []
for index in range(note_count):
    folder = folders[index % len(folders)]
    titles.append(f'{folder}/{word().capitalize()} {word()} {index}')
tags = ['physics', 'maths', 'chemistry', 'project', 'reading', 'idea', 'todo', 'review', 'lecture', 'exam']
average_bytes = target_bytes // note_count
for index, title in enumerate(titles):
    path = os.path.join(destination, title + '.md')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    parts = ['---', f'tags: [{tags[index % len(tags)]}, {tags[(index * 7) % len(tags)]}]',
             f'rating: {generator.randint(1, 5)}', f'status: {generator.choice(["open", "done", "waiting"])}',
             f'created: 2025-{generator.randint(1, 12):02d}-{generator.randint(1, 28):02d}', '---', '']
    size = sum(len(part) + 1 for part in parts)
    note_bytes = int(average_bytes * generator.uniform(0.2, 1.8))
    section = 0
    while size < note_bytes:
        if section % 6 == 0:
            heading = f'## {sentence(4)[:-1]}'
            parts.append(heading); size += len(heading) + 1
        paragraph = ' '.join(sentence(generator.randint(8, 24)) for _ in range(generator.randint(3, 8)))
        if generator.random() < 0.6:
            paragraph += f' See [[{generator.choice(titles).split("/")[-1]}]].'
        if generator.random() < 0.3:
            paragraph += f' #{generator.choice(tags)}'
        parts.append(paragraph); parts.append('')
        size += len(paragraph) + 2
        if generator.random() < 0.15:
            task = f'- [{generator.choice([" ", " ", "x"])}] {sentence(6)[:-1]} 📅 2026-{generator.randint(1, 12):02d}-{generator.randint(1, 28):02d}'
            parts.append(task); parts.append(''); size += len(task) + 2
        section += 1
    with open(path, 'w') as file:
        file.write('\n'.join(parts))

dashboard = '''# Dashboard

```dataview
TABLE rating, status, created FROM "Courses/Physics" SORT rating DESC LIMIT 30
```

```dataview
LIST FROM #exam WHERE status = "open" LIMIT 40
```

```tasks
not done
due before 2026-06-01
limit 30
```

```ad-note
title: About this vault
A made-up vault of a real vault's shape, for measuring community plugins.
```

```dataview
TABLE length(file.outlinks) AS Links FROM "Projects" SORT file.name LIMIT 25
```

```tasks
done
limit 20
```

```ad-tip
Rated notes: `$= dv.pages('"Reading"').where(p => p.rating >= 4).length`
```

Notes in the vault: `= length(this.file.inlinks)`
'''
with open(os.path.join(destination, 'Dashboard.md'), 'w') as file:
    file.write(dashboard)
print(note_count + 1, 'notes,', sum(os.path.getsize(os.path.join(root, name)) for root, _, names in os.walk(destination) for name in names if name.endswith('.md')), 'bytes')
