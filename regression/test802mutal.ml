type a = [`A of b | `C of GT.int   ]
and  b = [`B of a | `D of GT.string]
[@@deriving gt ~options:{show}]

type c = [ b | `E of GT.int ]
[@@deriving gt ~options:{show}]
