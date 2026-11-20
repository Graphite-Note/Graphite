/**
 * File: ReadingDiagramSamples.swift
 * ---------------------------------
 * Layer: Tests
 * Description: One small diagram of each type the package draws, from Mermaid's documentation, for the diagram tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 20/11/2026
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
        Sample(kind: .kanban, source: #"""
            kanban
            todo[Todo]
              id3[Update Database Function]@{ ticket: MC-2037, assigned: 'knsv', priority: 'High' }
            """#),
        Sample(kind: .treeView, source: #"""
            treeView-beta
                src/
                    App.tsx :::highlight
                    index.js
                package.json
            """#),
        Sample(kind: .ishikawa, source: #"""
            ishikawa-beta
                Blurry Photo
                Process
                    Out of focus
                    Shutter speed too slow
                    Protective film not removed
                    Beautification filter applied
                User
                    Shaky hands
                Equipment
                    LENS
                        Inappropriate lens
                        Damaged lens
                        Dirty lens
                    SENSOR
                        Damaged sensor
                        Dirty sensor
                Environment
                    Subject moved too quickly
                    Too dark
            """#),
        Sample(kind: .info, source: #"""
            info
            """#),
        Sample(kind: .packet, source: #"""
            ---
            config:
              packet:
                showBits: true
                bitOrder: descending
                bitsPerRow: 16
            ---
            packet
            0-7: "DATA"
            8-11: "TYPE"
            12: "EN"
            13-15: "RESERVED"
            """#),
        Sample(kind: .radar, source: #"""
            ---
            config:
              radar:
                axisScaleFactor: 0.25
                curveTension: 0.1
              theme: base
              themeVariables:
                cScale0: "#FF0000"
                cScale1: "#00FF00"
                cScale2: "#0000FF"
                radar:
                  curveOpacity: 0
            ---
            radar-beta
              axis A, B, C, D, E
              curve c1{1,2,3,4,5}
              curve c2{5,4,3,2,1}
              curve c3{3,3,3,3,3}
            """#),
        Sample(kind: .treemap, source: #"""
            ---
            config:
                theme: 'forest'
            ---
            treemap-beta
            "Category A"
                "Item A1": 10
                "Item A2": 20
            "Category B"
                "Item B1": 15
                "Item B2": 25
            """#),
        Sample(kind: .venn, source: #"""
            venn-beta
              set A["Alpha"]:20
              set B["Beta"]:12
              union A,B["AB"]:3
            """#),
        Sample(kind: .cynefin, source: #"""
            cynefin-beta
              title Incident Response

              complex
                "Investigate root cause"
                "Run chaos experiment"

              complicated
                "Analyze performance data"
                "Expert review needed"

              clear
                "Restart service"
                "Apply known fix"

              chaotic
                "Page on-call immediately"

              confusion
                "Unknown failure mode"
            """#),
        Sample(kind: .wardleyMap, source: #"""
            wardley-beta
            title Inertia

            component Legacy System [0.45, 0.40] (inertia)
            component New Platform [0.65, 0.45]

            Legacy System -> New Platform
            """#),
        Sample(kind: .eventModel, source: #"""
            eventmodeling

            tf 03 evt ItemAdded
            tf 02 rmo CartItems
            tf 04 ui CartUI
            """#),
        Sample(kind: .railroad, source: #"""
            railroad-ebnf-beta
            greeting = "Hello" " " "World" ;
            """#),
        Sample(kind: .c4, source: #"""
            C4Context
              title System Context diagram for Internet Banking System
              Person(customer, "Banking Customer", "A customer of the bank")
              System(banking, "Internet Banking System", "Shows customers their accounts")
              System_Ext(mail, "E-mail system", "The bank's e-mail system")
              Rel(customer, banking, "Uses")
              Rel(banking, mail, "Sends e-mails", "SMTP")
            """#),
        Sample(kind: .block, source: #"""
            block
              A space B
              A-->B
            """#),
        Sample(kind: .architecture, source: #"""
            architecture-beta
                group api(cloud)[API]

                service db(database)[Database] in api
                service disk1(disk)[Storage] in api
                service disk2(disk)[Storage] in api
                service server(server)[Server] in api

                db:L -- R:server
                disk1:T -- B:server
                disk2:T -- B:db
            """#),
        Sample(kind: .requirement, source: #"""
            requirementDiagram

            direction LR

            requirement test_req {
                id: 1
                text: the test text.
                risk: high
                verifymethod: test
            }

            element test_entity {
                type: simulation
            }

            test_entity - satisfies -> test_req
            """#),
        Sample(kind: .swimlane, source: #"""
            swimlane-beta LR
              subgraph Buyer
                choose[Choose product]
                pay[Pay invoice]
              end

              subgraph Store
                reserve[Reserve stock]
                ship[Ship product]
              end

              choose --> reserve
              reserve -->|Invoice ready| pay
              pay --> ship
            """#),
        Sample(kind: .useCase, source: #"""
            usecase-beta
            actor Customer
            Reset("`Reset
            password`")
            Refund("Refund #40;partial#41;")
            Customer --> Reset
            Customer --> Refund
            """#),
        Sample(kind: .agentFlow, source: #"""
            ---
            config:
              layout: elk
            ---
            agentflow-beta TB
              flow tools["Tools"]
                a["a"]@{ shape: tool }
                b["b"]@{ shape: tool }
              end
              tools@{ algorithm: "elk.rectpacking" }
            """#),
    ]
}
