
(*
copyright (c) 2013-2015, simon cruanes
all rights reserved.

redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Very Simple Parser Combinators} *)

type 'a or_error = [`Ok of 'a | `Error of string]

type input = {
  is_done : unit -> bool; (** End of input? *)
  cur : unit -> char;  (** Current char *)
  next : unit -> char; (** if not {!is_done}, move to next char *)
  pos : unit -> int;   (** Current pos *)
  backtrack : int -> unit;  (** Restore to previous pos *)
  sub : int -> int -> string; (** Extract slice from [pos] with [len] *)
}

exception ParseError of int * string (** position * message *)

(*$R
  let module T = struct
    type tree = L of int | N of tree * tree
  end in
  let open T in

  let mk_leaf x = L x in
  let mk_node x y = N(x,y) in

  let ptree = fix @@ fun self ->
    skip_space *>
    ( (char '(' *> (pure mk_node <*> self <*> self) <* char ')')
      <|>
      (U.int >|= mk_leaf) )
  in

  let rec pptree = function
    | N (a,b) -> Printf.sprintf "N (%s, %s)" (pptree a) (pptree b)
    | L x -> Printf.sprintf "L %d" x
  in
  let errpptree = function
    | `Ok x -> "Ok " ^ pptree x
    | `Error s -> "Error " ^ s
  in

  assert_equal ~printer:errpptree
    (`Ok (N (L 1, N (L 2, L 3))))
    (parse_string "(1 (2 3))" ptree);
  assert_equal ~printer:errpptree
    (`Ok (N (N (L 1, L 2), N (L 3, N (L 4, L 5)))))
    (parse_string "((1 2) (3 (4 5)))" ptree);
*)

(*$R
  let p = U.list ~sep:"," U.word in
  let printer = function
    | `Ok l -> "Ok " ^ CCPrint.to_string (CCList.pp CCString.pp) l
    | `Error s -> "Error " ^ s
  in
  assert_equal ~printer
    (`Ok ["abc"; "de"; "hello"; "world"])
    (parse_string "[abc , de, hello ,world  ]" p);
 *)

let input_of_string s =
  let i = ref 0 in
  { is_done=(fun () -> !i = String.length s);
    cur=(fun () -> s.[!i]);
    next=(fun () ->
        if !i = String.length s
        then raise (ParseError (!i, "unexpected EOI"))
        else (
          let c = s.[!i] in
          incr i;
          c
        )
    );
    pos=(fun () -> !i);
    backtrack=(fun j -> assert (0 <= j && j <= !i); i := j);
    sub=(fun j len -> assert (j + len <= !i); String.sub s j len);
  }

let input_of_chan ?(size=1024) ic =
  assert (size > 0);
  let b = ref (Bytes.make size ' ') in
  let n = ref 0 in  (* length of buffer *)
  let i = ref 0 in  (* current index in buffer *)
  let exhausted = ref false in (* input fully read? *)
  let eoi() = raise (ParseError (!i, "unexpected EOI")) in
  (* read a chunk of input *)
  let read_more () =
    assert (not !exhausted);
    (* resize *)
    if Bytes.length !b - !n < size then (
      let b' = Bytes.make (Bytes.length !b + 2 * size) ' ' in
      Bytes.blit !b 0 b' 0 !n;
      b := b';
    );
    let len = input ic !b !n size in
    exhausted := len = 0;
    n := !n + len
  in
  (* read next char *)
  let next() =
    if !exhausted && !i = !n then eoi();
    let c = Bytes.get !b !i in
    incr i;
    if !i = !n then (
      read_more();
      if !exhausted then eoi();
      assert (!i < !n);
    );
    c
  and is_done () = !exhausted && !i = !n in
  (* fetch first chars *)
  read_more();
  { is_done=(fun () -> !exhausted && !i = !n);
    cur=(fun () -> assert (not (is_done())); Bytes.get !b !i);
    next;
    pos=(fun() -> !i);
    backtrack=(fun j -> assert (0 <= j && j <= !i); i:=j);
    sub=(fun j len -> assert (j + len <= !i); Bytes.sub_string !b j len);
  }

type 'a t = input -> 'a

let return x _ = x
let pure = return
let (>|=) p f st = f (p st)
let (>>=) p f st =
  let x = p st in
  f x st
let (<*>) x y st =
  let f = x st in
  let g = y st in
  f g
let (<* ) x y st =
  let res = x st in
  let _ = y st in
  res
let ( *>) x y st =
  let _ = x st in
  let res = y st in
  res

let junk_ st = ignore (st.next ())
let fail_ st fmt =
  Printf.ksprintf
    (fun msg -> raise (ParseError (st.pos (), msg))) fmt

let eoi st = if st.is_done() then () else fail_ st "expected EOI"
let fail msg st = fail_ st "%s" msg
let nop _ = ()

let char c st =
  if st.next () = c then c else fail_ st "expected '%c'" c

let char_if p st =
  let c = st.next () in
  if p c then c else fail_ st "unexpected char '%c'" c

let chars_if p st =
  let i = st.pos () in
  let len = ref 0 in
  while not (st.is_done ()) && p (st.cur ()) do junk_ st; incr len done;
  st.sub i !len

let chars1_if p st =
  let s = chars_if p st in
  if s = "" then fail_ st "unexpected sequence of chars";
  s

let rec skip_chars p st =
  if not (st.is_done ()) && p (st.cur ()) then (
    junk_ st;
    skip_chars p st
  )

let is_alpha = function
  | 'a' .. 'z' | 'A' .. 'Z' -> true
  | _ -> false
let is_num = function '0' .. '9' -> true | _ -> false
let is_alpha_num = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | _ -> false
let is_space = function ' ' | '\t' -> true | _ -> false
let is_white = function ' ' | '\t' | '\n' -> true | _ -> false
let (~~~) p c = not (p c)
let (|||) p1 p2 c = p1 c || p2 c
let (&&&) p1 p2 c = p1 c && p2 c

let endline = char '\n'
let space = char_if is_space
let white = char_if is_white

let skip_space = skip_chars is_space
let skip_white = skip_chars is_white

let (<|>) x y st =
  let i = st.pos () in
  try
    x st
  with ParseError _ ->
    st.backtrack i; (* restore pos *)
    y st

let string s st =
  let rec check i =
    i = String.length s ||
    (s.[i] = st.next () && check (i+1))
  in
  if check 0 then s else fail_ st "expected \"%s\"" s

let rec many_rec p st acc =
  if st.is_done () then List.rev acc
  else
    let i = st.pos () in
    try
      let x = p st in
      many_rec p st (x :: acc)
    with ParseError _ ->
      st.backtrack i;
      List.rev acc

let many p st = many_rec p st []

let many1 p st =
  let x = p st in
  many_rec p st [x]

let rec skip p st =
  let i = st.pos () in
  let matched =
    try
      let _ = p st in
      true
    with ParseError _ ->
      false
  in
  if matched then skip p st else st.backtrack i

let rec sep1 ~by p =
  p >>= fun x ->
  let cont = by *> sep ~by p >|= fun tl -> x :: tl in
  cont <|> return [x]
and sep ~by p =
  sep1 ~by p <|> return []

let fix f =
  let rec p st = f p st in
  p

let parse_exn ~input p = p input

let parse ~input p =
  try `Ok (parse_exn ~input p)
  with ParseError (i, msg) ->
    `Error (Printf.sprintf "at position %d: error, %s" i msg)

let parse_string s p = parse ~input:(input_of_string s) p
let parse_string_exn s p = parse_exn ~input:(input_of_string s) p

let parse_file_exn ?size ~file p =
  let ic = open_in file in
  let input = input_of_chan ?size ic in
  try
    let res = parse_exn ~input p in
    close_in ic;
    res
  with e ->
    close_in ic;
    raise e

let parse_file ?size ~file p =
  try
    `Ok (parse_file_exn ?size ~file p)
  with
  | ParseError (i, msg) ->
    `Error (Printf.sprintf "at position %d: error, %s" i msg)
  | Sys_error s ->
    `Error (Printf.sprintf "error while reading %s: %s" file s)

module U = struct
  let sep_ = sep

  let list ?(start="[") ?(stop="]") ?(sep=";") p =
    string start *> skip_white *>
    sep_ ~by:(skip_white *> string sep *> skip_white) p <*
    skip_white <* string stop

  let int =
    chars1_if (is_num ||| (=) '-')
    >>= fun s ->
    try return (int_of_string s)
    with Failure _ -> fail "expected an int"

  let map f x = x >|= f
  let map2 f x y = pure f <*> x <*> y
  let map3 f x y z = pure f <*> x <*> y <*> z

  let prepend_str c s = String.make 1 c ^ s

  let word =
    map2 prepend_str (char_if is_alpha) (chars_if is_alpha_num)
end
