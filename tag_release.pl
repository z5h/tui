:- module(tag_release, []).

/** <module> Tag a release of this pack

    swipl tag_release.pl [--sign]

version(V) in pack.pl is the single source of truth for the version.
This script shows the version on the pack server (if any), the newest
V* tag on the remote and the local version, asks to continue, then
creates the tag V<version> on HEAD and pushes it. --sign makes a signed
tag (git tag -s), as the SWI-Prolog pack guide recommends.

It refuses if tracked files have uncommitted changes, or if the local
version is not newer than both the published version and the newest
tag: a published version must never be published again. The remote is
the one whose URL is pack.pl's download(URL).

Then register the release with: swipl pack publish URL
*/

:- use_module(library(main)).
:- use_module(library(http/http_open)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).

:- initialization(main, main).

main(Argv) :-
    (   Argv == []
    ->  Sign = false
    ;   Argv == ['--sign']
    ->  Sign = true
    ;   format(user_error, "usage: swipl tag_release.pl [--sign]~n", []),
        halt(1)
    ),
    pack_terms(Terms),
    memberchk(name(Pack), Terms),
    memberchk(version(Local), Terms),
    memberchk(download(URL), Terms),
    url_remote(URL, Remote),
    clean_or_halt,
    pack_published(Pack, Published),
    remote_newest_tag(Remote, Tagged),
    format("published version is ~w~n", [Published]),
    format("newest tag on ~w is ~w~n", [Remote, Tagged]),
    format("local version is ~w~n", [Local]),
    newer_or_halt(Local, Published),
    newer_or_halt(Local, Tagged),
    head_pushed_warning(Remote),
    atom_concat('V', Local, Tag),
    (   confirmed(Tag)
    ->  tag_pushed(Sign, Tag, Local, Remote),
        format("~nNow register it: swipl pack publish ~w~n", [URL])
    ;   format("Nothing done.~n", []),
        halt(1)
    ).


'#pack'.

pack_terms(Terms) :-
    read_file_to_terms('pack.pl', Terms, []).

% The newest version of Pack on the pack server, or none.
pack_published(Pack, Published) :-
    format(codes(Query), "~q.~n", [versions([Pack], [])]),
    setup_call_cleanup(
        http_open('https://www.swi-prolog.org/pack/query', In,
                  [ post(codes(application/'x-prolog', Query)) ]),
        ( set_stream(In, encoding(utf8)),
          read(In, Reply) ),
        close(In)),
    (   Reply = true(Packs),             % Pack and its dependencies
        memberchk(Pack-Versions, Packs),
        pairs_keys(Versions, Vs),
        Vs \== []
    ->  max_member(version_before, Published, Vs)
    ;   Reply = true(_)
    ->  Published = none
    ;   format(user_error, "Unexpected reply from the pack server: ~q~n", [Reply]),
        halt(1)
    ).


'#versions'.

% Versions compare as lists of integers.
version_numbers(V, Ns) :-
    atomic_list_concat(Parts, '.', V),
    maplist(atom_number, Parts, Ns).

version_before(V1, V2) :-
    version_numbers(V1, N1),
    version_numbers(V2, N2),
    N1 @< N2.

newer_or_halt(_, none) :- !.
newer_or_halt(Local, Other) :-
    (   version_before(Other, Local)
    ->  true
    ;   format(user_error,
               "Refusing: the local version ~w is not newer than ~w. Raise version/1 in pack.pl.~n",
               [Local, Other]),
        halt(1)
    ).


'#git'.

% The remote whose URL is URL.
url_remote(URL, Remote) :-
    git_lines([remote, '-v'], Lines),
    (   member(Line, Lines),
        split_string(Line, " \t", " \t", [R, U | _]),
        atom_string(URL, U)
    ->  atom_string(Remote, R)
    ;   format(user_error, "No git remote has the URL ~w (pack.pl download/1).~n", [URL]),
        halt(1)
    ).

clean_or_halt :-
    git_lines([status, '--porcelain', '--untracked-files=no'], Lines),
    (   Lines == []
    ->  true
    ;   format(user_error, "Refusing: tracked files have uncommitted changes.~n", []),
        halt(1)
    ).

% The newest V<version> tag on Remote, or none.
remote_newest_tag(Remote, Newest) :-
    git_lines(['ls-remote', '--tags', '--refs', Remote, 'V*'], Lines),
    convlist(line_tag_version, Lines, Vs),
    (   Vs == []
    ->  Newest = none
    ;   max_member(version_before, Newest, Vs)
    ).

line_tag_version(Line, V) :-
    split_string(Line, "\t", "", [_, Ref]),
    string_concat("refs/tags/V", VS, Ref),
    atom_string(V, VS),
    catch(version_numbers(V, _), _, fail).

head_pushed_warning(Remote) :-
    git_lines([fetch, '--quiet', Remote], _),
    git_lines([branch, '-r', '--contains', 'HEAD'], Branches),
    atom_concat(Remote, '/', Prefix),
    (   member(B, Branches),
        split_string(B, "", " ", [B1]),
        string_concat(Prefix, _, B1)
    ->  true
    ;   format("warning: HEAD is not on any branch of ~w yet; push it too.~n", [Remote])
    ).

confirmed(Tag) :-
    format("tag HEAD as ~w and push it? y/n ", [Tag]),
    flush_output,
    read_line_to_string(user_input, Answer),
    string_lower(Answer, A),
    memberchk(A, ["y", "yes"]).

tag_pushed(Sign, Tag, Version, Remote) :-
    (   Sign == true
    ->  Flag = '-s'
    ;   Flag = '-a'
    ),
    format(atom(Message), "Version ~w", [Version]),
    git_lines([tag, Flag, Tag, '-m', Message], _),
    git_lines([push, Remote, Tag], _),
    format("Tagged and pushed ~w.~n", [Tag]).

% IMPURE: runs git with Args; Lines is its output. A failing git ends
% the script with git's status.
git_lines(Args, Lines) :-
    setup_call_cleanup(
        process_create(path(git), Args, [stdout(pipe(Out)), process(Pid)]),
        read_string(Out, _, Output),
        close(Out)),
    process_wait(Pid, Status),
    (   Status == exit(0)
    ->  split_string(Output, "\n", "", Lines0),
        exclude(==(""), Lines0, Lines)
    ;   format(user_error, "git ~w failed (~w).~n", [Args, Status]),
        halt(1)
    ).
