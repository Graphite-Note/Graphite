# Code in every language

A fenced block in each language Graphite highlights (`CodeLanguage.all`, with the aliases CUDA and SystemVerilog), drawn as Obsidian draws code: a box with the language's colours, in each code theme of Settings › Editor.

## C

```c
int main(void) {
    printf("%d\n", 42);
    return 0;
}
```

## C++

```cpp
template <typename T> T square(T x) { return x * x; }
std::vector<int> values{1, 2, 3};
```

## CUDA

```cuda
__global__ void add(float *a, float *b) {
    int i = threadIdx.x;
    a[i] += b[i];
}
```

## Objective-C

```objc
@interface Sampler : NSObject
- (double)rate;
@end
```

## C#

```csharp
public record Sample(double Time, double Value);
var first = samples.First();
```

## Java

```java
final class Filter {
    double apply(double x) { return 0.5 * x; }
}
```

## Kotlin

```kotlin
data class Sample(val time: Double, val value: Double)
val rate = 1.0 / period
```

## JavaScript

```js
const rate = 1 / period;
console.log(`rate: ${rate}`);
```

## TypeScript

```ts
interface Sample { time: number; value: number }
const samples: Sample[] = [];
```

## Python

```python
def nyquist(rate: float) -> float:
    return rate / 2
```

## Swift

```swift
struct Sample { let time: Double; let value: Double }
let rate = 1 / period
```

## Rust

```rust
fn nyquist(rate: f64) -> f64 {
    rate / 2.0
}
```

## Go

```go
func nyquist(rate float64) float64 {
	return rate / 2
}
```

## Shell

```bash
for file in *.md; do
  echo "$file"
done
```

## JSON

```json
{"rate": 44100, "channels": [1, 2], "stereo": true}
```

## YAML

```yaml
rate: 44100
channels:
  - left
  - right
```

## SQL

```sql
SELECT name, rating FROM books WHERE rating >= 4 ORDER BY rating DESC;
```

## VHDL

```vhdl
architecture rtl of inverter is
begin
  y <= not a;
end architecture;
```

## SystemVerilog

```systemverilog
always_ff @(posedge clk) begin
  q <= d;
end
```

## Assembly

```asm
mov eax, 1
add eax, ebx
ret
```

## MATLAB

```matlab
x = linspace(0, 1, 100);
plot(x, sin(2*pi*5*x));
```

## LaTeX

```latex
\begin{equation}
  f_s > 2 f_{max}
\end{equation}
```

## Markdown

```markdown
# A heading

- a **bold** item
```

## HTML

```html
<p class="note">A <em>paragraph</em>.</p>
```

## CSS

```css
.note { color: #1b7f79; font-weight: 600; }
```

## Ruby

```ruby
def nyquist(rate) = rate / 2.0
puts nyquist(44_100)
```

## Lua

```lua
local function nyquist(rate)
  return rate / 2
end
```

## No language

```
plain text, not highlighted
```
