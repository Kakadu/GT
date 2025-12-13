  $ ../ppx/pp_gt.exe -h

  $ cat > a.ml << EOF
  > type nonrec t = [%error "An error in the type definition"]
  >   [@@deriving gt]
  > EOF
  $ cat a.ml
  $ OCAMLRUNPARAM='b=1' ../ppx/pp_gt.exe a.ml
  $ ocamlc -c -stop-after typing a.ml -pp ../ppx/pp_gt.exe