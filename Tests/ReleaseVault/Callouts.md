# Callouts

> [!note]
> A note callout with **bold** and a [[Link target|link]].

> [!abstract] Summary with a title

> [!info] Info
> One line.

> [!todo] To do
> - [ ] A task inside a callout
> - [x] A done one

> [!tip]+ Open and foldable
> This callout starts open.

> [!warning]- Folded
> This callout starts folded: its body is hidden.

> [!success] Done
> Worked.

> [!question] Question
> Why does it alias?

> [!failure] Failure

> [!danger] Danger
> High voltage.

> [!bug] Bug

> [!example] Example
> An example.

> [!quote] Quote
> A quotation.

> [!unknown-type] A type Graphite does not know
> It looks like a note.

## Nested

> [!info] Outer
> Text of the outer callout.
> > [!warning] Inner
> > Text of the inner callout.
> > > [!tip] Innermost
> > > Three levels deep.

## With a table and math

> [!example] A table in a callout
> | Symbol | Meaning |
> | --- | --- |
> | $f_s$ | sampling rate |
> | $T$ | period |
>
> And display math:
> $$
> f_s > 2 f_{max}
> $$

## With code

> [!note] Code
> ```python
> print("inside a callout")
> ```
