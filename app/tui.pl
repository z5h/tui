:- module(app_tui, []).

/** <module> swipl tui — the examples of library(tui)

    swipl tui examples            list the examples
    swipl tui run NAME [ARG ...]  run an example
    swipl tui source NAME         print an example's source

Installed as a pack, SWI-Prolog finds this file through the pack's app
directory. From a clone, run it as swipl app/tui.pl ....

An example runs in a child swipl, with the terminal handed over, and
the library beside the examples (this pack's prolog directory) first on
the library path, so a clone runs its own copy.
*/

:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(process)).
:- use_module(library(readutil)).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   argv_command(Argv)
    ->  true
    ;   usage,
        halt(1)
    ).

argv_command([examples]) :-
    examples_listed.
argv_command([run, Name | Args]) :-
    name_args_run(Name, Args).
argv_command([source, Name]) :-
    name_source_printed(Name).

usage :-
    format(user_error,
           "usage: swipl tui examples~n       swipl tui run NAME [ARG ...]~n       swipl tui source NAME~n",
           []).


'#examples'.

% The pack's directory: this file is in its app directory.
pack_directory(Dir) :-
    module_property(app_tui, file(File)),
    file_directory_name(File, AppDir),
    file_directory_name(AppDir, Dir).

pack_subdirectory(Sub, Dir) :-
    pack_directory(Pack),
    directory_file_path(Pack, Sub, Dir).

% Name is an example, in File. The examples are the .pl files in
% examples/, less the libraries they use (NAME_lib.pl).
example_file(Name, File) :-
    pack_subdirectory(examples, Dir),
    directory_files(Dir, Entries),
    msort(Entries, Sorted),
    member(Entry, Sorted),
    file_name_extension(Name, pl, Entry),
    \+ sub_atom(Name, _, _, 0, '_lib'),
    directory_file_path(Dir, Entry, File).

name_example_file(Name, File) :-
    (   example_file(Name, File)
    ->  true
    ;   format(user_error, "No example ~w. These are: swipl tui examples~n", [Name]),
        halt(1)
    ).

% The title of the example's module documentation, /** <module> Title.
file_title(File, Title) :-
    read_file_to_string(File, Text, []),
    split_string(Text, "\n", "", Lines),
    member(Line, Lines),
    sub_string(Line, Before, _, After, "<module> "),
    Before >= 0, !,
    sub_string(Line, _, After, 0, Title).
file_title(_, "").


'#commands'.

examples_listed :-
    findall(Name-File, example_file(Name, File), Examples),
    foldl(name_width_max, Examples, 0, Width),
    forall(member(Name-File, Examples),
           (   file_title(File, Title),
               format("~w~t~*|  ~w~n", [Name, Width, Title])
           )).

name_width_max(Name-_, W0, W) :-
    atom_length(Name, L),
    W is max(W0, L).

% IMPURE: runs the example in a child swipl, and exits with its status.
% The example's arguments follow a --, so that swipl does not take an
% argument ending in .pl as a file to load.
name_args_run(Name, Args0) :-
    name_example_file(Name, File),
    (   Args0 = ['--' | Args]
    ->  true
    ;   Args = Args0
    ),
    pack_subdirectory(prolog, Lib),
    atom_concat('library=', Lib, LibPath),
    current_prolog_flag(executable, Swipl),
    append(['-p', LibPath, File, '--'], Args, Argv),
    process_create(Swipl, Argv, [process(Pid)]),
    process_wait(Pid, Status),
    (   Status = exit(Code)
    ->  halt(Code)
    ;   halt(1)
    ).

name_source_printed(Name) :-
    name_example_file(Name, File),
    setup_call_cleanup(open(File, read, In),
                       copy_stream_data(In, user_output),
                       close(In)).
