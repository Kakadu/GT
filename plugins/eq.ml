(** {i Eq} plugin: receive another value as inherited attribute and test for equality.

    Very similar to {!Compare} plugin.

    For type declaration [type ('a,'b,...) typ = ...] it will create a transformation
    function with type

    [('a -> 'a -> bool) ->
     ('b -> 'b -> bool) -> ... -> ('a,'b,...) typ -> bool ]

    Inherited attribute' is the same as argument, synthetized attribute is {!GT.comparison}.
*)

open Base
open Ppxlib
open Printf

let trait_name = "eq"

module Make(AstHelpers : GTHELPERS_sig.S) = struct

let trait_name = trait_name

module C = Compare.Make(AstHelpers)

open AstHelpers

class g initial_args tdecls = object(self: 'self)
  inherit C.g initial_args tdecls as super

  method! trait_name = trait_name

  method! syn_of_param ~loc s = Typ.sprintf ~loc "bool"
  method! main_syn ~loc ?in_class tdecl = self#syn_of_param ~loc "dummy"

  (* method! trf_scheme ~loc =
   *   Typ.(arrow ~loc (var ~loc "a") @@
   *        arrow ~loc (var ~loc "a") (constr ~loc (Lident "bool") [])) *)

  method! on_different_constructors ~loc is_poly other_name cname arg_typs =
    Exp.false_ ~loc
  method! chain_exprs ~loc e1 e2 =
    Exp.app_list ~loc (Exp.ident ~loc "&&") [ e1; e2 ]
  method! chain_init ~loc = Exp.true_ ~loc


end

let create =
  (new g :>
     (Plugin_intf.plugin_args -> Ppxlib.type_declaration list ->
      (loc, Exp.t, Typ.t, type_arg, Ctf.t, Cf.t, Str.t, Sig.t) Plugin_intf.typ_g))
end

let register () =
  Expander.register_plugin trait_name (module Make: Plugin_intf.PluginRes)

let () = register ()
