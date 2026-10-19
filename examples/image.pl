:- module(image, []).

/** <module> Image — an image, through the Kitty graphics protocol

An image through the Kitty graphics protocol. The pixels are generated
(a gradient), so no file is needed; png(Bytes) or file(Path) work the
same way.

The image is drawn only once the terminal reports graphics(true) in
terminal_properties/1; elsewhere the view says so instead. + and - resize
the image: the terminal is sent a new placement, not the pixels again.
q quits.

    swipl tui run image
*/

:- use_module(library(tui)).

:- initialization(main, main).

main :-
    pixels(64-32, Bytes),
    app(_-model(false, 16-6, Bytes), view, update, _).

% A PW×PH gradient, RGB, 3 bytes a pixel: red across, green down.
pixels(PW-PH, Bytes) :-
    findall(C,
            ( between(0, PH, Y), Y < PH,
              between(0, PW, X), X < PW,
              R is X * 255 // (PW - 1),
              G is Y * 255 // (PH - 1),
              member(C, [R, G, 160]) ),
            Codes),
    string_codes(Bytes, Codes).

update(q, S, result(S)) :- !.
update(terminal_properties(Ps), C-model(_, WH, Bytes), C-model(G, WH, Bytes)) :- !,
    memberchk(graphics(G), Ps).
update(K, C-model(G, W0-H0, Bytes), C-model(G, W-H, Bytes)) :-
    key_step(K, S), !,
    W is max(2, min(60, W0 + 2 * S)),
    H is max(1, min(20, H0 + S)).
update(_, S, S).

key_step(+, 1).
key_step(-, -1).

view(_-model(G, W-H, Bytes),
     column([style([bold], "Image"),
             style([faint], "+ and - resize, q quits"),
             " ",
             Body])) :-
    graphics_size_bytes_body(G, W-H, Bytes, Body).

graphics_size_bytes_body(true, W-H, Bytes,
                         column([[box(BW-BH, thin), 1-1-image(1, rgb(64-32, Bytes), W-H)],
                                 style([faint], literal(W-H) .> " cells")])) :-
    BW is W + 2,
    BH is H + 2.
graphics_size_bytes_body(false, _, _,
                         style([faint], "This terminal does not report the Kitty graphics protocol.")).
