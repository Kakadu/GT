  $ ../ppx/pp_gt.exe -h

  $ cat > a.ml << EOF
  > type nonrec t = [%error "error text"] [@@deriving gt]
  > EOF
  $ cat a.ml
  $ OCAMLRUNPARAM=b ../ppx/pp_gt.exe a.ml