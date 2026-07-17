type match_ = {
  range : Text_range.t;
  display : string;
}

type selection = No_match | One of match_ | Ambiguous

let ( let* ) = Result.bind

let rec validate_json path = function
  | `Assoc members ->
      let names = List.map fst members in
      let sorted = List.sort String.compare names in
      let rec duplicate = function
        | left :: (right :: _ as rest) ->
            String.equal left right || duplicate rest
        | [] | [ _ ] -> false
      in
      if duplicate sorted then Error (path ^ ": duplicate object key")
      else
        List.fold_left
          (fun result (name, value) ->
            let* () = result in
            validate_json (path ^ "." ^ name) value)
          (Ok ()) members
  | `List values ->
      List.mapi
        (fun index value -> validate_json (Printf.sprintf "%s[%d]" path index) value)
        values
      |> List.fold_left
           (fun result item -> let* () = result in item)
           (Ok ())
  | `Float value when Float.is_nan value || Float.is_infinite value ->
      Error (path ^ ": non-finite number")
  | `String value when not (Utf8.is_valid value) ->
      Error (path ^ ": string must be valid UTF-8")
  | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ -> Ok ()
  | `Tuple _ | `Variant _ -> Error (path ^ ": non-JSON value")

let integer_equal expected = function
  | `Int actual -> expected = actual
  | `Intlit actual -> (
      match int_of_string_opt actual with Some value -> expected = value | None -> false)
  | _ -> false

let literal_equal expected actual =
  match expected with
  | Selector.Literal.String value -> (
      match actual with `String candidate -> String.equal value candidate | _ -> false)
  | Selector.Literal.Int value -> integer_equal value actual
  | Selector.Literal.Bool value -> (
      match actual with `Bool candidate -> Bool.equal value candidate | _ -> false)

let row_matches filter members =
  Selector.Row_filter.conditions filter
  |> List.for_all (fun (field, expected) ->
         let name = Selector.Field_name.to_string field in
         match List.assoc_opt name members with
         | None -> false
         | Some actual -> literal_equal expected actual)

let lines content =
  let length = String.length content in
  let rec loop start index acc =
    if index = length then
      if start = length then List.rev acc
      else List.rev ((start, length, String.sub content start (length - start)) :: acc)
    else if content.[index] = '\n' then
      let line_end = if index > start && content.[index - 1] = '\r' then index - 1 else index in
      let line = String.sub content start (line_end - start) in
      loop (index + 1) (index + 1) ((start, line_end, line) :: acc)
    else loop start (index + 1) acc
  in
  loop 0 0 []

let parse_line index line =
  try
    let json = Yojson.Safe.from_string line in
    let* () = validate_json (Printf.sprintf "$line[%d]" index) json in
    match json with
    | `Assoc members -> Ok members
    | _ -> Error (Printf.sprintf "$line[%d]: expected a JSON object" index)
  with Yojson.Json_error message ->
    Error (Printf.sprintf "$line[%d]: invalid JSON: %s" index message)

let select filter content =
  if not (Utf8.is_valid content) then Error "JSONL artifact must be valid UTF-8"
  else
    let* matches =
      lines content
      |> List.mapi (fun index (start, end_, line) ->
             if String.trim line = "" then Ok None
             else
               let* members = parse_line index line in
               if row_matches filter members then
                 let* range = Text_range.make ~start ~end_ in
                 Ok (Some { range; display = line })
               else Ok None)
      |> List.fold_left
           (fun result item ->
             let* acc = result in
             let* item = item in
             Ok (match item with None -> acc | Some value -> value :: acc))
           (Ok [])
      |> Result.map List.rev
    in
    match matches with
    | [] -> Ok No_match
    | [ value ] -> Ok (One value)
    | _ -> Ok Ambiguous
