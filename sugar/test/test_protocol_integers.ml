open Monika_sugar

let fail message =
  prerr_endline ("protocol integer corpus failed: " ^ message);
  exit 1

let field name fields =
  match List.assoc_opt name fields with
  | Some value -> value
  | None -> fail ("missing field: " ^ name)

let string = function
  | `String value -> value
  | _ -> fail "expected string"

let int = function
  | `Int value -> value
  | _ -> fail "expected integer"

let bool = function
  | `Bool value -> value
  | _ -> fail "expected boolean"

let check_case = function
  | `Assoc fields ->
      let id = field "id" fields |> string in
      let domain = field "domain" fields |> string in
      let value = field "value" fields |> int in
      let expected = field "valid" fields |> bool in
      let actual =
        match domain with
        | "signed" -> Protocol_integer.is_safe value
        | "nonnegative" -> Protocol_integer.is_nonnegative_safe value
        | _ -> fail (id ^ ": unknown domain: " ^ domain)
      in
      if actual <> expected then fail (id ^ ": unexpected classification")
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
