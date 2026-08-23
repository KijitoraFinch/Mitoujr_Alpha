type association = Not_associated | Associated of Observation_type.t

let ( let* ) = Result.bind

let compile_globs values =
  List.fold_right
    (fun value result ->
      let* glob = Path_glob.make value in
      let* globs = result in
      Ok (glob :: globs))
    values (Ok [])

let validate capability =
  match Capability.applies_to capability with
  | None -> Ok ()
  | Some applies_to ->
      let* _ = compile_globs applies_to.path_globs in
      Ok ()

let observation_type = function
  | None -> Ok Observation_type.binary
  | Some name -> Observation_type.make ~name ~version:"1" ()

let associate capability ~path =
  match Capability.applies_to capability with
  | None ->
      let* observation_type =
        observation_type (Workspace_observation_type.inferred_name path)
      in
      Ok (Associated observation_type)
  | Some applies_to ->
      let* path_globs = compile_globs applies_to.path_globs in
      let path_matches =
        path_globs = [] || List.exists (fun glob -> Path_glob.matches glob path) path_globs
      in
      if not path_matches then Ok Not_associated
      else
        match Workspace_observation_type.inferred_name path with
        | Some inferred
          when applies_to.media_types = []
               || List.exists (String.equal inferred) applies_to.media_types ->
            let* observation_type = observation_type (Some inferred) in
            Ok (Associated observation_type)
        | Some _ -> Ok Not_associated
        | None -> (
            match (applies_to.path_globs, applies_to.media_types) with
            | [], [] -> Error "extension applicability has no conditions"
            | [], _ :: _ -> Ok Not_associated
            | _ :: _, [] -> Ok (Associated Observation_type.binary)
            | _ :: _, [ media_type ] ->
                let* observation_type = observation_type (Some media_type) in
                Ok (Associated observation_type)
            | _ :: _, _ :: _ :: _ ->
                Error
                  "extension applicability maps one path to multiple media types")

let accepts capability ~observation =
  let* () = validate capability in
  match Capability.applies_to capability with
  | None -> Ok true
  | Some applies_to ->
      let* path_globs = compile_globs applies_to.path_globs in
      let path_matches =
        if path_globs = [] then true
        else
          match Observation.origin observation with
          | Origin.Workspace path ->
              List.exists (fun glob -> Path_glob.matches glob path) path_globs
          | Origin.Git _
          | Origin.Web _
          | Origin.Generated _
          | Origin.External _
          | Origin.Extension _ ->
              false
      in
      let observation_type = Observation.observation_type observation in
      let media_type_matches =
        applies_to.media_types = []
        || List.exists
             (String.equal (Observation_type.name observation_type))
             applies_to.media_types
      in
      Ok (path_matches && media_type_matches)
