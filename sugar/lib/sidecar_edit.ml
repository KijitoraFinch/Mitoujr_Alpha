type node_kind =
  | Scalar of string
  | Mapping of Yaml.layout_style * (node * node) list
  | Sequence of node list
  | Other

and node = {
  kind : node_kind;
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
            end_character = position.Yaml.Stream.Event.end_mark.index;
          },
          rest )
  | (Yaml.Stream.Event.Alias _, position) :: rest ->
      Ok
        ( {
            kind = Other;
            end_character = position.Yaml.Stream.Event.end_mark.index;
          },
          rest )
  | (Yaml.Stream.Event.Sequence_start _, _position) :: rest ->
      let rec members acc = function
        | (Yaml.Stream.Event.Sequence_end, ending) :: tail ->
            Ok
              ( {
                  kind = Sequence (List.rev acc);
                  end_character = ending.Yaml.Stream.Event.end_mark.index;
                },
                tail )
        | [] -> Error (`Msg "unterminated YAML sequence")
        | events ->
            let* member, rest = parse_node events in
            members (member :: acc) rest
      in
      members [] rest
  | (Yaml.Stream.Event.Mapping_start { style; _ }, _position) :: rest ->
      let rec pairs acc = function
        | (Yaml.Stream.Event.Mapping_end, ending) :: tail ->
            Ok
              ( {
                  kind = Mapping (style, List.rev acc);
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

let annotation_insertion_offset content =
  let* events = events content |> Result.map_error (fun (`Msg message) -> message) in
  let* root =
    document_node events |> Result.map_error (fun (`Msg message) -> message)
  in
  match root.kind with
  | Mapping (_, members) ->
      let annotation =
        List.find_map
          (fun (key, value) ->
            match key.kind with
            | Scalar "annotations" -> Some value
            | _ -> None)
          members
      in
      (match annotation with
      | Some { kind = Mapping (`Block, _); end_character; _ } ->
          byte_offset_of_character_index content end_character
      | Some { kind = Mapping _; _ } ->
          Error "derive requires a block-style annotations mapping"
      | Some _ -> Error "annotations must be a mapping"
      | None -> Error "sidecar has no annotations mapping")
  | _ -> Error "sidecar root must be a mapping"
