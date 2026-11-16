---
tags:
  - guide/markdown
---
# Quotes and callouts

## A quote

**Copy this**

```markdown
> The best way to learn a recipe is to cook it twice.
```

**What you see**

> The best way to learn a recipe is to cook it twice.

## Callouts

A callout is a quote with a type in brackets on its first line. It becomes a coloured box with an icon.

**Copy this**

```markdown
> [!tip] Remember
> Salt the water before the pasta goes in.
```

**What you see**

> [!tip] Remember
> Salt the water before the pasta goes in.

## Folded or open

A `-` after the type starts the callout folded, to hide an answer until you tap it. A `+` starts it open but foldable.

**Copy this**

```markdown
> [!question]- What is 230 V × 8.7 A?
> About 2,000 W: a kettle.
```

**What you see**

> [!question]- What is 230 V × 8.7 A?
> About 2,000 W: a kettle.

## Every type

> [!note] note
> The plain one.

> [!abstract] abstract (also summary, tldr)

> [!info] info

> [!todo] todo
> - [ ] Tasks work inside callouts too.

> [!tip] tip (also hint, important)

> [!success] success (also check, done)

> [!question] question (also help, faq)

> [!warning] warning (also caution, attention)

> [!failure] failure (also fail, missing)

> [!danger] danger (also error)

> [!bug] bug

> [!example] example

> [!quote] quote (also cite)

## Callouts inside callouts

**Copy this**

```markdown
> [!example] A full example
> Text of the outer box.
> > [!warning] And a warning inside it
> > With a table:
> >
> > | Setting | Value |
> > | --- | --- |
> > | Oven | 180 °C |
```

**What you see**

> [!example] A full example
> Text of the outer box.
> > [!warning] And a warning inside it
> > With a table:
> >
> > | Setting | Value |
> > | --- | --- |
> > | Oven | 180 °C |

To make one without typing, use **Format** › **Callout**.

## On iPad, in the dark

![[iPad - Callouts.jpg|420]]
