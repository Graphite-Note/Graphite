# Embedded base

A base written in the note, with a table and a kanban board of the tasks:

```base
filters:
  and:
    - file.hasTag("task")
formulas:
  late: 'if(due, date(due) < date("2026-10-01"), false)'
views:
  - type: table
    name: Tasks in the note
    order:
      - file.name
      - status
      - due
      - formula.late
    sort:
      - property: due
        direction: ASC
  - type: kanban
    name: Board
    groupBy:
      property: status
      direction: ASC
    order:
      - file.name
      - due
```

A view of a base file, embedded by its name:

![[Books.base#Gallery]]

The map of the places:

![[Places.base#Map]]

A list:

![[Books.base#Reading list]]
