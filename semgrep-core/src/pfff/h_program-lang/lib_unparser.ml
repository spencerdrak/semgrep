(* Yoann Padioleau
 *
 * Copyright (C) 2013 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
*)
open Common

module PI = Parse_info
open Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * There are multiple ways to unparse/pretty-print code:
 *  - one can iterate over an AST (or better CST), and print its leaves, but
 *    comments and spaces are usually not in the CST (and for a good reason)
 *    so you need  some extra code that also visits the tokens and try
 *    to "sync" the visit of the CST with the tokens
 *  - one can use a real pretty printer with a boxing or backtracking model
 *    working on an AST extended with comments (see julien's ast_pretty_print/)
 *  - one can iterate over the tokens, where comments and spaces are normal
 *    citizens, but this can be too low level
 *
 * Right now the preferred method for spatch is the last one. The pretty
 * printer currently is too different from our coding conventions
 * (also because we don't have precise coding conventions).
 * This token-based unparser handles transformation annotations (Add/Remove).
 * This was also the approach used in Coccinelle.
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(* Intermediate representations easier to work on; more convenient to
 * program heuristics which try to maintain some good indentation
 * and style.
*)
type elt =
  | OrigElt of string
  | Removed of string
  | Added of string
  | Esthet2 of (Parse_info.esthet * string)
  (* with tarzan *)

(*****************************************************************************)
(* Globals *)
(*****************************************************************************)
let debug = ref false

(*****************************************************************************)
(* Vof *)
(*****************************************************************************)

(* autogenerated by ocamltarzan *)
let rec vof_elt =
  function
  | OrigElt v1 ->
      let v1 = OCaml.vof_string v1 in OCaml.VSum ("OrigElt", [ v1 ])
  | Removed v1 ->
      let v1 = OCaml.vof_string v1 in OCaml.VSum ("Removed", [ v1 ])
  | Added v1 ->
      let v1 = OCaml.vof_string v1 in OCaml.VSum ("Added", [ v1 ])
  | Esthet2 (v1, v2) ->
      let v1 = vof_esthet v1 in
      let v2 = OCaml.vof_string v2 in
      OCaml.VSum ("Esthet", [ v1; v2 ])
and vof_esthet =
  function
  | Comment ->
      OCaml.VSum ("Comment", [])
  | Newline ->
      OCaml.VSum ("Newline", [])
  | Space ->
      OCaml.VSum ("Space", [])

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let s_of_add = function
  | AddStr s -> s
  | AddNewlineAndIdent -> raise Todo

(*****************************************************************************)
(* AddArgsBefore helpers *)
(*****************************************************************************)

(* rh = reversed head, tl = tail *)
let rec add_if_need_comma add_str rh tl =
  match tl with
  (* Because this token is right parenthese, there must be
     something before*)
  | [] -> failwith "Error with need_comma"
  | (OrigElt str)::_t when ((str = ",") || (str = "(")) ->
      List.rev_append rh tl
  | ((OrigElt _str) as h)::t ->
      List.rev_append rh ((Added add_str)::h::t)
  | ((Removed _str) as h)::t -> add_if_need_comma add_str (h::rh) t
  (* Added is very arbitrary, I'd rather not handle them.
   * This can be avoided by using AddArgsBefore only
  *)
  | (Added _str)::_t ->
      failwith "need comma: cannot handle this case!"
  | ((Esthet2 _) as h)::t -> add_if_need_comma add_str (h::rh) t

let rec search_prev_elt ?(ws=0) acc =
  match acc with
  (* Because this token is right parenthese, there must be
     something before *)
  | [] -> failwith "Error with search_prev_real_elt"
  | (OrigElt str)::_t -> (OrigElt str, ws)
  | (Removed _str)::t -> search_prev_elt ~ws t
  | (Added _str)::_t ->
      failwith "search_prev_real_elt: cannot handle this case"
  | (Esthet2(Comment, _str))::t -> search_prev_elt ~ws t
  | (Esthet2(Newline, str))::_t -> (Esthet2 (Newline,str), ws)
  | (Esthet2(Space,str))::t ->
      search_prev_elt ~ws:(ws + String.length str) t


(* This function decides how to add arguments.
 * factors considered:
 * prepend/append comma around arguments?
 * new line for each argument?
 * heuristic:
 * if previous (real) token is '(' or ',', do not prepend comma
 * if this token (right parenthese) follows a newline and some space, add newline for
 * each argument, and append a comma
*)
let elts_of_add_args_before acc xs =
  let (elt, ws) = search_prev_elt acc in
  (* search_prev_elt will fail if meet Added, which may be inserted
     during add_if_need_comma.
  *)
  match elt with
  | Esthet2 (Newline, _) ->
      (* new line for each argument *)
      let acc = add_if_need_comma "," [] acc in
      let sep = xs |> List.map (fun s ->
        "  " ^ s ^ ",\n" ^ String.make ws ' ') in
      let add_str = join "" sep in
      (Added add_str)::acc
  | _ ->
      let acc = add_if_need_comma ", " [] acc in
      let add_str = join ", " xs in
      (Added add_str)::acc

(*****************************************************************************)
(* Elts of any *)
(*****************************************************************************)
let elt_and_info_of_tok tok =
  let (kind, info) = tok in
  let str = PI.str_of_info info in
  let elt =
    match kind with
    | PI.Esthet x -> Esthet2 (x, str)
    | _ -> OrigElt str
  in
  elt, info

let elts_of_any toks =
  let rec aux acc toks =
    match toks with
    | [] -> List.rev acc
    | tok::t ->
        let elt, info = elt_and_info_of_tok tok in
        (match info.token with
         | Ab | FakeTokStr _ | ExpandedTok _ ->
             raise Impossible
         | OriginTok _ ->
             (match info.transfo with
              (* acc is reversed! *)
              | NoTransfo ->
                  aux (elt::acc) t
              | Remove ->
                  aux (Removed (PI.str_of_info info)::acc) t
              | Replace toadd ->
                  (* could also be Removed::Added::_, now that we have
                   * drop_useless_space(), this should not matter anymore
                  *)
                  aux (Added (s_of_add toadd)::Removed (PI.str_of_info info)::acc)
                    t
              | AddAfter toadd ->
                  aux (Added (s_of_add toadd)::elt::acc) t
              | AddBefore toadd ->
                  aux (elt::Added (s_of_add toadd)::acc) t

              | AddArgsBefore xs ->
                  let elt_list = elts_of_add_args_before acc xs in
                  let acc = elt::elt_list in
                  aux acc t
             )
        )
  in
  aux [] toks

(*****************************************************************************)
(* Heuristics *)
(*****************************************************************************)

(* but needs to keep the Removed, otherwise drop_whole_line_if_only_removed()
 * can not know which new empty lines it has to remove
*)
let drop_esthet_between_removed xs =
  let rec outside_remove = function
    | [] -> []
    | Removed s::xs -> Removed s:: in_remove [] xs
    | x::xs -> x::outside_remove xs
  and in_remove acc = function
    | [] -> List.rev acc
    | Removed s::xs -> Removed s::in_remove [] xs
    | Esthet2 x::xs -> in_remove (Esthet2 x::acc) xs
    | Added s::xs -> List.rev (Added s::acc) @ outside_remove xs
    | OrigElt s::xs -> List.rev (OrigElt s::acc) @ outside_remove xs
  in
  outside_remove xs

(* note that it will also remove comments in the line if everthing else
 * was removed, which is what we want most of the time
*)
let drop_whole_line_if_only_removed xs =
  let (before_first_newline, xxs) = xs |> Common2.group_by_pre (function
    | Esthet2 (Newline, _) -> true | _ -> false)
  in
  let xxs = xxs |> Common.exclude (fun (_newline, elts_after_newline) ->
    let has_a_remove =
      elts_after_newline |> List.exists (function
        | Removed _ -> true | _ -> false) in
    let only_remove_or_esthet =
      elts_after_newline |> List.for_all (function
        | Esthet2 _ | Removed _ -> true
        | Added _ | OrigElt _ -> false
      )
    in
    has_a_remove && only_remove_or_esthet
  )
  in
  before_first_newline @
  (xxs |> List.map (fun (elt, elts) -> elt::elts) |> List.flatten)

(* people often write s/foo(X,Y)/.../ but some calls to foo may have
 * a trailing comma that we also want to remove automatically
*)
let drop_trailing_comma_between_removed xs =
  let rec aux xs =
    match xs with
    | Removed s1::OrigElt ","::Removed ")"::rest ->
        Removed s1::Removed ","::Removed ")"::aux rest
    | x::xs -> x::aux xs
    | [] -> []
  in
  aux xs


let drop_removed xs =
  xs |> Common.exclude (function
    | Removed _ -> true
    | _ -> false
  )

(* When removing code, it's quite common as a result to have double
 * spacing. For instance when in 'class X implements I {' we remove
 * the interface 'I', as a result we naively get 'class X  {'.
 * The function below then detect those cases and remove the double spacing.
 *
 * We can have double space only as a result of a transformation on that line.
 * Otherwise the spacing will have been agglomerated by the parser. So we
 * don't risk to remove too much spaces here.
*)
let rec drop_useless_space xs  =
  match xs with
  | [] -> []
  | Esthet2 (Space,s)::Esthet2 (Space,_s2)::rest ->
      drop_useless_space ((Esthet2 (Space, s))::rest)
  (* see tests/php/spatch/distr_plus.spatch, just like we can have
   * double spaces, we can also have space before comma that are
   * useless
  *)
  | Esthet2 (Space, _s)::OrigElt ","::rest ->
      drop_useless_space (OrigElt ","::rest)
  | x::xs -> x::drop_useless_space xs

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

(*
 * The idea of the algorithm below is to iterate over all the tokens
 * and depending on the token 'transfo' annotation to print or not
 * the token as well as the comments/spaces associated with the token.
 * Note that if two tokens were annotated with a Remove, we
 * also want to remove the spaces between so we need a few heuristics
 * to maintain some good style.
 *)
let string_of_toks_using_transfo toks =

  Common2.with_open_stringbuf (fun (_pr_with_nl, buf) ->
    let pp s = Buffer.add_string buf s in

    let xs = elts_of_any toks in

    if !debug
    then xs |> List.iter (fun x -> pr2 (OCaml.string_of_v (vof_elt x)));

    let xs = drop_esthet_between_removed xs in
    let xs = drop_trailing_comma_between_removed xs in
    let xs = drop_whole_line_if_only_removed xs in
    (* must be after drop_whole_line_if_only_removed *)
    let xs = drop_removed xs in
    let xs = drop_useless_space xs in

    xs |> List.iter (function
      | OrigElt s | Added s | Esthet2 ((Comment | Space), s) -> pp s
      | Removed _ -> raise Impossible (* see drop_removed *)
      | Esthet2 (Newline, _) -> pp "\n"
    )
  )