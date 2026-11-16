---
tags:
  - guide/markdown
---
# Diagrams

A diagram can be written as text, in Mermaid, and Graphite draws it. Change a word and the drawing follows.

## A flowchart

**Copy this**

````markdown
```mermaid
flowchart LR
    A[Hungry?] --> B{Time to cook?}
    B -- yes --> C[Pick a recipe]
    B -- no --> D[Pick a restaurant]
    C --> E((Eat))
    D --> E
```
````

**What you see**

```mermaid
flowchart LR
    A[Hungry?] --> B{Time to cook?}
    B -- yes --> C[Pick a recipe]
    B -- no --> D[Pick a restaurant]
    C --> E((Eat))
    D --> E
```

## A timeline

```mermaid
timeline
    title The Lisbon weekend
    Friday : Train in the evening : Dinner near the river
    Saturday : Old town on foot : Tram 28 : Sunset at a viewpoint
    Sunday : Market breakfast : Train home
```

## A pie chart

```mermaid
pie title Where the trip budget went
    "Train" : 120
    "Food" : 95
    "Rooms" : 160
    "Museums" : 30
```

## A sequence

```mermaid
sequenceDiagram
    participant You
    participant Graphite
    participant iCloud
    You->>Graphite: Write a note
    Graphite->>iCloud: Save the file
    iCloud-->>Graphite: The same note on the Mac
```

Graphite also draws class, state, entity relationship and Gantt diagrams, mind maps, Git graphs, user journeys, quadrant charts, XY charts and Sankey diagrams. Write the source in a code block named `mermaid`, as above.
