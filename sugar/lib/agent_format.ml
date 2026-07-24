let selector = function
  | Selector.Whole_artifact -> ""
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

let origin = function
  | Artifact.Workspace path -> Workspace_path.to_canonical_string path
  | Artifact.Git value ->
      "git:" ^ value.repo ^ ":" ^ Option.value ~default:"HEAD" value.rev
      ^ ":" ^ value.path
  | Artifact.Web url -> url
  | Artifact.Generated name -> "generated:" ^ name
  | Artifact.External uri -> uri

let address value =
  origin (Region_address.artifact value)
  ^ selector (Region_address.selector value)

let region_ref ~artifacts = function
  | Region_ref.Address value -> address value
  | Region_ref.Resolved id ->
      let artifact =
        List.find_opt
          (fun artifact ->
            Artifact_id.equal (Region_id.artifact id) (Artifact.id artifact))
          artifacts
      in
      let artifact =
        match artifact with
        | Some artifact -> origin (Artifact.origin artifact)
        | None -> Artifact_id.to_string (Region_id.artifact id)
      in
      artifact ^ "#" ^ (Region_id.local id |> Identifier.to_string)
