type t = {
  value : Yojson.Safe.t;
  canonical_json : string;
}

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let rec normalize path = function
  | `Null -> Ok `Null
  | `Bool value -> Ok (`Bool value)
  | `String value when Utf8.is_valid value -> Ok (`String value)
  | `String _ -> Error (path ^ ": string must be valid UTF-8")
  | `Int value when Protocol_integer.is_safe value -> Ok (`Int value)
  | `Int _ -> Error (path ^ ": integer exceeds the protocol safe range")
  | `Intlit value -> (
      match int_of_string_opt value with
      | Some value when Protocol_integer.is_safe value -> Ok (`Int value)
      | _ -> Error (path ^ ": integer exceeds the protocol safe range"))
  | `List values ->
      values
      |> List.mapi (fun index value ->
             normalize (Printf.sprintf "%s[%d]" path index) value)
      |> List.fold_left
           (fun result item ->
             Result.bind result (fun values ->
                 Result.map (fun value -> value :: values) item))
           (Ok [])
      |> Result.map List.rev
      |> Result.map (fun values -> `List values)
  | `Assoc fields ->
      if List.exists (fun (name, _) -> not (Utf8.is_valid name)) fields then
        Error (path ^ ": object field must be valid UTF-8")
      else if duplicate_name fields then
        Error (path ^ ": object fields must be unique")
      else
        fields
        |> List.sort (fun (left, _) (right, _) -> String.compare left right)
        |> List.fold_left
             (fun result (name, value) ->
               Result.bind result (fun fields ->
                   Result.map
                     (fun value -> (name, value) :: fields)
                     (normalize (path ^ "." ^ name) value)))
             (Ok [])
        |> Result.map List.rev
        |> Result.map (fun fields -> `Assoc fields)
  | `Float _ -> Error (path ^ ": floating-point values are not supported")
  | `Tuple _ | `Variant _ -> Error (path ^ ": value must be valid JSON")

let make ?(path = "$value") value =
  Result.map
    (fun value ->
      { value; canonical_json = Yojson.Safe.to_string value })
    (normalize path value)

let to_yojson value = value.value
let canonical_json value = value.canonical_json
let compare left right = String.compare left.canonical_json right.canonical_json
let equal left right = compare left right = 0
