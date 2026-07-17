open Monika_sugar

let fail message =
  prerr_endline ("UTF-8 corpus failed: " ^ message);
  exit 1

let field name fields =
  match List.assoc_opt name fields with
  | Some value -> value
  | None -> fail ("missing field: " ^ name)

let string = function
  | `String value -> value
  | _ -> fail "expected string"

let bool = function
  | `Bool value -> value
  | _ -> fail "expected boolean"

let byte hex offset =
  let digit = function
    | '0' .. '9' as value -> Char.code value - Char.code '0'
    | 'a' .. 'f' as value -> Char.code value - Char.code 'a' + 10
    | _ -> fail "hex corpus values must be lowercase"
  in
  Char.chr ((digit hex.[offset] * 16) + digit hex.[offset + 1])

let bytes_of_hex hex =
  if String.length hex mod 2 <> 0 then fail "hex corpus value has odd length";
  String.init (String.length hex / 2) (fun index -> byte hex (index * 2))

let check_case = function
  | `Assoc fields ->
      let id = field "id" fields |> string in
      let value = field "hex" fields |> string |> bytes_of_hex in
      let expected = field "valid" fields |> bool in
      if Utf8.is_valid value <> expected then
        fail (id ^ ": unexpected classification")
  | _ -> fail "case must be an object"

let () =
  let corpus =
    match Array.to_list Sys.argv with
    | [ _; path ] -> path
    | _ -> fail "expected one corpus path argument"
  in
  match Yojson.Safe.from_file corpus with
  | `List cases -> List.iter check_case cases
  | _ -> fail "corpus must be an array"
