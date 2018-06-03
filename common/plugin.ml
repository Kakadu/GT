open Base
open Ppxlib
open Printf
open Asttypes
open HelpersBase

let self_arg_name = "fself"
let extra_param_name = "extra"

module Make(AstHelpers : GTHELPERS_sig.S) = struct

open AstHelpers
module Intf = Plugin_intf.Make(AstHelpers)

let prepare_patt_match_poly ~loc what rows labels ~onrow ~onlabel ~oninherit =
  let k cs = Exp.match_ ~loc what cs in
  let rs =
    List.map rows ~f:(function
        | Rtag (lab, _, _, args) ->
          let args = match args with
            | [t] -> unfold_tuple t
            | [] -> []
            | _ -> failwith "we don't support conjunction types"
          in
          let names = List.map args ~f:(fun _ -> gen_symbol ~prefix:"_" ()) in
          let lhs = Pat.variant ~loc  lab @@ List.map ~f:(Pat.var ~loc) names in
          case ~lhs ~rhs:(onrow lab @@ List.zip_exn names args)
        | Rinherit typ ->
          match typ.ptyp_desc with
          | Ptyp_constr({txt;_},ts) ->
            let newname = "subj" in
            let lhs = Pat.alias ~loc (Pat.type_ ~loc txt) newname
            in
            case ~lhs ~rhs:(oninherit ts txt newname)
          | _ -> failwith "this inherit field isn't supported"

      )
  in
  let ls = match labels with
    | None -> []
    | Some ls -> List.map ls ~f:(fun lab ->
        let newname = "subj" in
        let lhs = Pat.alias ~loc (Pat.type_ ~loc (Lident lab) ) newname
        in
        case ~lhs ~rhs:(onlabel lab newname)
      )
  in
  k @@ rs@ls

class virtual generator initial_args = object(self: 'self)
  inherit Intf.g

  (* parse arguments like { _1=<expr>; ...; _N=<expr>; ...} *)
  val reinterpreted_args =
    let check_name s =
      try Caml.Scanf.sscanf s "_%d" (fun n -> Some n)
      with Caml.Scanf.Scan_failure _ ->
        (* printf "can't parse it\n%!"; *) None
    in
    let ans =
      List.fold_left initial_args ~init:[]
        ~f:(fun acc (lident,expr) ->
            match lident with
            | Lident s -> Option.value_map (check_name s) ~default:acc
                            ~f:(fun n -> (n,expr) :: acc)
            | _ -> acc
          )
    in
    (* printf "Total args found for plugin : %d\n%!"  (List.length ans); *)
    ans

  method show_args =
    List.iter reinterpreted_args ~f:(fun (k,e) ->
        Format.printf "%d -> %a\n%!" k Pprintast.expression e
      )

  (* method extra_param_stub ~loc = construct_extra_param ~loc *)

  method extra_class_sig_members _ = []
  method extra_class_str_members _ = []
  method cur_name tdecl = tdecl.ptype_name.txt

  (* preparing class of transformation for [tdecl] *)
  method make_class ~loc tdecl ~is_rec mutal_names =
    let cur_name = self#cur_name tdecl in
    let k fields =
      let inh_params =
        let inh_params =
          let tnames  = map_type_param_names tdecl.ptype_params ~f:id in
          prepare_param_triples ~loc
            ~inh:(fun ~loc -> self#inh_of_param tdecl)
            ~syn:self#syn_of_param
            ~default_syn:(self#default_syn ~loc tdecl)
            ~default_inh:(self#default_inh ~loc tdecl)
            tnames
        in
        inh_params @ [ Typ.var ~loc extra_param_name ]
      in
      self#wrap_class_definition ~loc mutal_names tdecl ~inh_params
        ((self#extra_class_str_members tdecl) @ fields)
    in

    let is_self_rec t =
      is_rec &&
      match t.ptyp_desc with
      | Ptyp_var _ -> false
      | Ptyp_constr ({txt=Lident s}, params)
        when String.equal s cur_name &&
             List.length params = List.length tdecl.ptype_params &&
             List.for_all2_exn params tdecl.ptype_params
               ~f:(fun a (b,_) -> 0=compare_core_type a b)
        -> is_rec
      | _ -> false
    in
    self#got_typedecl ~loc tdecl ~is_self_rec ~mutal_names k

  (* method extra_class_lets tdecl k =
   *   k *)

  method prepare_fa_args ~loc tdecl =
    map_type_param_names tdecl.ptype_params ~f:(Pat.sprintf ~loc "f%s")

  method wrap_class_definition ~loc ~inh_params mutal_names tdecl fields =
    let cur_name = self#cur_name tdecl in
    (* inherit class_t and prepare to put other members *)

    Str.class_single ~loc
      ~params:(self#plugin_class_params tdecl )
      ~name:(self#make_class_name ~is_mutal:(not (List.is_empty mutal_names)) tdecl )
      ~virt:false
      ~wrap:((* self#extra_class_lets tdecl @@ *) fun body ->
        (* constructor arguments are *)
        let names =
          List.map mutal_names
            ~f:(Pat.sprintf ~loc "%s_%s" self#plugin_name) @
          [Pat.var ~loc self_arg_name] @
          (self#prepare_fa_args ~loc tdecl)
        in
        Cl.fun_list ~loc names body
      )
      @@
      [ let parent_name = HelpersBase.class_name_for_typ cur_name in
            (* ~trait:self#plugin_name *)
        (* in *)
        Cf.inherit_ ~loc (Cl.constr ~loc (Lident parent_name) inh_params)
      ] @ fields

  (* shortened class only used for mutally recursive declarations *)
  method make_shortend_class ~loc ~is_rec mutal_names tdecls =
    List.map tdecls ~f:(fun tdecl ->
      let mutal_names = List.filter mutal_names
          ~f:(String.(<>) tdecl.ptype_name.txt) in
      let class_name =
          trait_class_name_for_typ ~trait:self#plugin_name tdecl.ptype_name.txt
      in
      let stub_name = class_name ^ "_stub" in
      (* maybe it should be called proto *)
      let mut_funcs = List.map ~f:(sprintf "%s_%s" self#plugin_name) mutal_names in

      let new_params = self#plugin_class_params tdecl in
      Str.class_single ~loc ~name:class_name
        ~wrap:(fun cl ->
            Cl.fun_ ~loc (Pat.sprintf ~loc "%s" self_arg_name) @@
            Cl.fun_list ~loc (self#prepare_fa_args ~loc tdecl) cl
          )
        ~params:new_params
        [ Cf.inherit_ ~loc @@ Cl.apply ~loc
            (Cl.constr ~loc (Lident stub_name) @@
             List.map ~f:(Typ.of_type_arg ~loc) new_params)
            (List.map ~f:(Exp.sprintf ~loc "%s") mut_funcs @
             [Exp.sprintf ~loc "%s" self_arg_name] @
             (self#apply_fas_in_new_object ~loc tdecl))
        ]
    )

  method virtual make_typ_of_class_argument: loc:loc -> type_declaration ->
    string -> right:Cty.t -> Cty.t

  (* next method should be synchronized with prepare_fa_args *)
  method prepare_fa_arg_types ~loc tdecl =
    let names = map_type_param_names tdecl.ptype_params ~f:id  in
    List.map names
      ~f:(fun name ->
          self#make_typ_of_class_argument
            ~loc
            tdecl
            name
            (fun x -> x)
        )

  (* signature for a plugin class *)
  method make_class_sig ~loc tdecl ~is_rec (mutal_decls: type_declaration list) =
    let k fields =
      [ Sig.class_ ~loc
          ~params:(self#plugin_class_params tdecl)
          ~name:(self#make_class_name ~is_mutal:false tdecl)
          ~virt:false
          ~wrap:(fun init ->
              let for_self = self#make_typ_of_self_trf ~loc tdecl in
              let funcs_for_args = self#prepare_fa_arg_types ~loc tdecl in

              List.fold_right mutal_decls
                ~init:(Cty.arrow ~loc for_self funcs_for_args)
                ~f:(fun mut_decl acc ->
                  self#make_typ_of_mutal_trf ~loc mut_decl
                    (fun t -> Cty.arrow ~loc t acc)
                )
            )
          ((self#extra_class_sig_members tdecl) @ fields)
      ]
    in
    visit_typedecl ~loc tdecl
      ~onabstract:(fun () -> k [])
      ~onmanifest:(fun typ ->
        let rec helper typ =
          match typ.ptyp_desc with
          | Ptyp_var name -> (* antiphantom types *)
            let new_lident = Ldot (Lident "GT", "free") in
            let open Ppxlib.Ast_builder.Default in
            let loc = typ.ptyp_loc in
            helper @@ ptyp_constr ~loc (Located.mk ~loc new_lident) [ptyp_var ~loc name]

          | Ptyp_alias (t, aname) ->
            let loc = t.ptyp_loc in
            map_core_type t ~onvar:(fun as_ ->
              let open Ppxlib.Ast_builder.Default in
              if String.equal as_ aname
              then ptyp_constr ~loc (Located.lident ~loc tdecl.ptype_name.txt) @@
                List.map tdecl.ptype_params ~f:(fun (t,_) -> t)
              else ptyp_var ~loc as_
              ) |> helper
          | Ptyp_constr (cid, params) ->
            (* there for type 'a list = ('a,'a list) alist
             * we inherit plugin class for base type, for example (gmap):
             *  inherit ('a,'a2,'a list,'a2 list) gmap_alist
             **)
            k [Ctf.inherit_ ~loc @@ Cty.constr ~loc
                 (map_longident cid.txt
                    ~f:(trait_class_name_for_typ ~trait:self#plugin_name))
                 (self#prepare_inherit_typ_params_for_alias ~loc tdecl params)
              ]
          | Ptyp_tuple ts ->
            (* let's say we have predefined aliases for now *)
            helper @@ constr_of_tuple ~loc:typ.ptyp_loc ts
          | Ptyp_variant (rows,_,_) ->
              let rr = List.map rows ~f:(function
              | Rinherit typ ->
                  with_constr_typ typ
                    ~ok:(fun cid params ->
                        Ctf.inherit_ ~loc @@
                        Cty.constr ~loc
                          (map_longident  cid.txt
                             ~f:(trait_class_name_for_typ ~trait:self#plugin_name))
                          (self#prepare_inherit_typ_params_for_alias ~loc
                             tdecl params)
                     )
                     ~fail:(fun () -> assert false)
              | Rtag (lab,_,_, typs) -> begin
                  Ctf.method_ ~loc (sprintf "c_%s" lab) ~virt:false @@
                  match typs with
                  | [] -> Typ.(chain_arrow ~loc
                                 [ self#default_inh ~loc tdecl
                                 ; self#default_syn ~loc tdecl]
                              )
                  | [t] ->
                      Typ.(chain_arrow ~loc @@
                             [self#default_inh ~loc tdecl] @
                             (List.map ~f:Typ.from_caml @@ unfold_tuple t) @
                             [self#default_syn ~loc tdecl]
                          )
                  | typs ->
                      Typ.(chain_arrow ~loc @@
                             [self#default_inh ~loc tdecl] @
                             (List.map ~f:Typ.from_caml typs) @
                             [self#default_syn ~loc tdecl]
                          )
                end
              )
              in
              k @@ rr
        | _ -> assert false
        in
        helper typ
    )
    ~onvariant:(fun cds ->
        k @@ List.map cds
          ~f:(fun cd ->
              match cd.pcd_args with
              | Pcstr_record _ -> assert false
              | Pcstr_tuple ts ->
                Ctf.method_ ~loc ~virt:false ("c_"^cd.pcd_name.txt) @@
                List.fold_right ~init:(self#default_syn ~loc tdecl)
                  (self#default_inh ~loc tdecl :: (List.map ~f:Typ.from_caml ts))
                  ~f:(Typ.arrow ~loc)

          )
    )

  method make_inherit_args_for_alias ~loc ~is_self_rec tdecl do_typ cid cparams =
    let args =
      List.mapi cparams ~f:(fun i t ->
          (* printf "checking for arg with index (%d+1)\n%!" i; *)
          try List.Assoc.find_exn reinterpreted_args ~equal:Int.equal (i+1)
            |> Exp.from_caml
          with Caml.Not_found -> do_typ ~loc t
        )
    in
    (* for typ aliases we can cheat because first argument of constructor of type
               on rhs is self transformer function *)
    (* TODO: make consistent with self_arg_name *)
    (self#generate_for_variable ~loc "self") :: args


  (* When we got declaration of type alias via type application *)
  method got_constr ~loc ~is_self_rec tdecl do_typ cid cparams k =
    (* printf "got a constr\n%!"; *)
    (* self#show_args; *)
    let ans args : Cf.t list =
      [ let typ_params = self#prepare_inherit_typ_params_for_alias ~loc tdecl cparams
        in
        Cf.inherit_ ~loc @@ Cl.apply ~loc
          (Cl.constr ~loc
             (map_longident cid.txt
                ~f:(HelpersBase.trait_class_name_for_typ ~trait:self#plugin_name))
             typ_params)
          (args)
      ]
    in

    let class_args =
      (* TODO: maybe we should hardcode fself here and skip it in plugins *)
      self#make_inherit_args_for_alias ~loc ~is_self_rec tdecl do_typ cid cparams
    in
    k @@ ans class_args


  method got_polyvar ~loc ~is_self_rec ~mutal_names tdecl do_typ rows k =
    List.concat_map rows ~f:(function
    | Rinherit typ ->
        with_constr_typ typ
            ~fail:(fun () -> failwith "type is not a constructor")
            ~ok:(fun cid params ->
                (* Hypothesis: it's almost an type alias *)
                self#got_constr ~loc ~is_self_rec tdecl do_typ cid params k
            )

    (* tag by default have 1 argument which is a tuple instead of many arguments *)
    | Rtag (constr_name,_,_, []) ->
        self#on_tuple_constr ~loc ~is_self_rec ~mutal_names tdecl (`Poly constr_name)
          [] k
    | Rtag (constr_name,_,_, [arg]) ->
        self#on_tuple_constr ~loc ~is_self_rec ~mutal_names tdecl (`Poly constr_name)
          (unfold_tuple arg) k
    | Rtag (constr_name,_,_,args) ->
      (* Hypothesis: it's almost the same as constructor with a tuple of types  *)
      failwith "conjunction types are not supported but"
    )

  method got_typedecl ~loc ~is_self_rec ~mutal_names tdecl (k: Cf.t list -> _) =
    k @@
    visit_typedecl ~loc tdecl
    ~onmanifest:(fun typ ->
        let rec helper typ  =
          match typ.ptyp_desc with
          | Ptyp_var name -> (* antiphantom types *)
            let new_lident = Ldot (Lident "GT", "free") in
            let open Ppxlib.Ast_builder.Default in
            let loc = typ.ptyp_loc in
            helper @@ ptyp_constr ~loc (Located.mk ~loc new_lident) [ptyp_var ~loc name]
          | Ptyp_alias (t, aname) ->
            let open Ppxlib.Ast_builder.Default in
            let loc = tdecl.ptype_loc in
            map_core_type t ~onvar:(fun as_ ->
              if String.equal as_ aname
              then ptyp_constr ~loc:t.ptyp_loc
                  (Located.lident ~loc tdecl.ptype_name.txt)
                  (List.map tdecl.ptype_params ~f:fst)
              else ptyp_var ~loc as_
              ) |> helper
          | Ptyp_constr (cid, params) ->
              self#got_constr ~loc ~is_self_rec tdecl
                (self#do_typ_gen ~mutal_names ~is_self_rec)
                cid params (fun x -> x)

          | Ptyp_tuple ts ->
            (* let's say we have predefined aliases for now *)
            helper @@ constr_of_tuple ~loc:typ.ptyp_loc ts
          | Ptyp_variant (rows,_,_) ->
            self#got_polyvar ~loc tdecl (self#do_typ_gen ~mutal_names ~is_self_rec)
              ~is_self_rec ~mutal_names rows (fun x -> x)
        | _ -> assert false
        in
        helper typ
    )
    ~onvariant:(fun cds -> self#on_variant ~loc ~mutal_names ~is_self_rec tdecl cds id)
    ~onrecord:(self#on_record_declaration ~loc ~is_self_rec ~mutal_names tdecl)

  method virtual on_record_declaration: loc:loc ->
    is_self_rec:(core_type -> bool) ->
    mutal_names:(string list) ->
    type_declaration ->
    label_declaration list ->
    Cf.t list

  method make_typ_of_mutal_trf ~loc mutal_tdecl (k: Typ.t -> _)  =
    let subj_t = Typ.use_tdecl mutal_tdecl in
    k Typ.(arrow ~loc subj_t (self#default_syn ~loc mutal_tdecl))

    (* k @@ Typ.from_caml [%type: ([%t subj_t] -> [%t self#default_syn ~loc mutal_tdecl]) ] *)


  (* val name : <typeof fa> -> ... -> <typeof fz> ->
                     <this type we are generating here>
  *)

  (* method make_RHS_typ_of_transformation ~loc ?subj_t ?syn_t tdecl =
   *   let subj_t = Option.value subj_t
   *       ~default:(Typ.use_tdecl tdecl) in
   *   let syn_t  = Option.value syn_t ~default:(self#default_syn ~loc tdecl) in
   *   Typ.arrow ~loc subj_t syn_t *)

  (* method chain_inh_syn ~loc ~inh_t ~syn_t subj_t =
   *   [%type: [%t inh_t] -> [%t subj_t] -> [%t syn_t] ] *)

  method wrap_tr_function_typ (typ: core_type) =
    (* let loc = typ.ptyp_loc in *)
    typ
    (* [%type:  [%t self#default_inh] -> [%t typ] ] *)

  method make_trans_function_typ ~loc tdecl =
    let type_ = self#make_RHS_typ_of_transformation ~loc tdecl in

    List.fold_right
      (map_type_param_names tdecl.ptype_params ~f:id)
      ~init:type_
      ~f:(fun name right ->
          self#make_typ_of_class_argument ~loc tdecl name ~right
         )

  method make_trans_function_name tdecl =
    sprintf "%s_%s" self#plugin_name tdecl.ptype_name.txt

  method make_trans_functions_sig: loc:loc ->
    is_rec:bool -> string list -> type_declaration list -> Sig.t list
    = fun ~loc ~is_rec mutal_names tdecls ->

      List.map tdecls ~f:(fun tdecl ->
          let type_ = self#make_trans_function_typ ~loc tdecl in
          Sig.value ~loc
            ~name:(self#make_trans_function_name tdecl)
            type_
        )

  method make_class_name ?(is_mutal=false) tdecl =
    sprintf "%s%s"
      (HelpersBase.trait_class_name_for_typ ~trait:self#plugin_name
         tdecl.ptype_name.txt)
      (if is_mutal then "_stub" else "")

  method wrap_tr_function_str ~loc tdecl gcata_on_new_expr =
    let body = gcata_on_new_expr (Exp.sprintf ~loc "self") in

    Exp.fun_ ~loc (Pat.sprintf ~loc "subj") @@
    Exp.app_list ~loc
      (Exp.of_longident ~loc (Ldot (Lident "GT", "fix0")) )
      [ Exp.fun_ ~loc (Pat.sprintf ~loc "self") (Exp.app ~loc body @@ Exp.unit ~loc )
      ; Exp.sprintf ~loc "subj"
      ]
    (* [%expr fun subj -> GT.fix0 (fun self ->
     *     [%e body] ()) subj
     * ] *)

  method apply_fas_in_new_object ~loc tdecl =
    (* very similar to self#make_inherit_args_for_alias but the latter
     * applies `fself` by default. Need to refactor and remove this function *)
    map_type_param_names tdecl.ptype_params ~f:(Exp.sprintf ~loc "f%s")

  (* let <plugin-name> fa ... fz = <this body> *)
  method make_trans_function_body ~loc ?(rec_typenames=[]) class_name tdecl =
    self#wrap_tr_function_str ~loc tdecl
      (fun eself ->
         Exp.app ~loc (Exp.sprintf ~loc "gcata_%s" tdecl.ptype_name.txt) @@
         Exp.app_list ~loc (Exp.new_ ~loc @@ Lident class_name) @@
         (
          List.map rec_typenames ~f:(Exp.sprintf ~loc "%s_%s" self#plugin_name)
          @ [eself]
          @ (self#apply_fas_in_new_object ~loc tdecl)
         )
      )

  method make_trans_functions: loc:loc ->
    is_rec:bool -> string list -> type_declaration list -> Str.t
    = fun ~loc ~is_rec mutal_names tdecls ->
      (* we will generate mutally recursive showers here *)
      let on_tdecl tdecl =
        let cur_name = tdecl.ptype_name.txt in
        let others =
          List.filter mutal_names ~f:(String.(<>) cur_name)
        in
        value_binding ~loc
          ~pat:(Pat.sprintf ~loc "%s" @@ self#make_trans_function_name tdecl)
          ~expr:(
            let class_name = self#make_class_name
                ~is_mutal:(not (List.is_empty mutal_names))
                tdecl
            in
            (* let arg_transfrs =
             *   map_type_param_names tdecl.ptype_params ~f:((^)"f")
             * in *)
            Exp.fun_list ~loc
              (self#prepare_fa_args ~loc tdecl)
              (self#make_trans_function_body ~loc ~rec_typenames:others
                 class_name tdecl)
          )
      in
      (* let flag = if List.length mutal_names = 1 then Nonrecursive else Recursive in *)
      Str.values ~loc @@ List.map tdecls ~f:on_tdecl


  method do_single_sig ~loc ~is_rec tdecl =
    List.concat
    [ self#make_class_sig ~loc ~is_rec tdecl []
    ; self#make_trans_functions_sig ~loc ~is_rec [] [tdecl]
    ]

  method do_single ~loc ~is_rec tdecl =
    [ self#make_class ~loc ~is_rec tdecl []
    ; self#make_trans_functions ~loc ~is_rec [] [tdecl]
    ]

  method do_mutals ~loc ~is_rec tdecls : Str.t list =
    (* for mutal recursion we need to generate two classes and one function *)
    let mut_names = List.map tdecls ~f:(fun td -> td.ptype_name.txt) in
    List.map tdecls ~f:(fun tdecl ->
        self#make_class ~loc ~is_rec:true tdecl @@
        List.filter mut_names ~f:(String.(<>) tdecl.ptype_name.txt)
      ) @
    (self#make_trans_functions ~loc ~is_rec:true mut_names tdecls) ::
    (self#make_shortend_class  ~loc ~is_rec:true mut_names tdecls)


  method on_record_constr : type_declaration -> constructor_declaration ->
    label_declaration list -> 'on_record_result
    = fun _ _ _ ->
    failwith "not_implemented"

  method virtual on_tuple_constr : loc:loc ->
    is_self_rec:(core_type -> bool) ->
    mutal_names:string list ->
    type_declaration ->
    [ `Normal of string | `Poly of string ] ->
    core_type list -> (Cf.t list -> 'r) -> 'r

  method on_variant ~loc tdecl ~mutal_names ~is_self_rec cds k =
    k @@
    List.concat_map cds ~f:(fun cd ->
        match cd.pcd_args with
        | Pcstr_tuple ts ->
            self#on_tuple_constr ~loc ~mutal_names ~is_self_rec
              tdecl (`Normal cd.pcd_name.txt) ts (fun x -> x)
        | Pcstr_record ls -> self#on_record_constr tdecl cd ls
      )

  method virtual generate_for_polyvar_tag : loc:loc ->
    is_self_rec:(core_type -> bool) -> mutal_names:(string list) ->
    string -> (string*core_type) list -> Exp.t ->
    (Exp.t -> 'x) -> 'x

  method generate_for_variable ~loc varname =
    Exp.sprintf ~loc "f%s" varname

  method virtual app_transformation_expr: loc:loc ->
    Exp.t -> Exp.t -> Exp.t -> Exp.t

  method virtual abstract_trf: loc:loc -> (Exp.t -> Exp.t -> Exp.t) -> Exp.t

  (* TODO: decide expression of which type should be returned here *)
  (* do_type_gen will return an expression which after being applied
   * to inherited attribute and subject will return synthetized one
   *)
  method do_typ_gen ~loc ~mutal_names ~is_self_rec t : Exp.t =
    let access_plugins ~loc e =
      Exp.acc ~loc e @@
      (Ldot (Lident "GT", "plugins"))
    in
    let rec helper t =
      match t.ptyp_desc with
      | Ptyp_var s -> self#generate_for_variable ~loc s
      | Ptyp_tuple params ->
        self#abstract_trf ~loc (fun einh esubj ->
            self#app_transformation_expr ~loc
              Exp.(app_list ~loc
                 (send ~loc
                    (access_plugins ~loc
                       (of_longident ~loc
                          (Ldot (Lident "GT", Printf.sprintf "tuple%d" (List.length params))))
                    )
                    (* [%expr let open GT in
                     *   [%e  Exp.sprintf "tuple%d" (List.length params)
                     *   ].GT.plugins ] *)
                    self#plugin_name
                 )
                 (List.map ~f:helper params)
              )
              einh esubj
          )
      | Ptyp_constr (_,_) when is_self_rec t ->
        Exp.ident ~loc self_arg_name
      | Ptyp_constr ({txt},params) ->
          (* in this place it will be easier to have all plugin in single value *)
          let trf_expr =
            match txt with
            | Lident s when List.mem mutal_names s ~equal:String.equal ->
              (* we should use local trf function *)
              Exp.of_longident ~loc @@
              map_longident txt ~f:(sprintf "%s_%s" self#plugin_name)
            | _ ->
                (* [%expr let (module Op) =
                 *          [%e Exp.ident_of_long txt] in
                 *   [%e
                 *     Exp.ident_of_long ~loc @@
                 *     Ldot (Lident "Op", self#plugin_name) ]
                 * ] *)
              Exp.(send ~loc
                     (access_plugins ~loc (of_longident ~loc txt))
                     self#plugin_name
                  )
          in
        self#abstract_trf ~loc (fun einh esubj ->
            self#app_transformation_expr ~loc
              (List.fold_left params (* (List.map ~f:helper params) *)
                 ~init:trf_expr
                 ~f:(fun left typ ->
                   self#compose_apply_transformations ~loc ~left (helper typ) typ
                 )
              )
              einh esubj
          )
        | Ptyp_variant (rows, _, maybe_labels) -> begin
          let oninherit einh esubj typs cident varname =
            self#app_transformation_expr
              (Exp.app_list ~loc
                Exp.(of_longident ~loc @@
                     map_longident cident
                       ~f:(Printf.sprintf "%s_%s" self#plugin_name))
                (List.map typs ~f:helper)
              )
              einh esubj
            in
            let onrow lab bindings =
              self#generate_for_polyvar_tag ~loc ~is_self_rec ~mutal_names
                lab bindings
                (Exp.sprintf ~loc "inh")
                (fun x -> x)
            in
            self#abstract_trf ~loc (fun einh esubj ->
              prepare_patt_match_poly ~loc esubj rows maybe_labels
                ~onrow
                ~onlabel:(fun _ _ -> Exp.int_const ~loc 1)
                ~oninherit:(oninherit ~loc einh esubj)
            )
          end
        | _ -> failwith "Finish it!"
    in
    helper t


  method compose_apply_transformations ~loc ~left right typ =
    Exp.app ~loc left right


  method virtual make_typ_of_self_trf: loc:loc -> type_declaration -> Typ.t
  method virtual default_syn  : loc:loc -> Ppxlib.type_declaration -> Typ.t
  method virtual default_inh : loc:loc -> Ppxlib.type_declaration -> Typ.t

  method virtual make_RHS_typ_of_transformation: loc:AstHelpers.loc ->
         ?subj_t:Typ.t -> ?syn_t:Typ.t -> type_declaration -> Typ.t
end

class virtual ['self] no_inherit_arg = object(self: 'self)
  (* inherit [_] generator as super *)

  method virtual default_syn : loc:loc -> Ppxlib.type_declaration -> Typ.t
  method virtual default_inh : loc:loc -> Ppxlib.type_declaration -> Typ.t
  method virtual syn_of_param: loc:loc -> string -> Typ.t


  (* almost the same as `make_typ_of_class_argument` *)
  method make_typ_of_self_trf ~loc tdecl =
    let is_poly = is_polyvariant_tdecl tdecl in
    let openize_poly typ =
      if is_poly then Typ.variant ~loc ~is_open:true [Rinherit typ]
      else Typ.from_caml typ
    in

    let subj_t = openize_poly @@ using_type ~typename:tdecl.ptype_name.txt tdecl in
    let syn_t  = self#default_syn ~loc tdecl in
    Typ.(arrow ~loc subj_t @@ syn_t)

  (* val name: <fa> -> <fb> -> ... -> <fz> -> <_not_ this>
   *   fot a type ('a,'b,....'z) being generated
  **)
  method make_typ_of_class_argument ~loc tdecl name k =
    let subj_t = Typ.var ~loc name in
    let syn_t = self#syn_of_param ~loc name in
    k @@ Typ.arrow ~loc subj_t syn_t

  method make_RHS_typ_of_transformation ~loc ?subj_t ?syn_t tdecl =
    let subj_t = Option.value subj_t
        ~default:(Typ.use_tdecl tdecl) in
    let syn_t  = Option.value syn_t ~default:(self#default_syn ~loc tdecl) in
    Typ.arrow ~loc subj_t syn_t

  method abstract_trf ~loc k =
    Exp.fun_ ~loc (Pat.sprintf ~loc "subj") @@
    k (Exp.assert_false ~loc) (Exp.ident ~loc "subj")
    (* [%expr fun inh subj -> [%e k [%expr inh ] [%expr subj]]] *)

  method app_transformation_expr ~loc trf inh subj =
    (* we ignore inherited argument by default *)
    Exp.app ~loc trf subj

end

class virtual ['self] with_inherit_arg = object(self: 'self)
  inherit [_] no_inherit_arg as super

  method wrap_tr_function_str ~loc _tdelcl make_gcata_of_class =
    (* [%expr fun the_init subj -> GT.fix0 (fun self -> [%e body]) the_init subj] *)
    let body = make_gcata_of_class (Exp.ident ~loc "self") in
    Exp.fun_list ~loc [ Pat.sprintf ~loc "the_init"; Pat.sprintf ~loc "subj"] @@
    Exp.app_list ~loc
      (Exp.of_longident ~loc (Ldot (Lident "GT", "fix0")))
      [ Exp.fun_ ~loc (Pat.sprintf ~loc "self") body
      ; Exp.sprintf ~loc "the_init"
      ; Exp.sprintf ~loc "subj"
      ]

  method! make_typ_of_self_trf ~loc tdecl =
    Typ.arrow ~loc (self#default_inh ~loc tdecl) (super#make_typ_of_self_trf ~loc tdecl)

  (* val name: <fa> -> <fb> -> ... -> <fz> -> <_not_ this>
   *   fot a type ('a,'b,....'z) being generated
   **)
(*
  method! make_typ_of_class_argument ~loc tdecl name k =
    k @@
    super#make_typ_of_class_argument ~loc tdecl name (fun t ->
        Typ.arrow ~loc (Typ.var ~loc (name^"__")) t
      )
    *)

  method! make_RHS_typ_of_transformation ~loc ?subj_t ?syn_t tdecl =
    let subj_t = Option.value subj_t ~default:(Typ.use_tdecl tdecl) in
    let syn_t  = Option.value syn_t  ~default:(self#default_syn ~loc tdecl) in
    Typ.arrow ~loc (self#default_inh ~loc tdecl)
      (super#make_RHS_typ_of_transformation ~loc ~subj_t ~syn_t tdecl)

  method! abstract_trf ~loc k =
    Exp.fun_list ~loc [ Pat.sprintf ~loc "inh"; Pat.sprintf ~loc "subj" ]  @@
    k (Exp.ident ~loc "inh") (Exp.ident ~loc "subj")
    (* [%expr fun inh subj -> [%e k [%expr inh ] [%expr subj]]] *)

  method! app_transformation_expr ~loc trf inh subj =
    (* we ignore inherited argument by default *)
    Exp.app_list ~loc trf [inh; subj]

end

end
