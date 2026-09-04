type selected = Built_in_workspace_check | Installed of Installed_extension.t

let select_all registry =
  let installed =
    Registry_snapshot.extensions registry
    |> List.filter (fun extension ->
           Installed_extension.capability extension |> Capability.kind
           = Capability.Auditor)
    |> List.map (fun extension -> Installed extension)
  in
  Built_in_workspace_check :: installed
