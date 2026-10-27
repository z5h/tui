:- module(doc_check, []).

/** <module> Checks that the documentation is PLDoc

    swipl -p library=prolog test/doc_check.pl

Loads every Prolog file of the repository with PLDoc collecting
comments, and reports, one per line:

  * any warning or error while loading, which includes structured
    comments PLDoc cannot process (e.g. an invalid mode line);
  * a file without a module comment;
  * an exported predicate of the library (prolog/) without a structured
    comment, looked up in the module that defines it.

Exits 0 if there is nothing to report, 1 otherwise. Runs in a process of
its own, as PLDoc only collects comments from files loaded after
doc_collect(true). test/test_tui.pl runs it.
*/

:- use_module(library(pldoc)).
:- use_module(library(pldoc/doc_process), [doc_comment/4]).
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(lists)).

:- doc_collect(true).

:- initialization(main, main).

:- dynamic problem/1.

:- multifile user:message_hook/3.

% Warnings and errors are collected, to be reported once at the end.
user:message_hook(Message, Kind, Lines) :-
    memberchk(Kind, [warning, error]),
    message_to_codes(Message, Kind, Lines, Codes),
    assertz(problem(Codes)).

message_to_codes(_, Kind, Lines, Codes) :-
    with_output_to(codes(Codes),
                   print_message_lines(current_output, kind(Kind), Lines)).

% This file is loaded before it turns collecting on, so it is not
% checked itself.
main :-
    repository_files(Files0),
    module_property(doc_check, file(Self)),
    exclude(==(Self), Files0, Files),
    forall(member(F, Files), load_quietly(F)),
    forall(member(F, Files), file_documented(F)),
    forall(library_export(M, PI), export_documented(M, PI)),
    findall(P, problem(P), Problems),
    forall(member(P, Problems), format("~s~n", [P])),
    (   Problems == []
    ->  halt(0)
    ;   halt(1)
    ).

% Every Prolog file of the repository, run from its root: those in its
% directories, and at the top but pack.pl (metadata, not a module). Not
% from git, which CI images may lack.
repository_files(Files) :-
    findall(F,
            (   member(Dir, [prolog, app, examples, bench, test, tools]),
                exists_directory(Dir),
                directory_member(Dir, F0, [extensions([pl]), recursive(true)]),
                absolute_file_name(F0, F)
            ;   directory_member('.', F0, [extensions([pl])]),
                file_base_name(F0, Base),
                Base \== 'pack.pl',
                absolute_file_name(F0, F)
            ),
            Files0),
    sort(Files0, Files).

% Examples and scripts run main on initialization(main, main); loading
% them here does not, as this process halts first.
load_quietly(File) :-
    catch(use_module(File, []), E,
          ( message_to_codes(E, error, ['~p'-[E]], Codes),
            assertz(problem(Codes)) )).

file_documented(File) :-
    (   module_property(M, file(File)),
        doc_comment(M:module(_), _, _, _)
    ->  true
    ;   format(codes(Codes), "~w: no module comment", [File]),
        assertz(problem(Codes))
    ).

% M exports PI, defined in prolog/.
library_export(D, PI) :-
    absolute_file_name(library(tui), Main, [file_type(prolog), access(read)]),
    file_directory_name(Main, LibDir),
    module_property(M, file(File)),
    sub_atom(File, 0, _, _, LibDir),
    module_property(M, exports(Exports)),
    member(N/A, Exports),
    functor(H, N, A),
    (   predicate_property(M:H, imported_from(D0))
    ->  D = D0
    ;   D = M
    ),
    PI = N/A.

export_documented(M, N/A) :-
    (   (   doc_comment(M:N/A, _, _, _)
        ;   A >= 2,
            A2 is A - 2,
            doc_comment(M:N//A2, _, _, _)
        )
    ->  true
    ;   format(codes(Codes), "~w:~w/~w: exported, but no structured comment", [M, N, A]),
        assertz(problem(Codes))
    ).
