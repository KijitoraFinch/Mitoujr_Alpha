let suffix = ".annotations.yaml"

let is_metadata path =
  Workspace_path.to_canonical_string path |> String.ends_with ~suffix

let for_primary path =
  Workspace_path.to_canonical_string path ^ suffix
  |> Workspace_path.of_canonical_string
