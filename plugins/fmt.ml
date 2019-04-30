(*
 * Generic Transformers: `format` plugin.
 * Copyright (C) 2016-2017
 *   Dmitrii Kosarev aka Kakadu
 * St.Petersburg State University, JetBrains Research
 *)

(** {i Format} module: pretty-prints a value to {!Format.formatter} using {!Format} module.

    For type declaration [type ('a,'b,...) typ = ...] it will create a transformation
    function with type

    [(Format.formatter -> 'a -> unit) -> (Format.formatter -> 'b -> unit) -> ... ->
     Format.formatter -> ('a,'b,...) typ -> unit ]

    Inherited attributes' type (both default and for type parameters) is [Format.formatter].
    Synthesized attributes' type (both default and for type parameters) is [unit].
*)

open Base
open Ppxlib
open HelpersBase
open Printf

let trait_name = "fmt"

module Make(AstHelpers : GTHELPERS_sig.S) = struct

let trait_name = trait_name

module P = Plugin.Make(AstHelpers)
open AstHelpers

let app_format_fprintf ~loc efmtr efmts =
  Exp.app_list ~loc
    Exp.(of_longident ~loc (Ldot(Lident "Format", "fprintf")) )
    [ efmtr; efmts ]

class g args tdecls = object(self)
  inherit [loc, Exp.t, Typ.t, type_arg, Ctf.t, Cf.t, Str.t, Sig.t] Plugin_intf.typ_g
  inherit P.generator args tdecls
  inherit P.with_inherit_arg args tdecls

  method trait_name = trait_name
  method main_inh ~loc _tdecl =
    Typ.of_longident ~loc (Ldot (Lident"Format", "formatter"))
  method main_syn ~loc ?in_class _tdecl = Typ.ident ~loc "unit"

  method syn_of_param ~loc _     = Typ.ident ~loc "unit"
  method inh_of_param tdecl _name = self#main_inh ~loc:noloc tdecl

  method plugin_class_params tdecl =
    (* TODO: reuse prepare_inherit_typ_params_for_alias here *)
    let ps =
      List.map tdecl.ptype_params ~f:(fun (t,_) -> typ_arg_of_core_type t)
    in
    ps @
    [ named_type_arg ~loc:(loc_from_caml tdecl.ptype_loc) @@
      Naming.make_extra_param tdecl.ptype_name.txt
    ]

  method prepare_inherit_typ_params_for_alias ~loc tdecl rhs_args =
    List.map rhs_args ~f:Typ.from_caml

  (* method trf_scheme ~loc =
   *   Typ.(arrow ~loc (of_longident ~loc (Ldot (Lident "Format", "formatter"))) @@
   *        arrow ~loc (var ~loc "a") (unit ~loc) )
   * method trf_scheme_params = ["a"]
   * inherit P.index_result *)

  (* Adapted to generate only single method per constructor definition *)
  method on_tuple_constr ~loc ~is_self_rec ~mutal_decls ~inhe tdecl constr_info ts =
    let constr_name = match constr_info with
      | `Poly s -> sprintf "`%s" s
      | `Normal s -> s
    in

    let fmt = List.map ts ~f:(fun _ -> "%a") |> String.concat ~sep:",@,@ " in
    let fmt = sprintf "%s@ @[(@,%s@,)@]" constr_name fmt in

    Exp.fun_list ~loc
      (List.map ts ~f:(fun (s,_) -> Pat.sprintf ~loc "%s" s))
      (if List.length ts = 0
       then app_format_fprintf ~loc inhe @@ Exp.string_const ~loc constr_name
       else
         List.fold_left ts
           ~f:(fun acc (name, typ) ->
                Exp.app_list ~loc acc
                  [ self#do_typ_gen ~loc ~is_self_rec ~mutal_decls tdecl typ
                  ; Exp.ident ~loc name
                  ]
             )
            ~init:(app_format_fprintf ~loc inhe @@
                   Exp.string_const ~loc fmt
                  )
      )

  method on_record_declaration ~loc ~is_self_rec ~mutal_decls tdecl labs =
    let pat = Pat.record ~loc @@
      List.map labs ~f:(fun l ->
          (Lident l.pld_name.txt, Pat.var ~loc l.pld_name.txt)
        )
    in
    let methname = sprintf "do_%s" tdecl.ptype_name.txt in
    let fmt = List.fold_left labs ~init:""
        ~f:(fun acc x ->
            sprintf "%s@,@ @,@[%s@,=@,%%a;@]" acc x.pld_name.txt
          )
    in
    let fmt_name = gen_symbol ~prefix:"fmt" () in
    [ Cf.method_concrete ~loc methname @@
      Exp.fun_ ~loc (Pat.sprintf "%s" ~loc fmt_name) @@
      Exp.fun_ ~loc pat @@
      List.fold_left labs
            ~f:(fun acc {pld_name; pld_type} ->
                Exp.app_list ~loc acc
                  [ self#do_typ_gen ~loc ~is_self_rec ~mutal_decls tdecl pld_type
                  ; Exp.ident ~loc pld_name.txt
                  ]
              )
            ~init:(app_format_fprintf ~loc (Exp.sprintf "%s" ~loc fmt_name) @@
                   Exp.string_const ~loc @@ sprintf "{@[<hov>%s@]@ }@," fmt
                  )
    ]

  method! on_record_constr ~loc ~is_self_rec ~mutal_decls ~inhe tdecl info bindings labs =
    let cname = match info with
      | `Normal s -> s
      | `Poly s -> s
    in
    let fmt = List.fold_left labs ~init:""
        ~f:(fun acc l ->
            sprintf "%s@,@ @,@[%s@,=@,%%a;@]" acc l.pld_name.txt
          )
    in
    Exp.fun_list ~loc (List.map bindings ~f:(fun (s,_,_) -> Pat.var ~loc s)) @@
    List.fold_left bindings
      ~f:(fun acc (name, _, typ) ->
        Exp.app_list ~loc acc
          [ self#do_typ_gen ~loc ~is_self_rec ~mutal_decls tdecl typ
          ; Exp.ident ~loc name
          ]
      )
      ~init:(app_format_fprintf ~loc inhe @@
        Exp.string_const ~loc @@ sprintf "%s {@[<hov>%s@]@ }@," cname fmt
      )


end

let create =
  (new g :>
     (Plugin_intf.plugin_args -> Ppxlib.type_declaration list ->
      (loc, Exp.t, Typ.t, type_arg, Ctf.t, Cf.t, Str.t, Sig.t) Plugin_intf.typ_g))

end

let register () =
  Expander.register_plugin trait_name (module Make: Plugin_intf.PluginRes)

let () = register ()
