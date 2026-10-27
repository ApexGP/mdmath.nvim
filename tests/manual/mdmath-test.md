# mdmath manual checklist

Goals: correct placement, tracking of later edits, contained failures, no leftovers.

Interaction: moving the cursor into an equation restores its source (`anticonceal`); entering
Insert mode hides every image (`hide_on_insert`); `:MdMath clear` forces a re-render;
`:messages` must never contain mdmath errors.

## 1. Inline equations

The mass-energy equation $E = mc^2$ should be vertically centered against the text on the
same line, and the text on both sides must stay visible.

A formula inside a long line must not bleed into it: $a^2 + b^2 = c^2$ is followed by more
text, and everything after it stays plain text, including on the next visual row.

## 2. Whole-line single equation

$$E = mc^2$$

## 3. Multi-line alignment

The opening and closing `$$` must each own a line, otherwise the rectangular check fails and
the block is not rendered as multi-line.

$$
\begin{aligned}
a &= b + c \\
d &= e + f \\
g &= h + i
\end{aligned}
$$

## 4. Matrix and cases

$$
A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}, \qquad
f(x) = \begin{cases} x & x > 0 \\ -x & x \le 0 \end{cases}
$$

## 5. Wide equation (dynamic size)

$$\int_{-\infty}^{\infty} e^{-x^{2}}\,\mathrm{d}x = \sqrt{\pi}$$

## 6. Non-ASCII (IPC byte length)

$$\text{中文} + \alpha = \beta$$

## 7. Error path

The equation below must render `✙` plus the error text in place: Neovim must not crash and
`:messages` must not contain a luv callback error.

$\begin{unknownenv}x\end{unknownenv}$

## 8. Scroll and recycling

Scroll up and down so equations leave the viewport and come back: they must reappear, with no
stale image on the wrong row and no duplicated placeholders.

$$
\sum_{n=1}^{\infty} \frac{1}{n^{2}} = \frac{\pi^{2}}{6}
$$

Filler paragraph, used to create scroll distance.

$$
\lim_{x \to 0} \frac{\sin x}{x} = 1
$$

Filler paragraph, used to create scroll distance.

$$
\int_{0}^{1} x^{n}\,\mathrm{d}x = \frac{1}{n+1}
$$

Filler paragraph, used to create scroll distance.

$$
e^{i\pi} + 1 = 0
$$

Filler paragraph, used to create scroll distance.

$$
\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}
$$

Filler paragraph, used to create scroll distance.

$$
\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
$$

Filler paragraph, used to create scroll distance.

$$
\frac{\partial u}{\partial t} = \alpha \nabla^{2} u
$$

Filler paragraph, used to create scroll distance.

$$
H(X) = -\sum_{i} p(x_i) \log_2 p(x_i)
$$

## 9. Edit tracking

Insert or delete lines below this one: the equations above must move with the text instead of
staying on their old rows.

Placeholder line A

Placeholder line B

Placeholder line C
