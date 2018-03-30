open Ppx_core
open Printf
open Ast_helper
open GtHelpers
open Ppx_core.Ast_builder.Default

let make_dest_param_names ?(loc=Location.none) ps =
  map_type_param_names ps ~f:(sprintf "%s_2")

let hack_params ?(loc=Location.none) ps =
  let param_names = map_type_param_names ps ~f:id in
  let rez_names = make_dest_param_names ~loc ps in
  let name_migrations = List.zip_exn param_names rez_names in
  let assoc s =
    try List.Assoc.find_exn ~equal:String.equal name_migrations s
    with Not_found ->
      raise_errorf "can't find new typ for param `%s" s
  in
  let blownup_params =
    List.concat_map param_names
      ~f:(fun s1 ->
           [Typ.var ~loc s1; Typ.var ~loc @@ assoc s1 ]
         )
  in
  (param_names, rez_names, assoc, blownup_params)

open Plugin

(* TODO: we want easily get foldr from foldl *)

let g initial_args = object(self: 'self)
  inherit ['self] Plugin.generator initial_args

  method plugin_name = "foldl"

  method default_inh = let loc = Location.none in [%type: 'syn]
  method default_syn tdecl =
    let loc = tdecl.ptype_loc in
    [%type: 'syn]

  method syn_of_param ~loc s = [%type: 'syn]

  method plugin_class_params tdecl =
    (* There we should have all parameters on the LHS of definition and 'syn one *)
    List.map ~f:fst tdecl.ptype_params @ [self#default_syn tdecl]

  method prepare_inherit_args_for_alias ~loc tdecl rhs_args =
    rhs_args @ [ self#default_syn tdecl ]
               (* TODO: add 'extra ? *)

  method on_tuple_constr tdecl is_self_rec cd args =
    let loc = tdecl.ptype_loc in
    let names = make_new_names (List.length args) in

    Cf.method_concrete ~loc ("c_"^cd.pcd_name.txt)
      [%expr fun inh -> [%e
        Exp.fun_list ~args:(List.map names ~f:(Pat.sprintf "%s")) @@
        List.fold_left ~f:(fun acc (name,typ) ->
          [%expr [%e self#do_typ_gen ~loc is_self_rec typ] [%e acc]
              [%e Exp.sprintf ~loc "%s" name]]
        )
        ~init:[%expr inh]
        (List.zip_exn names args)
      ]]


  method generate_for_polyvar_tag ~loc constr_name bindings is_self_rec einh k =
    (* TODO: rewrite *)
    let ctuple =
      match bindings with
      | [] -> None
      | _  ->
        Some (Exp.tuple ~loc @@
              List.map bindings
                ~f:(fun (name, typ) ->
                    [%expr
                      [%e self#do_typ_gen ~loc is_self_rec typ ]
                      [%e einh]
                      [%e Exp.ident ~loc name ]
                    ]
                  )
             )
    in
    k @@ Exp.variant ~loc constr_name ctuple


  method got_polyvar ~loc tdecl do_typ is_self_rec rows k =
        (* TODO: rewrite *)
    let _param_names,_rez_names,_find_param,blownup_params =
      hack_params tdecl.ptype_params
    in
    k @@
    List.map rows ~f:(function
        | Rinherit typ ->
          with_constr_typ typ
            ~fail:(fun () -> failwith "type is not a constructor")
            ~ok:(fun cid params ->
                let args = List.map params ~f:(self#do_typ_gen ~loc is_self_rec) in
                let inh_params = blownup_params @ [[%type: 'extra]] in
                Cf.inherit_ ~loc @@ Cl.apply
                  (Cl.constr
                     ({cid with txt = map_longident cid.txt ~f:((^)"gmap_")})
                     inh_params
                  )
                  (nolabelize ([%expr _fself]::args))
              )
        | Rtag (constr_name,_,_,args) ->
            assert false
          (* let names = make_new_names (List.length ts) in
           *
           * Cf.method_concrete ~loc ("c_" ^ constr_name)
           *   [%expr fun () -> [%e
           *     Exp.fun_list ~args:(List.map names ~f:(Pat.sprintf "%s")) @@
           *     let ctuple =
           *       if List.length ts = 0
           *       then None
           *       else Some (Exp.tuple ~loc @@
           *                  List.concat_map (List.zip_exn names ts)
           *                    ~f:(fun (name, typ) -> self#do_typ_gen ~loc is_self_rec  typ)
           *                 )
           *     in
           *     Exp.variant ~loc constr_name ctuple
           *   ]] *)

      )

end
