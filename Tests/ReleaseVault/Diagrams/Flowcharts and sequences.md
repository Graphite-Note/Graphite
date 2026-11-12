# Flowcharts and sequences

## Flowchart

```mermaid
flowchart LR
    A[Sample the signal] --> B{Above Nyquist?}
    B -- yes --> C[Reconstruct]
    B -- no --> D((Aliasing))
    D -.-> E>Add a filter]
    E --> A
    C ==> F[(Store)]
```

## Graph, top down, with subgraphs

```mermaid
graph TD
    subgraph Front end
        M[Microphone] --> P[Preamplifier]
    end
    subgraph Converter
        P --> S[Sample and hold] --> Q[Quantizer]
    end
    Q --> O[Output]
```

## Sequence diagram

```mermaid
sequenceDiagram
    participant S as Student
    participant T as Teaching assistant
    S->>T: Hands in the lab report
    activate T
    T-->>S: Asks for the plots
    deactivate T
    Note over S,T: One week later
    loop Every exercise
        S->>T: A question
        T-->>S: An answer
    end
    alt On time
        T->>S: Full marks
    else Late
        T->>S: Half marks
    end
```
