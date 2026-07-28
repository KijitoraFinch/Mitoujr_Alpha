type node_kind =
  | Scalar of string
  | Mapping of Yaml.layout_style * (node * node) list
  | Sequence of Yaml.layout_style * node list
  | Other

and node = {
  kind : node_kind;
  start_character : int;
  end_character : int;
}

let ( let* ) = Result.bind

let events content =
  let* parser = Yaml.Stream.parser content in
  let rec loop acc =
    let* event, position = Yaml.Stream.do_parse parser in
    let acc = (event, position) :: acc in
    match event with
    | Yaml.Stream.Event.Stream_end -> Ok (List.rev acc)
    | _ -> loop acc
  in
  loop []

let rec parse_node = function
  | (Yaml.Stream.Event.Scalar scalar, position) :: rest ->
      Ok
        ( {
            kind = Scalar scalar.Yaml.value;
            start_character = position.Yaml.Stream.Event.start_mark.index;
            end_character = position.Yaml.Stream.Event.end_mark.index;
          },
          rest )
  | (Yaml.Stream.Event.Alias _, position) :: rest ->
      Ok
        ( {
            kind = Other;
            start_character = position.Yaml.Stream.Event.start_mark.index;
            end_character = position.Yaml.Stream.Event.end_mark.index;
          },
          rest )
  | (Yaml.Stream.Event.Sequence_start { style; _ }, position) :: rest ->
      let rec members acc = function
        | (Yaml.Stream.Event.Sequence_end, ending) :: tail ->
            Ok
              ( {
                  kind = Sequence (style, List.rev acc);
                  start_character =
                    position.Yaml.Stream.Event.start_mark.index;
                  end_character = ending.Yaml.Stream.Event.end_mark.index;
                },
                tail )
        | [] -> Error (`Msg "unterminated YAML sequence")
        | events ->
            let* member, rest = parse_node events in
            members (member :: acc) rest
      in
      members [] rest
  | (Yaml.Stream.Event.Mapping_start { style; _ }, position) :: rest ->
      let rec pairs acc = function
        | (Yaml.Stream.Event.Mapping_end, ending) :: tail ->
            Ok
              ( {
                  kind = Mapping (style, List.rev acc);
                  start_character =
                    position.Yaml.Stream.Event.start_mark.index;
                  end_character = ending.Yaml.Stream.Event.start_mark.index;
                },
                tail )
        | [] -> Error (`Msg "unterminated YAML mapping")
        | events ->
            let* key, after_key = parse_node events in
            let* value, after_value = parse_node after_key in
            pairs ((key, value) :: acc) after_value
      in
      pairs [] rest
  | _ -> Error (`Msg "unexpected YAML event while locating sidecar mapping")

let document_node events =
  let rec seek = function
    | ( ( Yaml.Stream.Event.Stream_start _
        | Yaml.Stream.Event.Document_start _ ),
        _ )
      :: rest ->
        seek rest
    | events -> parse_node events |> Result.map fst
  in
  seek events

let mapping_member name members =
  List.find_map
    (fun (key, value) ->
      match key.kind with Scalar candidate when String.equal candidate name -> Some value | _ -> None)
    members

let mapping_pair name members =
  List.find_opt
    (fun (key, _value) ->
      match key.kind with
      | Scalar candidate -> String.equal candidate name
      | _ -> false)
    members

let require_block_mapping path = function
  | { kind = Mapping (`Block, members); _ } -> Ok members
  | { kind = Mapping _; _ } ->
      Error (path ^ " must use a block-style mapping")
  | _ -> Error (path ^ " must be a mapping")

let require_canonical_derived_mapping path = function
  | { kind = Mapping (`Block, members); _ } -> Ok members
  | { kind = Mapping (`Flow, []); _ } -> Ok []
  | { kind = Mapping _; _ } ->
      Error
        (path
        ^ " must use a block-style mapping, except that an empty mapping may use {}")
  | _ -> Error (path ^ " must be a mapping")

let rec validate_canonical_derived_node path node =
  match node.kind with
  | Scalar _ | Other -> Ok ()
  | Mapping (`Flow, []) -> Ok ()
  | Mapping (`Flow, _) ->
      Error
        (path
        ^ " must use block style, except that an empty mapping may use {}")
  | Mapping (`Any, _) -> Error (path ^ " has an unspecified mapping style")
  | Mapping (`Block, members) ->
      List.fold_left
        (fun result (key, value) ->
          let* () = result in
          let* () = validate_canonical_derived_node (path ^ ".<key>") key in
          validate_canonical_derived_node (path ^ ".<value>") value)
        (Ok ()) members
  | Sequence (`Flow, _) -> Error (path ^ " must use a block-style sequence")
  | Sequence (`Any, _) -> Error (path ^ " has an unspecified sequence style")
  | Sequence (`Block, members) ->
      List.fold_left
        (fun result member ->
          let* () = result in
          validate_canonical_derived_node (path ^ "[]") member)
        (Ok ()) members

let validate_layout_profile content =
  let* events = events content |> Result.map_error (fun (`Msg message) -> message) in
  let* root =
    document_node events |> Result.map_error (fun (`Msg message) -> message)
  in
  let* root_members = require_block_mapping "$" root in
  match mapping_member "derived" root_members with
  | None -> Ok ()
  | Some derived ->
      let* derived_members = require_block_mapping "$.derived" derived in
      let* () =
        List.fold_left
          (fun result (key, value) ->
            let* () = result in
            let path =
              match key.kind with
              | Scalar name -> "$.derived." ^ name
              | _ -> "$.derived.<value>"
            in
            validate_canonical_derived_node path value)
          (Ok ()) derived_members
      in
      let* () =
        match mapping_member "refs" derived_members with
        | None -> Ok ()
        | Some refs ->
            require_canonical_derived_mapping "$.derived.refs" refs
            |> Result.map ignore
      in
      (match mapping_member "annotations" derived_members with
      | None -> Ok ()
      | Some annotations ->
          require_canonical_derived_mapping "$.derived.annotations" annotations
          |> Result.map ignore)

let byte_offset_of_character_index content target =
  let length = String.length content in
  let rec loop byte character =
    if character = target then Ok byte
    else if byte >= length then Error "YAML source position is outside the sidecar"
    else
      let leading = Char.code content.[byte] in
      let width =
        if leading land 0x80 = 0 then 1
        else if leading land 0xe0 = 0xc0 then 2
        else if leading land 0xf0 = 0xe0 then 3
        else if leading land 0xf8 = 0xf0 then 4
        else 0
      in
      if width = 0 || byte > length - width then
        Error "sidecar contains invalid UTF-8"
      else loop (byte + width) (character + 1)
  in
  loop 0 0

let optional_derived_section_range content =
  let* events = events content |> Result.map_error (fun (`Msg message) -> message) in
  let* root =
    document_node events |> Result.map_error (fun (`Msg message) -> message)
  in
  match root.kind with
  | Mapping (_, members) ->
      let derived =
        List.find_map
          (fun (key, value) ->
            match key.kind with
            | Scalar "derived" -> Some (key, value)
            | _ -> None)
          members
      in
      (match derived with
      | None -> Ok None
      | Some (key, value) ->
          let* start =
            byte_offset_of_character_index content key.start_character
          in
          let* end_ =
            byte_offset_of_character_index content value.end_character
          in
          Text_range.make ~start ~end_
          |> Result.map Option.some)
  | _ -> Error "sidecar root must be a mapping"

let derived_section_range content =
  let* range = optional_derived_section_range content in
  match range with
  | Some range -> Ok range
  | None -> Error "sidecar has no derived section"

let derived_insertion_offset content =
  let* events = events content |> Result.map_error (fun (`Msg message) -> message) in
  let* root =
    document_node events |> Result.map_error (fun (`Msg message) -> message)
  in
  match root.kind with
  | Mapping (`Block, members) ->
      let insertion_character =
        match mapping_pair "authored" members with
        | Some (key, _) -> key.start_character
        | None -> root.end_character
      in
      byte_offset_of_character_index content insertion_character
  | Mapping _ -> Error "sidecar root must use a block-style mapping"
  | _ -> Error "sidecar root must be a mapping"
