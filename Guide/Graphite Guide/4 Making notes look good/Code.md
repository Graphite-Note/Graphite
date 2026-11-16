---
tags:
  - guide/markdown
---
# Code

Code goes between three backticks, with the name of its language after the first three, for colours.

**Copy this**

````markdown
```python
def cooking_time(weight_in_grams):
    """Twenty minutes a pound, and twenty more."""
    return weight_in_grams / 450 * 20 + 20

print(cooking_time(1800))
```
````

**What you see**

```python
def cooking_time(weight_in_grams):
    """Twenty minutes a pound, and twenty more."""
    return weight_in_grams / 450 * 20 + 20

print(cooking_time(1800))
```

Many languages are coloured, among them Python, JavaScript, Swift, C, Java, HTML, CSS, JSON, SQL, shell scripts and LaTeX:

```json
{ "recipe": "Pancakes", "serves": 2, "vegetarian": true }
```

```sql
SELECT title FROM recipes WHERE minutes < 30 ORDER BY title;
```

## Code themes

Settings › Editor › **Code Theme** picks the colours: **Obsidian**, **One Monokai**, **Dracula**, **GitHub**, **Solarized** or **Xcode**, each with a light and a dark version.

> [!info] Colours while writing
> Code is coloured in the reading view. While you write, a code block is shown in a plain monospaced font.

To make a code block without typing the backticks: **Insert** › **Code Block** (touch and hold in the text on iPad and iPhone, right-click on the Mac).
