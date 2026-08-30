type selected = Built_in_workspace_file | Installed of Installed_extension.t

let select registry origin =
  match origin with
  | Origin.Workspace _ -> Ok (Some Built_in_workspace_file)
  | Origin.Extension { observer; _ } ->
      let matches =
        Registry_snapshot.extensions registry
        |> List.filter (fun extension ->
               let capability = Installed_extension.capability extension in
               Capability.kind capability = Capability.Resource_observer
               && String.equal (Capability.name capability)
                    (Resource_observer.name observer)
               && String.equal (Capability.version capability)
                    (Resource_observer.version observer))
      in
      (match matches with
      | [] -> Ok None
      | [ extension ] -> Ok (Some (Installed extension))
      | _ -> Error "Resource Observer identity is ambiguous in RegistrySnapshot")
  | Origin.Git _ | Origin.Web _ | Origin.Generated _ | Origin.External _ ->
      Ok None
