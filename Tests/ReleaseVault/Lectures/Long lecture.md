---
title: Inverter delay and sizing
course: Digital circuits
lecture: 6
due: 2026-10-07
reviewed: false
score: 8.5
tags:
  - lecture
  - course/digital-circuits
aliases:
  - Inverter sizing lecture
---

# Inverter delay and sizing

A long lecture for scrolling: twelve sections of text, lists, tasks, callouts, code, tables, formulas and pictures, as a course note has them.

## 1. Stage 1 of the inverter chain

The **propagation delay** of stage 1 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 1 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-1

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 1.a
- [x] Read chapter 1

> [!tip] Rule of thumb 1
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_1 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 1 | 4 | 5 ps |
| 2 | 16 | 5 ps |

$$
t_{p,1} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 2. Stage 2 of the inverter chain

The **propagation delay** of stage 2 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 2 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-2

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 2.a
- [x] Read chapter 2

> [!tip] Rule of thumb 2
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_2 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 2 | 16 | 5 ps |
| 3 | 64 | 5 ps |

$$
t_{p,2} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 3. Stage 3 of the inverter chain

The **propagation delay** of stage 3 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 3 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-3

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 3.a
- [x] Read chapter 3

> [!tip] Rule of thumb 3
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_3 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 3 | 64 | 5 ps |
| 4 | 1 | 5 ps |

$$
t_{p,3} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 4. Stage 4 of the inverter chain

The **propagation delay** of stage 4 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 4 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-4

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 4.a
- [x] Read chapter 4

> [!tip] Rule of thumb 4
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_4 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 4 | 1 | 5 ps |
| 5 | 4 | 5 ps |

$$
t_{p,4} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

![[Circuit sketch.png|320]]

## 5. Stage 5 of the inverter chain

The **propagation delay** of stage 5 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 5 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-5

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 5.a
- [x] Read chapter 5

> [!tip] Rule of thumb 5
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_5 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 5 | 4 | 5 ps |
| 6 | 16 | 5 ps |

$$
t_{p,5} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 6. Stage 6 of the inverter chain

The **propagation delay** of stage 6 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 6 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-6

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 6.a
- [x] Read chapter 6

> [!tip] Rule of thumb 6
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_6 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 6 | 16 | 5 ps |
| 7 | 64 | 5 ps |

$$
t_{p,6} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 7. Stage 7 of the inverter chain

The **propagation delay** of stage 7 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 7 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-7

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 7.a
- [x] Read chapter 7

> [!tip] Rule of thumb 7
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_7 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 7 | 64 | 5 ps |
| 8 | 1 | 5 ps |

$$
t_{p,7} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 8. Stage 8 of the inverter chain

The **propagation delay** of stage 8 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 8 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-8

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 8.a
- [x] Read chapter 8

> [!tip] Rule of thumb 8
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_8 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 8 | 1 | 5 ps |
| 9 | 4 | 5 ps |

$$
t_{p,8} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

![[Circuit sketch.png|320]]

## 9. Stage 9 of the inverter chain

The **propagation delay** of stage 9 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 9 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-9

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 9.a
- [x] Read chapter 9

> [!tip] Rule of thumb 9
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_9 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 9 | 4 | 5 ps |
| 10 | 16 | 5 ps |

$$
t_{p,9} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 10. Stage 10 of the inverter chain

The **propagation delay** of stage 10 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 10 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-10

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 10.a
- [x] Read chapter 10

> [!tip] Rule of thumb 10
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_10 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 10 | 16 | 5 ps |
| 11 | 64 | 5 ps |

$$
t_{p,10} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 11. Stage 11 of the inverter chain

The **propagation delay** of stage 11 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 11 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-11

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 11.a
- [x] Read chapter 11

> [!tip] Rule of thumb 11
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_11 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 11 | 64 | 5 ps |
| 12 | 1 | 5 ps |

$$
t_{p,11} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

## 12. Stage 12 of the inverter chain

The **propagation delay** of stage 12 is set by its *effective* resistance $R_{eq}$ and the load $C_L$ it drives. Section 12 works the chain through with logical effort, $t_p = 0.69\,R_{eq} C_L$.

See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-12

- Size the first stage for the input capacitance
- Keep the stage effort near four
  - the parasitic delay adds $p$
- Count the stages: $N = \log_4 F$

- [ ] Redo exercise 12.a
- [x] Read chapter 12

> [!tip] Rule of thumb 12
> A fanout of four gives a delay close to the optimum.

```verilog
module inverter_chain_12 (input a, output y);
  wire [3:0] stage;
  assign stage[0] = ~a;
  assign y = ~stage[0];
endmodule
```

| Stage | Size | Delay |
| --- | ---: | ---: |
| 12 | 1 | 5 ps |
| 13 | 4 | 5 ps |

$$
t_{p,12} = 0.69\, R_{eq} \left( C_{int} + C_L \right)
$$

![[Circuit sketch.png|320]]
