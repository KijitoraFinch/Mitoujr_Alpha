type selected = Built_in_inline_to_sidecar | Installed of Installed_extension.t

let find_exact registry ~name ~version =
  let built_in =
    String.equal name "inline-to-sidecar" && String.equal version "1"
  in
  let installed =
    Registry_snapshot.extensions registry
    |> List.find_opt (fun extension ->
           let capability = Installed_extension.capability extension in
           Capability.kind capability = Capability.Deriver
           && String.equal (Capability.name capability) name
           && String.equal (Capability.version capability) version)
  in
  match built_in, installed with
  | true, Some _ ->
      Error "installed Deriver identity collides with built-in inline-to-sidecar@1"
  | true, None -> Ok (Some Built_in_inline_to_sidecar)
  | false, Some extension -> Ok (Some (Installed extension))
  | false, None -> Ok None
