let ( let* ) = Result.bind

type observations = {
  observations : Observation.t list;
  regions : Region.t list;
  references : Reference.t list;
  annotations : Annotation.t list;
  diagnostics : Diagnostic.t list;
}

let empty_observations =
  { observations = []; regions = []; references = []; annotations = []; diagnostics = [] }

let command_result ?summary ?(diagnostics = []) ?(observations = [])
    ?(regions = []) ?(references = []) ?(annotations = []) ~termination () =
  match
    Command_result.make ~command:"check" ~termination
      ~effect:Command_result.No_change ~diagnostics ~observations ~regions
      ~references ~annotations ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"check"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let terminal_result scan =
  match Command_result.termination scan with
  | Command_result.Completed -> None
  | Command_result.Usage_failure message ->
      Some
        (command_result
           ~termination:(Command_result.Usage_failure message)
           ~summary:[ ("message", Command_result.Text message) ] ())
  | Command_result.Internal_failure _ ->
      Some
        (command_result
           ~termination:
             (Command_result.Internal_failure "internal operation failed")
           ~summary:
             [
               ("errorCode", Command_result.Text "filesystem-io");
               ("operation", Command_result.Text "scan-workspace");
             ]
           ())

let markdown_observation observation =
  match Observation.origin observation with
  | Origin.Workspace path -> (
      match List.rev (Workspace_path.segments path) with
      | basename :: _ ->
          Filename.check_suffix basename ".md"
          || Filename.check_suffix basename ".markdown"
      | [] -> false)
  | _ -> false

let inspect_scanned_observation ~workspace observation =
  match Observation.origin observation with
  | Origin.Workspace path ->
      Ok (Workspace_inspect.inspect ~workspace ~observation:path)
  | _ -> Error "scan emitted a non-workspace observation"

let collect_inspection ~workspace observations =
  List.filter markdown_observation observations
  |> List.fold_left
       (fun result observation ->
         let* observations = result in
         let* inspected = inspect_scanned_observation ~workspace observation in
         match Command_result.termination inspected with
         | Command_result.Usage_failure _ | Command_result.Internal_failure _ ->
             Error "inspect-observation"
         | Command_result.Completed ->
             Ok
               {
                 observations = observations.observations @ Command_result.observations inspected;
                 regions = observations.regions @ Command_result.regions inspected;
                 references =
                   observations.references @ Command_result.references inspected;
                 annotations =
                   observations.annotations @ Command_result.annotations inspected;
                 diagnostics =
                   observations.diagnostics @ Command_result.diagnostics inspected;
               })
       (Ok empty_observations)

let merge_observations scanned inspected =
  let replacement id =
    List.find_opt (fun observation -> Observation_id.equal id (Observation.id observation))
      inspected
  in
  List.map
    (fun observation ->
      match replacement (Observation.id observation) with
      | Some current -> current
      | None -> observation)
    scanned

let annotation_location annotation =
  let id = Annotation.id annotation in
  {
    Diagnostic.observation = Some (Annotation_id.observation id);
    region = None;
    annotation = Some id;
    range = None;
  }

let reference_location reference =
  let id = Reference.id reference in
  {
    Diagnostic.observation = Some (Reference_id.observation id);
    region = None;
    annotation = None;
    range = None;
  }

let diagnostic ~code ~message ~location =
  Diagnostic.make ~code ~message ~location ()

let has_sidecar annotation =
  List.exists
    (function Annotation.Sidecar _ -> true | _ -> false)
    (Annotation.materialization annotation)

let has_inline annotation =
  List.exists
    (function Annotation.Markdown_inline _ -> true | _ -> false)
    (Annotation.materialization annotation)

let region_id_of_address address =
  match (Region_address.origin address, Region_address.selector address) with
  | Origin.Workspace path, Selector.Region_id local ->
      let* observation =
        Observation_id.make ("observation:" ^ Workspace_path.to_canonical_string path)
      in
      Region_id.make ~observation ~local:(Identifier.to_string local)
  | _ -> Error "address is not a region-id selector"

let annotation_subject_id annotation =
  match Annotation.subject annotation with
  | Annotation.Region (Region_ref.Resolved id) -> Some id
  | Annotation.Region (Region_ref.Address address) ->
      Result.to_option (region_id_of_address address)

let known_region regions id =
  List.exists (fun region -> Region_id.equal id (Region.id region)) regions

let same_object left right =
  match (Annotation.object_ left, Annotation.object_ right) with
  | Annotation.Reference_object l, Annotation.Reference_object r ->
      Reference_id.equal l r
  | Annotation.Region_object l, Annotation.Region_object r ->
      Region_ref.compare l r = 0
  | Annotation.Literal l, Annotation.Literal r -> String.equal l r
  | _ -> false

let same_semantics left right =
  String.equal (Annotation.predicate left) (Annotation.predicate right)
  && same_object left right

let same_subject left right =
  match (annotation_subject_id left, annotation_subject_id right) with
  | Some l, Some r -> Region_id.equal l r
  | _ -> false

let annotation_diagnostics regions annotations =
  let inline = List.filter has_inline annotations in
  let sidecar = List.filter has_sidecar annotations in
  List.fold_left
    (fun result annotation ->
      let* diagnostics = result in
      let location = annotation_location annotation in
      match annotation_subject_id annotation with
      | None ->
          let* diagnostic =
            diagnostic ~code:Diagnostic.Invalid_selector
              ~message:"annotation subject is not supported by its interpreter"
              ~location
          in
          Ok (diagnostic :: diagnostics)
      | Some subject when not (known_region regions subject) ->
          let* diagnostic =
            diagnostic ~code:Diagnostic.Stale_selector
              ~message:"annotation subject selector does not resolve" ~location
          in
          Ok (diagnostic :: diagnostics)
      | Some _ when has_sidecar annotation ->
          if
            List.exists
              (fun candidate ->
                same_subject annotation candidate
                && not (same_semantics annotation candidate))
              inline
          then
            let* diagnostic =
              diagnostic ~code:Diagnostic.Divergent
                ~message:"inline and sidecar annotations disagree" ~location
            in
            Ok (diagnostic :: diagnostics)
          else if
            List.exists
              (fun candidate ->
                Annotation_id.equal (Annotation.id annotation)
                  (Annotation.id candidate))
              inline
          then Ok diagnostics
          else
            let* diagnostic =
              diagnostic ~code:Diagnostic.Sidecar_only
                ~message:"annotation is materialized only in the sidecar" ~location
            in
            Ok (diagnostic :: diagnostics)
      | Some _ ->
          if
            List.exists
              (fun candidate ->
                Annotation_id.equal (Annotation.id annotation)
                  (Annotation.id candidate))
              sidecar
          then Ok diagnostics
          else
            let* diagnostic =
              diagnostic ~code:Diagnostic.Inline_only
                ~message:"annotation is materialized only inline" ~location
            in
            Ok (diagnostic :: diagnostics))
    (Ok []) annotations
  |> Result.map List.rev

let expectation_matches identity = function
  | Expectation.Digest digest ->
      String.equal (Content_digest.to_string digest)
        (Content_identity.display_hash identity)

let used_reference_ids annotations =
  List.filter_map
    (fun annotation ->
      match Annotation.object_ annotation with
      | Annotation.Reference_object id -> Some id
      | Annotation.Region_object _ | Annotation.Literal _ -> None)
    annotations

let reference_diagnostics ~workspace ~regions ~annotations references =
  let used = used_reference_ids annotations in
  List.fold_left
    (fun result reference ->
      let* diagnostics = result in
      let location = reference_location reference in
      let local = Reference.id reference |> Reference_id.local |> Identifier.to_string in
      let diagnostics =
        if
          List.exists (fun id -> Reference_id.equal id (Reference.id reference)) used
        then Ok diagnostics
        else
          let* diagnostic =
            diagnostic ~code:Diagnostic.Unreferenced_ref
              ~message:("reference " ^ local ^ " is declared but not used")
              ~location
          in
          Ok (diagnostic :: diagnostics)
      in
      let* diagnostics = diagnostics in
      match Reference_resolver.resolve ~workspace ~regions reference with
      | Reference_resolver.Not_found ->
          let* diagnostic =
            diagnostic ~code:Diagnostic.Unresolved_ref
              ~message:("reference " ^ local ^ " target does not resolve")
              ~location
          in
          Ok (diagnostic :: diagnostics)
      | Reference_resolver.Read_failure ->
          let* diagnostic =
            diagnostic ~code:Diagnostic.Unresolved_ref
              ~message:("reference " ^ local ^ " target cannot be read safely")
              ~location
          in
          Ok (diagnostic :: diagnostics)
      | Reference_resolver.Invalid_selector message ->
          let* diagnostic =
            diagnostic ~code:Diagnostic.Invalid_selector ~message ~location
          in
          Ok (diagnostic :: diagnostics)
      | Reference_resolver.Resolved resolved ->
          if
            List.for_all (expectation_matches resolved.content_identity)
              (Reference.expectations reference)
          then Ok diagnostics
          else
            let* diagnostic =
              diagnostic ~code:Diagnostic.Expectation_failed
                ~message:
                  ("reference " ^ local
                 ^ " target does not satisfy its expectation")
                ~location
            in
            Ok (diagnostic :: diagnostics))
    (Ok []) references
  |> Result.map List.rev

let check ~workspace =
  let scan = Workspace_scan.scan ~workspace in
  match terminal_result scan with
  | Some result -> result
  | None ->
      let inventory = Command_result.observations scan in
      (match collect_inspection ~workspace inventory with
      | Error operation ->
          command_result
            ~termination:
              (Command_result.Internal_failure "internal operation failed")
            ~summary:
              [
                ("errorCode", Command_result.Text "filesystem-io");
                ("operation", Command_result.Text operation);
              ]
            ()
      | Ok collected ->
          let observations =
            merge_observations inventory collected.observations
          in
          (match
             ( annotation_diagnostics collected.regions collected.annotations,
               reference_diagnostics ~workspace ~regions:collected.regions
                 ~annotations:collected.annotations collected.references )
           with
          | Error _, _ | _, Error _ ->
              Command_result.internal_error ~command:"check"
                ~error_code:"internal-invariant"
                ~operation:"construct-diagnostic"
          | Ok annotation_diagnostics, Ok reference_diagnostics ->
              let diagnostics =
                Command_result.diagnostics scan @ collected.diagnostics
                @ annotation_diagnostics @ reference_diagnostics
              in
              command_result ~termination:Command_result.Completed ~diagnostics
                ~observations
                ~summary:
                  [
                    ( "diagnostics",
                      Command_result.Count (List.length diagnostics) );
                  ]
                ()))
