# Documenting aliases

Aliases (clauses of `tui:alias_drawable/2`) are not documented with PLDoc
comments of their own. PLDoc keys a comment on a predicate, so a `%!` comment
above an alias clause would document a predicate that does not exist. Instead,
each alias carries a `/*<tui>` comment, and `tools/tui_doc.pl` transcribes them
all into the PLDoc comment of `alias_drawable/2` in `prolog/tui.pl`.

The technical details (what the tool reads, how it checks, why) are in the
source of `tools/tui_doc.pl`.

## Writing an alias comment

```prolog
/*<tui> hover(Style, Term)
Draws Term, with the attributes Style added while the cursor is on it.
Style is a list of attributes.
*/
tui:alias_drawable(hover(Style, Term), hover(Style, Term, _Group)).
```

- The comment starts with `/*<tui>` at the beginning of a line, followed on
  the same line by the alias as the user writes it: its name, and its
  arguments named as in the text.
- It stands immediately before the alias's first clause. An alias with
  several clauses (`row/1`) has one comment; aliases with the same name and
  different arities (`frame/2`, `frame/3`) have one each.
- Write for the app author using the alias, not for whoever maintains it.
  Say what they see, how it shows focus, and which events it takes and
  what they become, as briefly as that allows. How the alias achieves
  it (which attributes, glyph swaps, hover groups) belongs in plain `%`
  comments by the code.

  ```
  A button, shown as ``┃Label┃``, highlighted when focused. A unit (see
  `unit(Drawable)`).

    - `' '`, `return` or `mouse(press, left)` become `button-pressed`
  ```

- The text is PLDoc wiki markup: paragraphs, lists, fenced code blocks.
  It is transcribed as written, so write it as the full documentation.
- Single backticks make code only of text that reads as a Prolog term
  (`` `[bold]` ``). For anything else, glyphs included, use double backticks:
  ` ``┃OK┃`` `, ` ``[x] Title`` `.
- Every alias in `prolog/` has a comment: any `tui:alias_drawable/2` clause
  can be used by an app, intended or not. A helper that apps should not use
  is not an alias: call a predicate of the module from the alias's body
  instead.

  ```prolog
  % Not this: private/1 is an alias any app can draw.
  tui:alias_drawable(public(X), private(X)).
  tui:alias_drawable(private(X), D) :- ...

  % This:
  tui:alias_drawable(public(X), D) :- private_drawable(X, D).
  ```

  The exception is an alias drawn only so that events can find it:
  events reach components through the aliases on the alias stack, so it
  must be an alias. Document it in one line as part of the alias it
  serves, as `scroll_view/4` is ("Part of `scroll(Size, Offset,
  Content)`; not meant to be drawn directly."), and explain it in a `%`
  comment by the code.

- Never put a `%!` comment above an alias clause.

## Where the documentation goes

The PLDoc comment of `alias_drawable/2` in `prolog/tui.pl` has a line
`%   ## Aliases`. From there to its first `@` tag (or its end), the comment is
generated; do not edit it by hand. It has a section for the core aliases
(`drawable.pl`, `hover.pl`, `image.pl`, loaded by `library(tui)`), then one
for each opt-in library, such as `library(tui/components)`, each listing its
aliases alphabetically.

## Running the tool

- `swipl tools/tui_doc.pl` rewrites the generated part of `prolog/tui.pl`.
  Run it after changing an alias comment, and commit the result with the
  change.
- `swipl tools/tui_doc.pl check` changes nothing. It fails if the generated
  part is out of date, an alias has no comment (or two), or a `%!` comment
  stands above an alias clause. The `doc` test unit runs it.
