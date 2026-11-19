/**
 * File: ReadingDiagramSamples.swift
 * ---------------------------------
 * Layer: Tests
 * Description: One small diagram of each type the package draws, from Mermaid's documentation, for the diagram tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import MermaidDiagrams

/// A diagram of each type, small enough to draw in a test, written as Mermaid's documentation writes them.
enum ReadingDiagramSamples {
    struct Sample {
        let kind: MermaidDiagramKind
        let source: String
    }

    static let oneOfEachType: [Sample] = [
        Sample(kind: .flowchart, source: "flowchart TD\n  A[Christmas] -->|Get money| B(Go shopping)\n  B --> C{Let me think}\n  C -->|One| D[Laptop]"),
        Sample(kind: .sequence, source: "sequenceDiagram\n  autonumber\n  Alice->>John: Hello John, how are you?\n  John-->>Alice: Great!"),
        Sample(kind: .classDiagram, source: "classDiagram\n  Animal <|-- Duck\n  class Duck{\n    +String beakColor\n    +swim()\n  }"),
        Sample(kind: .stateDiagram, source: "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving\n  Moving --> Crash\n  Crash --> [*]"),
        Sample(kind: .entityRelationship, source: "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER ||--|{ LINE-ITEM : contains"),
        Sample(kind: .pieChart, source: "pie title Pets adopted by volunteers\n  \"Dogs\" : 386\n  \"Cats\" : 85\n  \"Rats\" : 15"),
        Sample(kind: .ganttChart, source: "gantt\n  title A Gantt Diagram\n  dateFormat YYYY-MM-DD\n  section Section\n  A task :a1, 2014-01-01, 30d\n  Another task :after a1, 20d"),
        Sample(kind: .gitGraph, source: "---\ntitle: Release\n---\ngitGraph\n  commit\n  branch develop\n  checkout develop\n  commit\n  checkout main\n  merge develop"),
        Sample(kind: .mindmap, source: "mindmap\n  root((mindmap))\n    Origins\n      Long history\n    Research"),
        Sample(kind: .timeline, source: "timeline\n  title History of Social Media Platform\n  2002 : LinkedIn\n  2004 : Facebook : Google"),
        Sample(kind: .userJourney, source: "journey\n  title My working day\n  section Go to work\n    Make tea: 5: Me\n    Go upstairs: 3: Me, Cat"),
        Sample(kind: .quadrantChart, source: "quadrantChart\n  title Reach and engagement\n  x-axis Low Reach --> High Reach\n  y-axis Low Engagement --> High Engagement\n  quadrant-1 We should expand\n  Campaign A: [0.3, 0.6]"),
        Sample(kind: .xyChart, source: "xychart\n  title \"Sales Revenue\"\n  x-axis [jan, feb, mar]\n  y-axis \"Revenue\" 4000 --> 11000\n  bar [5000, 6000, 7500]\n  line [5000, 6000, 7500]"),
        Sample(kind: .sankey, source: "sankey\nAgricultural waste,Bio-conversion,124.729\nBio-conversion,Liquid,0.597\nBio-conversion,Losses,26.862"),
    ]
}
