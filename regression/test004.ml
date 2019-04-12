@type a = [`A of b | `C of GT.int] with show
and   b = [`B of a GT.list | `D of GT.string] with show

let x = `A (`B [`C 3; `C 4])
let y = `B [`A (`D "3"); `C 5]

let () =
  Printf.printf "%s\n" (GT.show(a) x);
  Printf.printf "%s\n" (GT.show(b) y)

class show_a' (for_a,for_b) fself =
  object(this)
    inherit [_] show_a_t_stub (for_a,for_b) fself as super
    method c_C i x y = "new " ^ super#c_C i x y
    method c_A _ _ x = Printf.sprintf "new A %a" for_b x
  end


let show_a' () s =
  (fst @@ fix_a (new show_a') (new show_b_t_stub)) () s

(* let new_fix =
 *   Fix_show_a.fixv
 *     (fun f ->
 *        {call =
 *          fun (type a) (sym : a Ishow_a.i) ->
 *            (match sym with
 *               Ishow_a.A -> GT.transform_gc gcata_a (new show_a'  f)
 *             | Ishow_a.B -> GT.transform_gc gcata_b (new show_b_t f)
 *             : a) } ) *)

let () =
  Printf.printf "%s\n" (show_a' () x)
