/**
 * File: DiagramScrollingNote.swift
 * --------------------------------
 * Layer: Tests
 * Description: A demo note of 35 mermaid diagrams of 32 types, written for the scrolling measurement: a made-up course on
 *              digital systems, each diagram under a heading and a line of text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */
#if os(iOS)
import Foundation

/// The note `DiagramNoteScrollingHostedTests` scrolls: small and large diagrams, wide ones that the iPhone's column shows
/// turned or scrolling sideways, and every type Graphite draws but the info diagram.
enum DiagramScrollingNote {
    static var text: String {
        "# Digital systems, the course in diagrams\n\nEvery diagram of the course, one after the other.\n\n"
            + diagrams.enumerated().map { number, diagram in
                "## \(number + 1). \(diagram.title)\n\nThe \(diagram.title.lowercased()) as drawn in the lecture.\n\n```mermaid\n\(diagram.source)\n```\n"
            }.joined(separator: "\n")
    }

    static let diagrams: [(title: String, source: String)] = graphs + charts + newerTypes

    private static let graphs: [(title: String, source: String)] = [
        ("Design flow", """
            flowchart TD
              Spec[Specification] --> RTL[RTL in VHDL]
              RTL --> Sim{Simulation passes?}
              Sim -- no --> RTL
              Sim -- yes --> Synth[Synthesis] --> PnR[Place and route] --> Timing{Timing met?}
              Timing -- no --> Synth
              Timing -- yes --> Bitstream[(Bitstream)]
            """),
        ("Pipeline stages", """
            flowchart LR
              IF[Fetch] --> ID[Decode] --> EX[Execute] --> MEM[Memory] --> WB[Write back]
              EX -. forward .-> EX
              MEM -. forward .-> EX
              ID --> Hazard{{Hazard unit}} --> IF
            """),
        ("Memory hierarchy", """
            flowchart TB
              subgraph Core
                R[Registers] --> L1[L1 cache]
              end
              subgraph Chip
                L1 --> L2[L2 cache] --> L3[L3 cache]
              end
              L3 --> DRAM[(Main memory)] --> SSD[(Storage)]
            """),
        ("Bus transaction", """
            sequenceDiagram
              participant CPU
              participant Bus
              participant Memory
              CPU->>Bus: Request address 0x40
              Bus->>Memory: Read
              activate Memory
              Memory-->>Bus: Data
              deactivate Memory
              Bus-->>CPU: Data ready
              Note over CPU,Memory: Four cycles in all
            """),
        ("Handshake", """
            sequenceDiagram
              autonumber
              Sender->>Receiver: valid
              Receiver-->>Sender: ready
              loop Each word
                Sender->>Receiver: data
              end
              alt Error
                Receiver-->>Sender: retry
              else Done
                Receiver-->>Sender: ack
              end
            """),
        ("Components", """
            classDiagram
              class Register {
                +width: Int
                +load(value)
                +read() Int
              }
              class Counter {
                +increment()
              }
              class ShiftRegister {
                +shiftLeft()
              }
              Register <|-- Counter
              Register <|-- ShiftRegister
              Counter --> Clock : uses
            """),
        ("Traffic light controller", """
            stateDiagram-v2
              [*] --> Red
              Red --> Green : timer
              Green --> Yellow : timer
              Yellow --> Red : timer
              state Green {
                [*] --> Go
                Go --> Pedestrian : button
              }
            """),
        ("Lab database", """
            erDiagram
              STUDENT ||--o{ SUBMISSION : makes
              LAB ||--|{ SUBMISSION : receives
              STUDENT {
                string name
                int sciper
              }
              LAB {
                int number
                date due
              }
            """),
        ("Branches of the project", """
            gitGraph
              commit
              branch alu
              commit
              commit
              checkout main
              commit
              merge alu
              branch cache
              commit
              checkout main
              merge cache
            """)
    ]

    private static let charts: [(title: String, source: String)] = [
        ("Semester plan", """
            gantt
              title Semester
              dateFormat YYYY-MM-DD
              section Labs
              Lab 1 :a1, 2026-09-14, 7d
              Lab 2 :a2, after a1, 14d
              Lab 3 :after a2, 14d
              section Project
              Proposal :p1, 2026-10-05, 7d
              Build :p2, after p1, 35d
              Report :after p2, 7d
            """),
        ("Grade", """
            pie title Grade
              "Labs" : 30
              "Project" : 30
              "Exam" : 40
            """),
        ("Topics", """
            mindmap
              root((Digital systems))
                Logic
                  Gates
                  Boolean algebra
                Sequential
                  Flip-flops
                  State machines
                Processors
                  Pipelines
                  Caches
            """),
        ("History", """
            timeline
              title Processors
              1971 : Intel 4004
              1978 : 8086
              1985 : ARM1
              1993 : Pentium
              2020 : Apple M1
            """),
        ("A lab session", """
            journey
              title A lab session
              section Before
                Read the handout: 3: Student
                Set up the board: 2: Student, Assistant
              section During
                Simulate: 4: Student
                Synthesise: 3: Student
            """),
        ("Designs compared", """
            quadrantChart
              title Area against speed
              x-axis Small --> Large
              y-axis Slow --> Fast
              quadrant-1 Fast and large
              quadrant-2 Fast and small
              quadrant-3 Slow and small
              quadrant-4 Slow and large
              Ripple adder: [0.2, 0.2]
              Carry lookahead: [0.6, 0.7]
              Kogge-Stone: [0.85, 0.9]
            """),
        ("Power per week", """
            xychart-beta
              title "Power measured"
              x-axis [w1, w2, w3, w4, w5, w6, w7, w8]
              y-axis "Milliwatts" 0 --> 120
              bar [40, 55, 70, 65, 90, 85, 100, 110]
              line [40, 55, 70, 65, 90, 85, 100, 110]
            """),
        ("Where the power goes", """
            sankey-beta
            Supply,Core,60
            Supply,Memory,25
            Supply,IO,15
            Core,Logic,40
            Core,Clock tree,20
            """),
        ("Instruction word", """
            packet
            0-6: "Opcode"
            7-11: "rd"
            12-14: "funct3"
            15-19: "rs1"
            20-24: "rs2"
            25-31: "funct7"
            """),
        ("Skills", """
            radar-beta
              axis l["Logic"], s["Sequential"], t["Timing"], v["VHDL"], d["Debugging"]
              curve a["Week 1"]{40, 30, 20, 30, 20}
              curve b["Week 12"]{90, 85, 70, 90, 80}
              max 100
              min 0
            """),
        ("Area of the chip", """
            treemap-beta
            "Core"
                "ALU": 20
                "Registers": 10
            "Caches"
                "L1": 25
                "L2": 35
            """)
    ]

    private static let newerTypes: [(title: String, source: String)] = [
        ("Requirements", """
            requirementDiagram
              requirement timing {
                id: 1
                text: Meet 100 MHz.
                risk: high
                verifymethod: test
              }
              element fpga_build {
                type: simulation
              }
              fpga_build - satisfies -> timing
            """),
        ("Lab system", """
            C4Context
              title The lab's system
              Person(student, "Student", "Runs the labs.")
              System(board, "FPGA board", "Runs the design.")
              System_Ext(server, "Grading server", "Checks submissions.")
              Rel(student, board, "Programs")
              Rel(student, server, "Submits to")
            """),
        ("Board layout", """
            block
            columns 3
              FPGA["FPGA"]:2 Clock
              LEDs Switches UART
            """),
        ("Week board", """
            kanban
              todo[To do]
                lab3[Lab 3 report]
              doing[Doing]
                fsm[Traffic light FSM]
              done[Done]
                lab2[Lab 2]
            """),
        ("Lab network", """
            architecture-beta
              group lab(cloud)[Lab]
              service pc(server)[Workstation] in lab
              service fpga(disk)[Board] in lab
              service db(database)[Grades] in lab
              pc:R -- L:fpga
              pc:B -- T:db
            """),
        ("Project tree", """
            treeView-beta
            ├── rtl/
            │   ├── alu.vhd
            │   └── fsm.vhd
            ├── tb/
            │   └── alu_tb.vhd
            └── Makefile
            """),
        ("Why the timing failed", """
            ishikawa-beta
                Timing not met
                Design
                    Long carry chain
                    No pipeline
                Tools
                    Wrong constraints
                Board
                    Slow speed grade
            """),
        ("Good designs", """
            venn-beta
              title A good design
              set Fast
              set Small
              set Correct
              union Fast,Correct["Usable"]
              union Fast,Small,Correct["Ideal"]
            """),
        ("Kinds of bugs", """
            cynefin-beta
              title Bugs
              clear
                "Typo in a signal name"
              complicated
                "Timing violation"
              complex
                "Metastability"
              chaotic
                "Board does not start"
            """),
        ("Tool chain", """
            wardley-beta
            title Tool chain
            anchor Student [0.95, 0.6]
            component Design [0.8, 0.4]
            component Simulator [0.6, 0.7]
            component Synthesis [0.4, 0.8]
            Student -> Design
            Design -> Simulator
            Design -> Synthesis
            """),
        ("Ordering a board", """
            eventmodeling
            tf 01 ui OrderForm
            tf 02 cmd OrderBoard
            tf 03 evt BoardOrdered
            """),
        ("Digit", """
            railroad-ebnf-beta
            title "Hex digit"
            digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "A" | "B" | "C" | "D" | "E" | "F" ;
            """),
        ("Submission", """
            swimlane-beta LR
              subgraph Student
                Write[Write the report]
                Submit[Submit]
              end
              subgraph Assistant
                Grade[Grade]
              end
              Write --> Submit --> Grade
            """),
        ("Uses of the grading server", """
            usecase-beta
            direction LR
            actor Student("Student")
            systemBoundary "Grading server"
              Submit("Submit a lab")
              Results("See results")
            end
            Student --> Submit
            Student --> Results
            """),
        ("Lab assistant", """
            agentflow-beta TB
              flow helper["Lab assistant"]
                question["Student question"]@{ shape: input }
                look["Read the design"]@{ shape: task }
                run["run_simulation"]@{ shape: tool }
                answer["Answer found?"]@{ shape: decision }
                question --> look --> run --> answer
              end
            """)
    ]
}
#endif
