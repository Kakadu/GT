#load "q_MLast.cmo";;

open Pa_gt.Plugin
open List
open Printf

let _ =
  register "gmap"
    (fun loc descriptor ->
       let module H = Helper (struct let loc = loc end) in
       H.(
        let gen   = name_generator (descriptor.name :: descriptor.parameters) in
        let imgs  = map (fun a -> gen#generate (syn_parameter a)) descriptor.parameters in
        let targs = combine descriptor.parameters imgs in
        {
          inh_t = T.id "unit";
          syn_t = T.app (T.id descriptor.name :: map T.var imgs);
          transformer_parameters = flatten (map (fun (x, y) -> [x; y]) targs);
          inh_t_of_parameter = (fun _ -> T.id "unit");
          syn_t_of_parameter = (fun type_parameter ->
            try T.var (assoc type_parameter targs)
            with Not_found ->
              raise (Generic_extension (sprintf "arg_img not found (%s)" type_parameter))
          )
        },
        let rec map_arg env = function
        | arg, (Variable _ | Self _) -> <:expr< $E.lid arg$.GT.fx () >>
        | arg, Tuple (_, elems) ->
            let args = mapi (fun i _ -> env.new_name (sprintf "e%d" i)) elems in
            <:expr<
               let $P.tuple (map P.id args)$ = $E.id arg$ in
               $E.tuple (map (map_arg env) (combine args elems))$
            >>
        | arg, typ ->
            (match env.trait "map" typ with
             | None   -> E.id arg
             | Some e -> <:expr< $e$ () $E.id arg$ >>
            )
        in
        object
          inherit plugin_generator
          method record env fields =
            let values = map (map_arg env) (map (fun (n, (_, _, t)) -> n, t) fields) in
            E.record (combine (map (fun (_, (n, _, _)) -> P.id n) fields) values)

          method tuple env elems = E.tuple (map (map_arg env) elems)

          method constructor env name args =
            E.app (((if descriptor.is_polymorphic_variant then E.variant else E.id) name)::
                   map (map_arg env) args
                  )
        end
       )
    )
