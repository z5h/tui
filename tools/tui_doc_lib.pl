:- module(tui_doc_lib,
          [ lines_comments/2,
            files_problems/2,
            files_doc_lines/3,
            lines_doc_lines_replaced/3
          ]).

/** <module> Alias documentation: reading, checking and transcribing

The pure part of tools/tui_doc.pl; tools/TUI_PLDOC.md is the format.
Files are given as lines (strings, without their line ends), so that a
file is read and written back unchanged but for the generated part.

The tool does not parse the files as Prolog. A `/*<tui>` comment is
found by its first line alone: one starting with `/*<tui>`, the rest of
which is the documented key. It ends at a line that is `*/` alone. The
clauses come from the loaded code instead (clause/3), as Name/Arity of
their first argument and the line they start on, so the head itself is
never read either. A comment documents the clause starting on the line
after its `*/`; the key's Name/Arity must be that clause's.

A file is file(Path, Group, Lines, Clauses), Group being `core` or the
library spec (a string, e.g. "library(tui/components)") of an opt-in
file, and Clauses a list of PI-Line, one per alias clause.

Problems are problem(Path, Line, Format, Args), printed as
`Path:Line: Message`.
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).


'#comments'.

%!  lines_comments(+Lines, -Comments) is det.
%
%   Comments are the `/*<tui>` comments of a file's Lines, in order,
%   each comment(Start, Key, Body, End) or unclosed(Start). Start and
%   End are the line numbers of its first and last line, Key its key as
%   written (a string), and Body the lines between, as written.

lines_comments(Lines, Comments) :-
    numbered(Lines, 1, Numbered),
    numbered_comments(Numbered, Comments).

numbered([], _, []).
numbered([L|Ls], N, [N-L|NLs]) :-
    succ(N, N1),
    numbered(Ls, N1, NLs).

numbered_comments([], []).
numbered_comments([N-L|NLs], Comments) :-
    (   string_concat("/*<tui>", Rest, L)
    ->  normalize_space(string(Key), Rest),
        Comments = [C|Cs],
        comment_body(NLs, N, Key, C, NLs1),
        numbered_comments(NLs1, Cs)
    ;   numbered_comments(NLs, Comments)
    ).

comment_body(NLs, Start, Key, Comment, Rest) :-
    (   append(Body0, [End-Close|Rest], NLs),
        split_string(Close, "", " \t", ["*/"])
    ->  pairs_values(Body0, Body),
        Comment = comment(Start, Key, Body, End)
    ;   Comment = unclosed(Start),
        Rest = []
    ).


'#checks'.

%!  files_problems(+Files, -Problems) is det.
%
%   Problems are what is wrong with the alias comments of Files: a
%   comment unclosed, with a key that is not a term, or not directly
%   above an alias clause with the key's Name/Arity; an alias with no
%   comment, or more than one; a `%!` comment above an alias clause.

files_problems(Files, Problems) :-
    foldl(file_problems, Files, Problems0, []),
    findall(PI-(Path-Line),
            ( member(file(Path, _, _, Clauses), Files),
              member(PI-Line, Clauses) ),
            PIClauses),
    findall(PI-(Path-Start),
            ( member(file(Path, _, Lines, _), Files),
              lines_comments(Lines, Cs),
              member(comment(Start, Key, _, _), Cs),
              key_pi(Key, PI) ),
            PIComments),
    coverage_problems(PIClauses, PIComments, Problems1),
    append(Problems0, Problems1, Problems).

file_problems(file(Path, _, Lines, Clauses), Ps0, Ps) :-
    lines_comments(Lines, Comments),
    foldl(comment_problems(Path, Clauses), Comments, Ps0, Ps1),
    foldl(pldoc_problems(Path, Lines), Clauses, Ps1, Ps).

comment_problems(Path, _, unclosed(Start), Ps0, Ps) :-
    Ps0 = [problem(Path, Start, "/*<tui> comment without a line `*/`", [])|Ps].
comment_problems(Path, Clauses, comment(Start, Key, _, End), Ps0, Ps) :-
    succ(End, Next),
    (   \+ key_pi(Key, _)
    ->  Ps0 = [problem(Path, Start, "key `~s` is not a term", [Key])|Ps]
    ;   \+ memberchk(_-Next, Clauses)
    ->  Ps0 = [problem(Path, Start, "/*<tui> comment not directly above an alias clause", [])|Ps]
    ;   key_pi(Key, PI),
        memberchk(CPI-Next, Clauses),
        PI \== CPI
    ->  Ps0 = [problem(Path, Start, "key `~s` is ~q, its clause is ~q", [Key, PI, CPI])|Ps]
    ;   key_pi(Key, PI),
        member(PI-Earlier, Clauses),
        Earlier < Next
    ->  Ps0 = [problem(Path, Start, "/*<tui> comment not above the first clause of ~q", [PI])|Ps]
    ;   Ps0 = Ps
    ).

key_pi(Key, Name/Arity) :-
    catch(term_string(T, Key), _, fail),
    callable(T),
    functor(T, Name, Arity).

% A `%!` line in the % comment block directly above an alias clause.
pldoc_problems(Path, Lines, _-Line, Ps0, Ps) :-
    succ(Above, Line),
    length(Prefix, Above),
    append(Prefix, _, Lines),
    reverse(Prefix, Up),
    (   append(Block, _, Up),
        maplist(comment_line, Block),
        member(L, Block),
        string_concat("%!", _, L)
    ->  Ps0 = [problem(Path, Line, "`%!` comment above an alias clause", [])|Ps]
    ;   Ps0 = Ps
    ).

comment_line(L) :-
    string_concat("%", _, L).

% Each alias has one comment, above its first clause.
coverage_problems(PIClauses, PIComments, Problems) :-
    keysort(PIClauses, Sorted),
    group_pairs_by_key(Sorted, ByPI),
    findall(P,
            ( member(PI-Places, ByPI),
              alias_problem(PI, Places, PIComments, P) ),
            Problems).

alias_problem(PI, Places, PIComments, P) :-
    findall(Path-Start, member(PI-(Path-Start), PIComments), Comments),
    min_member(Path-Line, Places),
    (   Comments == []
    ->  P = problem(Path, Line, "alias ~q has no /*<tui> comment", [PI])
    ;   Comments = [_, _|_]
    ->  Comments = [_, Path2-Start2|_],
        P = problem(Path2, Start2, "alias ~q has more than one /*<tui> comment", [PI])
    ).


'#transcription'.

%!  files_doc_lines(+Files, +Indent, -DocLines) is det.
%
%   DocLines are the generated part of the comment of alias_drawable/2:
%   a section for the core aliases, then one per opt-in library in
%   alphabetical order, each listing its aliases alphabetically by key,
%   with their comments' bodies. Each line is "%" followed by Indent, a
%   string of spaces, or "%" alone if blank.

files_doc_lines(Files, Indent, DocLines) :-
    findall(Group-(Key-Body),
            ( member(file(_, Group, Lines, _), Files),
              lines_comments(Lines, Cs),
              member(comment(_, Key, Body, _), Cs) ),
            Entries),
    keysort(Entries, Sorted),
    group_pairs_by_key(Sorted, ByGroup0),
    (   selectchk(core-Core, ByGroup0, ByGroup1)
    ->  ByGroup = [core-Core|ByGroup1]
    ;   ByGroup = ByGroup0
    ),
    foldl(group_lines(Indent), ByGroup, Lines0, []),
    DocLines = ["%"|Lines0].

group_lines(Indent, Group-Entries0, Ls0, Ls) :-
    group_title(Group, Title),
    format(string(H), "%~s### ~s", [Indent, Title]),
    Ls0 = [H, "%"|Ls1],
    keysort(Entries0, Entries),
    foldl(entry_lines(Indent), Entries, Ls1, Ls).

group_title(core, "Core") :- !.
group_title(Library, Library).

entry_lines(Indent, Key-Body0, Ls0, Ls) :-
    format(string(H), "%~s#### `~s`", [Indent, Key]),
    trimmed_blank_lines(Body0, Body),
    maplist(doc_line(Indent), Body, BodyLines),
    append([[H, "%"], BodyLines, ["%"]], Entry),
    append(Entry, Ls, Ls0).

trimmed_blank_lines(Lines0, Lines) :-
    drop_blank(Lines0, Lines1),
    reverse(Lines1, Rev0),
    drop_blank(Rev0, Rev),
    reverse(Rev, Lines).

drop_blank([L|Ls], Rest) :-
    blank(L),
    !,
    drop_blank(Ls, Rest).
drop_blank(Ls, Ls).

blank(L) :-
    split_string(L, "", " \t", [""]).

doc_line(_, L0, "%") :-
    blank(L0),
    !.
doc_line(Indent, L0, L) :-
    string_trimmed_end(L0, L1),
    atomics_to_string(["%", Indent, L1], L).

string_trimmed_end(S0, S) :-
    string_codes(S0, Cs0),
    reverse(Cs0, R0),
    drop_spaces(R0, R),
    reverse(R, Cs),
    string_codes(S, Cs).

drop_spaces([C|Cs], Rest) :-
    code_type(C, space),
    !,
    drop_spaces(Cs, Rest).
drop_spaces(Cs, Cs).


'#splice'.

%!  lines_doc_lines_replaced(+Lines0, +Files, -Lines) is semidet.
%
%   Lines is the file of alias_drawable/2's comment, Lines0, with the
%   generated part of the comment rewritten from Files: the lines after
%   its `## Aliases` line, up to its first `@` tag or its end. Fails if
%   the comment has no such line. The generated lines are indented as
%   the `## Aliases` line is.

lines_doc_lines_replaced(Lines0, Files, Lines) :-
    append(Pre, [Hdr|Rest], Lines0),
    string_concat("%!", R, Hdr),
    normalize_space(string(S), R),
    string_concat("alias_drawable(", _, S),
    append(Mid, [Heading|Tail], Rest),
    maplist(comment_line, Mid),
    heading_indent(Heading, Indent),
    !,
    generated(Tail, _Old, After),
    files_doc_lines(Files, Indent, Doc),
    append([Pre, [Hdr|Mid], [Heading|Doc], After], Lines).

heading_indent(Heading, Indent) :-
    string_concat("%", R, Heading),
    string_concat(Indent, "## Aliases", R),
    split_string(Indent, "", " ", [""]).

generated([L|Ls], [L|Old], After) :-
    comment_line(L),
    \+ tag_line(L),
    !,
    generated(Ls, Old, After).
generated(After, [], After).

tag_line(L) :-
    string_concat("%", R, L),
    split_string(R, "", " ", [T]),
    string_concat("@", _, T).
