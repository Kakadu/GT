#load "q_MLast.cmo";;

open Pa_gt.Plugin
open List
open Printf
open MLast
open Ploc

exception Found of int

let _ =
  register "eq"
    (fun loc descriptor ->
       let module H = Helper (struct let loc = loc end) in
       H.(
        let ng   = name_generator descriptor.parameters in
        let self = ng#generate "self" in
        {
          inh_t = if descriptor.is_polyvar
                  then T.app (T.id (type_open_t descriptor.name) :: map T.var (self :: descriptor.parameters))
                  else T.app (T.id descriptor.name :: map T.var descriptor.parameters);
          syn_t = T.id "bool";
          transformer_parameters = if descriptor.is_polyvar then self :: descriptor.parameters else descriptor.parameters;
          inh_t_of_parameter = (fun a -> T.var a);
          syn_t_of_parameter = (fun _ -> T.id "bool");
        },
        let rec many env arg args =
          fold_left
            (fun acc (b, typ) ->
               let test =
                  match typ with
                 | Instance (_, args, qname) ->
                     (match env.trait "eq" typ with
                      | None   -> <:expr< True >>
                      | Some e ->
                           let rec name = function
                          | [n]  -> <:expr< $e$ ($E.id (arg b)$) $E.id b$ >>
                          | _::t -> name t
                          in
                          name qname
                     )
                 | Tuple (_, elems) ->
                     let args_a = mapi (fun i _ -> env.new_name (sprintf "e%d" i)) elems in
                     let args_b = mapi (fun i _ -> env.new_name (sprintf "e%d" i)) elems in
                     let elems  = combine args_a elems in
                     let args   = combine args_a args_b in
                     let arg' a = assoc a args in
                     <:expr<
                       let $P.tuple (map P.id args_a)$ = $E.lid b$       in
                       let $P.tuple (map P.id args_b)$ = $E.lid (arg b)$ in
                       $many env arg' elems$
                     >>
                 | Variable (_, a) -> <:expr< $E.id b$.GT.fx ($E.id (arg b)$) >>
                 | Self     _      -> <:expr< $E.id b$.GT.fx ($E.id (arg b)$) >>
                 | Arbitrary _     -> <:expr< true >>
              in
              <:expr< $acc$ && $test$ >>
            )
            <:expr< True >>
          args
        in
        object
          inherit generator
          method record env fields =
            let args   = map (fun a -> a, env.new_name a) (map fst fields) in
            let arg  a = assoc a args in
            let branch = many env arg (map (fun (a, (_, _, t)) -> a, t) fields) in
            <:expr< match $E.id env.inh$ with
                    | $P.record (map (fun (a, (f, _, _)) -> P.id f, P.id (arg a)) fields)$ -> $branch$
                    end
            >>

          method tuple env elems  =
            let args   = map (fun a -> a, env.new_name a) (map fst elems) in
            let arg  a = assoc a args in
            let branch = many env arg elems in
            <:expr< match $E.id env.inh$ with
                    | $P.tuple (map (fun (_, a) -> P.id a) args)$ -> $branch$
                    end
            >>

          method constructor env name cargs =
            let args   = map (fun a -> a, env.new_name a) (map fst cargs) in
            let arg  a = assoc a args in
            let branch = many env arg cargs in
            <:expr< match $E.id env.inh$ with
                    | $P.app (((if descriptor.is_polyvar then P.variant else P.uid) name)::(map (fun (_, a) -> P.id a) args))$ -> $branch$
                    | _ -> False
                    end
            >>
        end
       )
    )
