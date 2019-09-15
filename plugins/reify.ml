(*
 * Generic transformers: plugins.
 * Copyright (C) 2016-2020
 *   Dmitrii Kosarev aka Kakadu
 * St.Petersburg State University, JetBrains Research
 *)

(** {i Reify} plugin

  *)

open Base
open Ppxlib
open HelpersBase
open Printf

let trait_name = "reify"

module Make(AstHelpers : GTHELPERS_sig.S) = struct

let trait_name = trait_name

open AstHelpers

class g args tdecls = object(self)
  inherit [loc, Exp.t, Typ.t, type_arg, Ctf.t, Cf.t, Str.t, Sig.t] Plugin_intf.public_plugin

  method trait_name = trait_name

  method do_single_sig ~loc ~is_rec _ = []
  method do_single     ~loc ~is_rec _ = []
  method do_mutuals     ~loc ~is_rec _ = failwith "not implemented"
  method do_mutuals_sigs ~loc ~is_rec = failwith "not implemented"

  method need_inh_attr = true

  method eta_and_exp ~center _ = center
  method make_final_trans_function_typ ~loc _ = Typ.var ~loc "typ"

end

let create = (new g :> Plugin.Make(AstHelpers).plugin_constructor)

end

let register () =
  Expander.register_plugin trait_name (module Make: Plugin_intf.MAKE)

let () = register ()
