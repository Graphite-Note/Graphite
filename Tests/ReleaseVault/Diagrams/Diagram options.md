# Diagram options

Mermaid diagrams with the options Graphite reads, and one Graphite cannot draw.

## A compact Gantt chart

```mermaid
---
displayMode: compact
---
gantt
    title Lab weeks
    dateFormat YYYY-MM-DD
    section Lab
    Build the circuit :a1, 2026-11-02, 4d
    Measure :a2, after a1, 3d
    Write up :2026-11-05, 4d
```

## A pie chart with its labels outside, a hole and a legend on the right

```mermaid
---
config:
  pie:
    textPosition: 0.9
    donutHole: 0.4
    legendPosition: right
---
pie title Marks
    "Labs" : 30
    "Exam" : 50
    "Homework" : 20
```

## A git graph, its branch line hidden

```mermaid
---
config:
  gitGraph:
    showBranches: false
    mainBranchName: trunk
---
gitGraph
    commit
    branch feature
    commit
    checkout trunk
    merge feature
```

## Options in a directive

A directive's options are read as the front matter's, and over them.

```mermaid
%%{init: {'pie': {'donutHole': 0.5, 'legendPosition': 'bottom'}}}%%
pie title Hours a week
    "Lectures" : 12
    "Exercises" : 8
    "Reading" : 6
```

```mermaid
%%{init: {'gitGraph': {'mainBranchName': 'trunk', 'rotateCommitLabel': false}}}%%
gitGraph
    commit id: "lab 1"
    branch report
    commit id: "draft"
    checkout trunk
    merge report
```

```mermaid
---
config:
  sankey:
    width: 900
---
%%{init: {'sankey': {'width': 500, 'showValues': false}}}%%
sankey
Study hours,Lectures,12
Study hours,Exercises,8
Exercises,Corrections,3
```

## An empty diagram

Graphite shows its source and why it is not drawn:

```mermaid
```
