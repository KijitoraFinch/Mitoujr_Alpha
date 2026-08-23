type component = Globstar | Segment of string
type t = component list

let invalid message = Error ("invalid path glob: " ^ message)

let validate_segment segment =
  if String.equal segment "." || String.equal segment ".." then
    invalid "dot and dot-dot segments are not allowed"
  else if String.equal segment "**" then Ok Globstar
  else
    let length = String.length segment in
    let rec loop index =
      if index = length then Ok (Segment segment)
      else
        match segment.[index] with
        | '\000' -> invalid "NUL is not allowed"
        | '?' | '[' | ']' | '\\' ->
            invalid "only literal characters and * are allowed within a segment"
        | '*' when index + 1 < length && Char.equal segment.[index + 1] '*' ->
            invalid "** must occupy a complete path segment"
        | _ -> loop (index + 1)
    in
    loop 0

let make pattern =
  if String.length pattern = 0 then invalid "the pattern must not be empty"
  else if not (Utf8.is_valid pattern) then invalid "the pattern must be valid UTF-8"
  else if Char.equal pattern.[0] '/' then invalid "the pattern must be relative"
  else if Char.equal pattern.[String.length pattern - 1] '/' then
    invalid "the pattern must not end with a separator"
  else
    let segments = String.split_on_char '/' pattern in
    let rec loop accumulated = function
      | [] -> Ok (List.rev accumulated)
      | "" :: _ -> invalid "empty path segments are not allowed"
      | segment :: rest -> (
          match validate_segment segment with
          | Error _ as error -> error
          | Ok segment -> loop (segment :: accumulated) rest)
    in
    loop [] segments

let segment_matches pattern value =
  let pattern_length = String.length pattern in
  let value_length = String.length value in
  let memo = Hashtbl.create 32 in
  let rec matches pattern_index value_index =
    match Hashtbl.find_opt memo (pattern_index, value_index) with
    | Some result -> result
    | None ->
        let result =
          if pattern_index = pattern_length then value_index = value_length
          else if Char.equal pattern.[pattern_index] '*' then
            matches (pattern_index + 1) value_index
            || (value_index < value_length
               && matches pattern_index (value_index + 1))
          else
            value_index < value_length
            && Char.equal pattern.[pattern_index] value.[value_index]
            && matches (pattern_index + 1) (value_index + 1)
        in
        Hashtbl.add memo (pattern_index, value_index) result;
        result
  in
  matches 0 0

let matches pattern path =
  let pattern = Array.of_list pattern in
  let path = Workspace_path.segments path |> Array.of_list in
  let pattern_length = Array.length pattern in
  let path_length = Array.length path in
  let memo = Hashtbl.create 32 in
  let rec loop pattern_index path_index =
    match Hashtbl.find_opt memo (pattern_index, path_index) with
    | Some result -> result
    | None ->
        let result =
          if pattern_index = pattern_length then path_index = path_length
          else
            match pattern.(pattern_index) with
            | Globstar ->
                loop (pattern_index + 1) path_index
                || (path_index < path_length
                   && loop pattern_index (path_index + 1))
            | Segment segment ->
                path_index < path_length
                && segment_matches segment path.(path_index)
                && loop (pattern_index + 1) (path_index + 1)
        in
        Hashtbl.add memo (pattern_index, path_index) result;
        result
  in
  loop 0 0
