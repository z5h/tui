# Prolog Style Guide

This guide governs SWI-Prolog code in this repository. It targets three goals in priority order:

1. **Logical purity** — pure relational style per Triska's methodology.
2. **Readability** — for humans and for LLM agents (Claude Code) that must orient from cold-reads of source.
3. **Performance** — concessions to impurity only at measured bottlenecks, always marked.

Readers are assumed proficient in Prolog. This document focuses on conventions and decisions, not tutorial material.

---

## Module & File Structure

One module per file. File named after the module. Explicit exports.

```prolog
:- module(game_state, [
       initial_state/1,
       state_after_move/3,
       state_legal_moves/2
   ]).
:- use_module(library(clpfd)).
:- use_module(library(lists)).
```

Keep modules under ~200 clauses. If a module grows past that, it is likely doing two things — split it.

The `:- module/2` declaration is the single most important orientation artifact for cold-readers. The export list should be the complete public API; do not rely on implicit exports or `:- reexport`.


## Intra-File Organization: Section Markers

Within a file, predicates are grouped by concept or functionality. Each group is preceded by a quoted fact predicate whose name begins with `#`:

```prolog
:- module(game_state, [
       initial_state/1,
       state_after_move/3,
       state_moves/2
   ]).

'#initialization'.

initial_state(state(0, [])).

'#transitions'.

state_after_move(S0, Move, S) :-
    ...

'#queries'.

state_moves(State, Moves) :-
    ...
```

These markers are valid Prolog — each is a fact asserting its own existence, which is logically innocuous. Their practical value: any Prolog editor, tool, or LLM agent that can search for predicates will enumerate these section markers, providing a table of contents for the file.

Use `snake_case` after the `#`. Keep the names short and descriptive of the group's purpose.


## Predicate Documentation

Every exported predicate gets a PLdoc header with mode declarations:

```prolog
%% state_after_move(+StateBefore, +Move, -StateAfter) is det.
%
%  StateAfter is the game state resulting from applying Move
%  to StateBefore. Move must be legal in StateBefore.
```

For pure relations intended to work in multiple modes:

```prolog
%% list_length(?List, ?N) is nondet.
%
%  True when N is the length of List. Works in all directions
%  when used with CLP(FD) constraints on N.
```

The `is det/semidet/nondet/multi` annotation and mode markers (`+`, `-`, `?`) carry high information density per token. Do not omit them.

Internal helper predicates get a brief `%` comment explaining their role. Full PLdoc is optional for helpers.


## Naming

Relational, not imperative. The functor describes what the relation *is*, not what it *does*.

### Word-per-Argument Convention

Each argument should ideally correspond to one word in the functor, separated by single underscores:

```prolog
% Yes — one word per argument, relational
list_deduped/2          % List, DedupedList
tree_height/2           % Tree, Height
graph_path/4            % Graph, Start, End, Path
state_moves/2           % State, Moves

% No — imperative, or words don't map to arguments
remove_duplicates/2
calculate_height/2
find_path/4
get_legal_moves/2
```

### Double Underscore for Multi-Word Arguments

When an argument's role cannot be captured in a single word, use a double underscore (`__`) to separate argument phrases. Within each phrase, single underscores separate words as normal:

```prolog
list__without_duplicates/2    % List, ListWithoutDuplicates
state__legal_moves/2          % State, LegalMoves
graph__shortest_path/4        % Graph, Start, End, ShortestPath
```

Prefer the single-word form (`list_deduped/2`) when a concise word exists. The double-underscore form is for cases where compression would sacrifice clarity.

### Parameterized Mappings: `_by` / `_with`

When a predicate maps an input to an output under a parameter, and is expected to work (at least conceptually) as `(+, +, ?)`, name it `<param>_<relation_verb>_<by|with>(Param, In, Out)`. The parameter comes first, then the input, then the output. `<param>` is optional.

```prolog
integer_increment_by(Int, In, Out)
increment_by(Inc, In, Out)
solve_with(Solver, In, Out)
command_update_with(Command, In, Out)
```

A name ending in `_by` or `_with` tells the reader what to expect: parameter, in, out. The order also has practical benefits:

- **It suits `foldl/4`**, which calls its goal with the list element first, then the accumulator in and out: `foldl(command_update_with, Commands, M0, M)`.
- **It suits clause indexing.** The parameter is usually what clauses are distinguished by (each `command_update_with/3` clause handles one command), while the input usually has the same shape in every clause (any model). With the parameter first, first-argument indexing selects the matching clause directly, without trying the others or leaving choice points.

When the relation may be expected to work as `(?, ?, ?)`, don't use this form; name the relationship between the arguments instead:

```prolog
front_end_joined(Front, End, Joined) :-
    append(Front, End, Joined).
```

### Auxiliaries

Auxiliary predicates for a main predicate `foo/N` should be named `foo_/M` or `foo_aux/M`, not given unrelated names.


## Architecture: Pure Core, Impure Shell

All logic lives in pure modules — no cuts, no `assert`/`retract`, no I/O, no `->` (see exception below). Side effects are confined to a thin orchestration layer.

```prolog
% Pure: game_logic.pl
state_after_moves(S, [], S).
state_after_moves(S0, [M|Ms], S) :-
    state_after_move(S0, M, S1),
    state_after_moves(S1, Ms, S).

% Impure shell: main.pl
run_game :-
    initial_state(S0),
    read_moves(Moves),
    state_after_moves(S0, Moves, Final),
    write_state(Final).
```

The pure core can be reasoned about as equations. Execution order matters only in the shell.


## Arithmetic: CLP(FD) by Default

Use `library(clpfd)` (or `library(clpz)` if available) for all arithmetic in the pure core. This preserves generality and enables multi-directional use.

```prolog
list_length([], 0).
list_length([_|Xs], N) :-
    N #> 0,
    N1 #= N - 1,
    list_length(Xs, N1).
```

### Concession: `is/2` for Ground Arithmetic

Use `is/2` when **all** of the following hold:

- Arguments are provably ground at every call site.
- The predicate will never be called "backwards."
- The constraint overhead is measurable on a hot path.

**Always mark the concession:**

```prolog
% IMPURE: ground arithmetic — index is always computed from known K, N.
bucket_index(K, N, I) :-
    I is K mod N.
```

The `% IMPURE:` marker prevents well-meaning refactoring in either direction.


## Branching: `if_/3` by Default

Use `if_/3` with reified tests (`=/3`, `dif/3`, `memberd_t/3` from `library(reif)`) for any branching that interacts with unification or search:

```prolog
list_filtered([], _, []).
list_filtered([X|Xs], E, Ys) :-
    if_(X = E,
        list_filtered(Xs, E, Ys),
        (Ys = [X|Ys1], list_filtered(Xs, E, Ys1))
    ).
```

### Concession: `-> ;` for Ground Dispatch

Plain `-> ;` is acceptable when the test is provably ground at call time (typically in the impure shell or fully-determined dispatch). Mark it:

```prolog
% IMPURE: ground dispatch — Format is always an atom here.
format_output(json, Data) :-
    ...
format_output(text, Data) :-
    ...
```

If you can solve it with first-argument indexing (i.e., separate clauses on distinct functors), prefer that over both `if_/3` and `-> ;`.


## DCGs for List Construction

Use DCGs for any predicate that builds, consumes, or transforms a list. They eliminate manual difference-list threading and the `S0, S1, S2, ...` variable chains that are hard to track:

```prolog
expr_tokens(lit(N)) --> [N].
expr_tokens(add(A, B)) -->
    expr_tokens(A),
    [+],
    expr_tokens(B).
```

DCGs are also appropriate for state threading via semicontext notation when the "list" is really an accumulator or state pair.


## Tabling for Memoization

Use SWI's tabling instead of `assert`-based memoization. It preserves the declarative reading and avoids mutable global state:

```prolog
:- table fib/2.

fib(0, 0).
fib(1, 1).
fib(N, F) :-
    N #> 1,
    N1 #= N - 1,
    N2 #= N - 2,
    fib(N1, F1),
    fib(N2, F2),
    F #= F1 + F2.
```

Any predicate where you are tempted to cache results via `assert` should use `:- table` instead.


## Nondeterminism: Do Not Collect Then Iterate

A common LLM-generated anti-pattern is using `findall/3` (or `bagof/3`, `setof/3`) to collect all solutions to a sub-problem into a list, then iterating over that list with `member/2` or `maplist` to construct the final answer. This defeats Prolog's built-in search.

```prolog
% WRONG: collecting solutions only to re-enumerate them
all_reachable(Graph, Start, Nodes) :-
    findall(N, reachable(Graph, Start, N), Nodes).

do_something_with_reachable(Graph, Start) :-
    all_reachable(Graph, Start, Nodes),
    member(N, Nodes),
    process(N).

% RIGHT: let nondeterminism do the work
do_something_with_reachable(Graph, Start) :-
    reachable(Graph, Start, N),
    process(N).
```

Use `findall/3` and friends only when the complete collection is genuinely needed at that point — aggregate computations (count, sum, max), producing a result list that must exist as a list, or interfacing with impure code that requires a ground list. If you are collecting solutions only to feed them back into backtracking, you are laundering nondeterminism through a list for no reason.


## Formatting

### Clause Grouping

No blank lines between clauses of the same predicate. One blank line between predicates.

```prolog
list_max([X], X).
list_max([X|Xs], Max) :-
    list_max(Xs, MaxTail),
    Max #= max(X, MaxTail).

list_min([X], X).
list_min([X|Xs], Min) :-
    list_min(Xs, MinTail),
    Min #= min(X, MinTail).
```

### Indentation

4 spaces. No tabs. Clause bodies indented once from the head.

### Clause Body Order

Guards and preconditions first, then recursive or constructive goals:

```prolog
tree_insert(Key, Val, t(K,V,L,R), t(K,V,L1,R)) :-
    Key #< K,                        % guard
    tree_insert(Key, Val, L, L1).    % construction
```

### Clause Body Length

A clause body longer than ~8 goals is a smell. Extract a named helper predicate.

### Disjunctions

Avoid deeply nested `( ; )` in clause bodies. Use separate clauses or helper predicates instead.


## Impurity Markers

Any departure from purity must be commented with a `% IMPURE:` tag and a reason. This serves two purposes:

1. Human reviewers can audit impurity by grepping for the tag.
2. LLM agents will not "correct" intentional impurity back to purity (or vice versa).

```prolog
% IMPURE: side effect — writes to stdout for user feedback.
report_progress(Step) :-
    format("Step ~w complete.~n", [Step]).

% IMPURE: ground arithmetic — always called with bound arguments on hot path.
fast_hash(Key, Size, Hash) :-
    Hash is Key mod Size.
```


## Summary of Defaults and Concessions

| Decision | Default | Concede when |
|---|---|---|
| CLP(FD) vs `is/2` | CLP(FD) | Always-ground, never-reversed, measured hot path |
| `if_/3` vs `-> ;` | `if_/3` | Test provably ground; or use clause indexing instead |
| Assert-free | Yes | Never for logic; tabling covers memoization |
| Small modules | ≤200 clauses | Almost never worth violating |
| DCGs for lists | Yes | Rarely a reason not to |
| Green/red cuts | Never | No exceptions in the pure core |
| `findall/3` | Avoid | Only when the complete collection is needed as a list |

Write the pure version first. Profile. Introduce impurity only at measured bottlenecks, with `% IMPURE:` markers. This is the governing principle.
