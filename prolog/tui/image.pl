:- module(tui_image,
          [
            images_sent_actions/4
          ]).

/** <module> Images

The core alias `image(Id, Source, Size)`, documented under
tui:alias_drawable/2. This module is internal.

Images through the Kitty graphics protocol, using its Unicode
placeholders: https://sw.kovidgoyal.net/kitty/graphics-protocol/

An image is uploaded to the terminal once, under an id, with a virtual
placement of W×H cells. It is then shown by drawing placeholder cells:
U+10EEEE followed by diacritics for the cell's row and column within the
image, with the image id as the 24-bit foreground colour. To everything
else, the cells are text: they diff, erase, clip and layer as text does.

image(Id, Source, W-H) draws the placeholders. Because it is an alias,
it is on the stack of each of its cells, and the loop collects the
images a frame needs from there; see images_sent_actions/4 for what is
sent to the terminal.
*/

:- multifile tui:alias_drawable/2.


'#drawable'.

/*<tui> image(Id, Source, Size)
The image Source, under Id, shown in W×H cells, Size being W-H. Id is
an integer from 1 to 16777215, unique to the image; W and H are from 1
to 297. Source is one of:

  - `png(Bytes)`: a PNG file's contents
  - `rgba(PW-PH, Bytes)`: PW×PH pixels, 4 bytes each
  - `rgb(PW-PH, Bytes)`: PW×PH pixels, 3 bytes each
  - `file(Path)`: a file the terminal reads itself (PNG); only when the
    terminal runs on the same machine

Bytes is a string or code list of octets (0..255), as read from a
binary stream. Text decoded on reading (e.g. as UTF-8) gives a
corrupted image; this cannot be detected.

Only terminals supporting the Kitty graphics protocol show images; see
`graphics(Bool)` in the `terminal_properties(Properties)` event.
Elsewhere its cells show as unknown characters.
*/
tui:alias_drawable(image(Id, _, W-H), style([fg(R, G, B)], column(Rows))) :-
    must_be(between(1, 16777215), Id),
    diacritics(Ds),
    length(Ds, N),
    must_be(between(1, N), W),
    must_be(between(1, N), H),
    id_rgb(Id, R, G, B),
    W1 is W - 1,
    H1 is H - 1,
    findall(chars(Row),
            ( between(0, H1, Y),
              findall(C, ( between(0, W1, X),
                           row_column_placeholder(Y, X, C) ),
                      Row) ),
            Rows).

id_rgb(Id, R, G, B) :-
    R is (Id >> 16) /\ 0xFF,
    G is (Id >> 8) /\ 0xFF,
    B is Id /\ 0xFF.

% A placeholder cell: one character on screen, three codepoints. Every
% cell says where it is (Kitty can infer it from the previous cell, but
% a repainted run may start partway through an image).
row_column_placeholder(Row, Column, C) :-
    diacritics(Ds),
    nth0(Row, Ds, RD),
    nth0(Column, Ds, CD),
    atom_codes(C, [0x10EEEE, RD, CD]).

% Kitty's row and column diacritics, in order: the Nth stands for N.
% From kitty's gen/rowcolumn-diacritics.txt.
diacritics([
    0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F, 0x0346,
    0x034A, 0x034B, 0x034C, 0x0350, 0x0351, 0x0352, 0x0357, 0x035B, 0x0363,
    0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369, 0x036A, 0x036B, 0x036C,
    0x036D, 0x036E, 0x036F, 0x0483, 0x0484, 0x0485, 0x0486, 0x0487, 0x0592,
    0x0593, 0x0594, 0x0595, 0x0597, 0x0598, 0x0599, 0x059C, 0x059D, 0x059E,
    0x059F, 0x05A0, 0x05A1, 0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4,
    0x0610, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617, 0x0657,
    0x0658, 0x0659, 0x065A, 0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8,
    0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF, 0x06E0, 0x06E1, 0x06E2, 0x06E4,
    0x06E7, 0x06E8, 0x06EB, 0x06EC, 0x0730, 0x0732, 0x0733, 0x0735, 0x0736,
    0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743, 0x0745, 0x0747, 0x0749,
    0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE, 0x07EF, 0x07F0, 0x07F1, 0x07F3,
    0x0816, 0x0817, 0x0818, 0x0819, 0x081B, 0x081C, 0x081D, 0x081E, 0x081F,
    0x0820, 0x0821, 0x0822, 0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082A,
    0x082B, 0x082C, 0x082D, 0x0951, 0x0953, 0x0954, 0x0F82, 0x0F83, 0x0F86,
    0x0F87, 0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75, 0x1A76,
    0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D, 0x1B6E,
    0x1B6F, 0x1B70, 0x1B71, 0x1B72, 0x1B73, 0x1CD0, 0x1CD1, 0x1CD2, 0x1CDA,
    0x1CDB, 0x1CE0, 0x1DC0, 0x1DC1, 0x1DC3, 0x1DC4, 0x1DC5, 0x1DC6, 0x1DC7,
    0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1, 0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5,
    0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9, 0x1DDA, 0x1DDB, 0x1DDC, 0x1DDD, 0x1DDE,
    0x1DDF, 0x1DE0, 0x1DE1, 0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE,
    0x20D0, 0x20D1, 0x20D4, 0x20D5, 0x20D6, 0x20D7, 0x20DB, 0x20DC, 0x20E1,
    0x20E7, 0x20E9, 0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2,
    0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6, 0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA, 0x2DEB,
    0x2DEC, 0x2DED, 0x2DEE, 0x2DEF, 0x2DF0, 0x2DF1, 0x2DF2, 0x2DF3, 0x2DF4,
    0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA, 0x2DFB, 0x2DFC, 0x2DFD,
    0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D, 0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1,
    0xA8E2, 0xA8E3, 0xA8E4, 0xA8E5, 0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA,
    0xA8EB, 0xA8EC, 0xA8ED, 0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2,
    0xAAB3, 0xAAB7, 0xAAB8, 0xAABE, 0xAABF, 0xAAC1, 0xFE20, 0xFE21, 0xFE22,
    0xFE23, 0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186,
    0x1D187, 0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242,
    0x1D243, 0x1D244
]).


'#sending'.

%!  images_sent_actions(+Images, +Sent0, -Actions, -Sent) is det.
%
%  What to send so that the terminal has Images, image(Id, Source, W-H)
%  terms, given that it has Sent0. Actions are, in order:
%
%    * transmit(Id, Source) — upload Source under Id, replacing any
%      earlier image with that Id
%    * place(Id, W-H)       — the virtual placement of Id, W×H cells
%      (replacing any earlier one)
%
%  An image already sent needs nothing; one sent at another size needs a
%  new placement only. Sent is Sent0 with Images' entries replacing those
%  with the same Id: the terminal keeps images that are no longer drawn,
%  so drawing them again sends nothing.
images_sent_actions(Images, Sent0, Actions, Sent) :-
    foldl(image_sent_actions, Images, Sent0-Actions, Sent-[]).

image_sent_actions(image(Id, S, WH), Sent0-As0, Sent-As) :-
    (   memberchk(image(Id, S, WH), Sent0)
    ->  Sent = Sent0,
        As0 = As
    ;   (   memberchk(image(Id, S, _), Sent0)
        ->  As0 = [place(Id, WH) | As]
        ;   As0 = [transmit(Id, S), place(Id, WH) | As]
        ),
        exclude(id_image(Id), Sent0, Others),
        Sent = [image(Id, S, WH) | Others]
    ).

id_image(Id, image(Id, _, _)).
