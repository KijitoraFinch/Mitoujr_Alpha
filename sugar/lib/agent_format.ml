let selector = function
  | Selector.Whole_observation -> ""
  | Selector.Region_id id -> "#" ^ Identifier.to_string id
  | Selector.Text_range range ->
      Printf.sprintf "#bytes=%d:%d" (Text_range.start range)
        (Text_range.end_ range)
  | Selector.Row_filter filter ->
      let literal = function
        | Selector.Literal.String value -> Printf.sprintf "%S" value
        | Selector.Literal.Int value -> string_of_int value
        | Selector.Literal.Bool value -> string_of_bool value
      in
      let conditions =
        Selector.Row_filter.conditions filter
        |> List.map (fun (field, value) ->
               Selector.Field_name.to_string field ^ "=" ^ literal value)
        |> String.concat ","
      in
      "#where(" ^ conditions ^ ")"
  | Selector.Extension extension ->
      Printf.sprintf "#extension(%s:%s)"
        (Selector.Extension.schema extension)
        (Selector.Extension.value extension |> Yojson.Safe.to_string)

let origin = function
  | Origin.Workspace path -> Workspace_path.to_canonical_string path
  | Origin.Git value ->
      "git:" ^ value.repo ^ ":" ^ Option.value ~default:"HEAD" value.rev
      ^ ":" ^ value.path
  | Origin.Web url -> url
  | Origin.Generated name -> "generated:" ^ name
  | Origin.External uri -> uri
  | Origin.Extension value -> value.observer ^ ":" ^ value.locator

let address value =
  origin (Region_address.origin value)
  ^ selector (Region_address.selector value)

let region_ref ~observations = function
  | Region_ref.Address value -> address value
  | Region_ref.Resolved id ->
      let observation =
        List.find_opt
          (fun observation ->
            Observation_id.equal (Region_id.observation id) (Observation.id observation))
          observations
      in
      let observation =
        match observation with
        | Some observation -> origin (Observation.origin observation)
        | None -> Observation_id.to_string (Region_id.observation id)
      in
      observation ^ "#" ^ (Region_id.local id |> Identifier.to_string)
