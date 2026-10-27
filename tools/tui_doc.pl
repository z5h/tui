:- module(tui_doc, []).

/** <module> Transcribes the alias comments into alias_drawable/2's PLDoc

    swipl tools/tui_doc.pl           % rewrite the generated part
    swipl tools/tui_doc.pl check     % fail if anything is wrong or stale

tools/TUI_PLDOC.md is the format. This script loads the library (every
.pl file in prolog/), so that the alias clauses, and the lines they
start on, come from clause/3; it reads each file's lines for its
comments. tui_doc_lib.pl does the rest, without side effects.

Which files are core (loaded by library(tui)) is written here, in
core_file/1: any other file in prolog/ with an alias clause or comment
is opt-in, its section titled by its library spec. Only prolog/tui.pl is
ever written, and only if its generated part changed.

Prints its problems as `File:Line: Message`, and exits 1 if there are
any (or, checking, if the generated part is stale); 0 otherwise.
*/

:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(readutil)).
:- use_module(tui_doc_lib).

:- initialization(main, main).

core_file('tui/drawable.pl').
core_file('tui/hover.pl').
core_file('tui/image.pl').

main :-
    current_prolog_flag(argv, Argv),
    (   Argv == []
    ->  Mode = update
    ;   Argv == [check]
    ->  Mode = check
    ;   format(user_error, "Usage: swipl tools/tui_doc.pl [check]~n", []),
        halt(2)
    ),
    module_property(tui_doc, file(Self)),
    file_directory_name(Self, Tools),
    file_directory_name(Tools, Repo),
    directory_file_path(Repo, prolog, Lib),
    asserta(user:file_search_path(library, Lib)),
    library_files(Lib, Paths),
    forall(member(P, Paths), use_module(P, [])),
    convlist(lib_file(Lib), Paths, Files),
    files_problems(Files, Problems0),
    directory_file_path(Lib, 'tui.pl', Main),
    file_lines(Main, Lines0),
    (   lines_doc_lines_replaced(Lines0, Files, Lines)
    ->  Problems = Problems0
    ;   Lines = Lines0,
        append(Problems0,
               [problem(Main, 1, "no `## Aliases` line in the comment of alias_drawable/2", [])],
               Problems)
    ),
    maplist(print_problem(Repo), Problems),
    outcome(Mode, Problems, Repo, Main, Lines0, Lines, Status),
    halt(Status).

library_files(Lib, Paths) :-
    findall(P,
            ( directory_member(Lib, P0, [extensions([pl]), recursive(true)]),
              absolute_file_name(P0, P) ),
            Paths0),
    sort(Paths0, Paths).

% The file(Path, Group, Lines, Clauses) of tui_doc_lib, if Path has an
% alias clause or comment.
lib_file(Lib, Path, file(Path, Group, Lines, Clauses)) :-
    findall(PI-Line, alias_clause(Path, PI, Line), Clauses),
    file_lines(Path, Lines),
    (   Clauses \== []
    ->  true
    ;   lines_comments(Lines, [_|_])
    ),
    directory_file_path(Lib, Rel, Path),
    (   core_file(Rel)
    ->  Group = core
    ;   file_name_extension(Spec, _, Rel),
        format(string(Group), "library(~w)", [Spec])
    ).

% An alias clause loaded from Path: the Name/Arity of its first argument
% (- if that is a variable) and the line it starts on.
alias_clause(Path, PI, Line) :-
    clause(tui:alias_drawable(A, _), _, Ref),
    clause_property(Ref, file(Path)),
    clause_property(Ref, line_count(Line)),
    (   var(A)
    ->  PI = (-)
    ;   functor(A, N, Ar),
        PI = N/Ar
    ).

% IMPURE: reads the file. Split at "\n" only, so joining the lines with
% "\n" gives the file back.
file_lines(Path, Lines) :-
    read_file_to_string(Path, S, [encoding(utf8)]),
    split_string(S, "\n", "", Lines).

% IMPURE: prints.
print_problem(Repo, problem(Path, Line, Format, Args)) :-
    directory_file_path(Repo, Rel, Path),
    format(string(Msg), Format, Args),
    format("~w:~w: ~s~n", [Rel, Line, Msg]).

% IMPURE: writes prolog/tui.pl when updating, if it changed.
outcome(_, [_|_], _, _, _, _, 1) :- !.
outcome(check, [], Repo, Main, Lines0, Lines, Status) :-
    (   Lines == Lines0
    ->  Status = 0
    ;   directory_file_path(Repo, Rel, Main),
        format("~w: the generated alias documentation is stale; run swipl tools/tui_doc.pl~n", [Rel]),
        Status = 1
    ).
outcome(update, [], Repo, Main, Lines0, Lines, 0) :-
    (   Lines == Lines0
    ->  true
    ;   atomic_list_concat(Lines, '\n', Out),
        setup_call_cleanup(open(Main, write, S, [encoding(utf8)]),
                           write(S, Out),
                           close(S)),
        directory_file_path(Repo, Rel, Main),
        format("~w: updated~n", [Rel])
    ).
