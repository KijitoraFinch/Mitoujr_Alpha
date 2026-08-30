type query_direction = Incoming | Outgoing | Both
type region_scope = Exact | Contained
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_use | Semantic_relation
type result_status = Complete | Incomplete | Failed

type resolution = Endpoint_resolution.t =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

type edge_target =
  | Address_target of Region_address.t
  | Unresolved_reference_target of Reference_id.t

type edge = {
  direction : edge_direction;
  kind : edge_kind;
  predicate : string;
  source : Region_address.t;
  target : edge_target;
  reference : Reference_id.t option;
  annotation : Annotation_id.t option;
  occurrence_range : Text_range.t option;
  source_resolution : resolution;
  target_resolution : resolution;
}

type coverage = Coverage.t

type t = {
  observation : Workspace_path.t;
  query_region : Identifier.t option;
  region_scope : region_scope option;
  query_direction : query_direction;
  predicate : string option;
  limit : int;
  matches : edge list;
  diagnostics : Diagnostic.t list;
  result_status : result_status;
  coverage : coverage;
  truncated : bool;
}

type error = Usage of string | Internal of string

let ( let* ) = Result.bind

type build_error =
  | Query_error of error
  | Unstable_workspace

type snapshot_inputs = {
  observations : Observation.t list;
  sidecar_snapshots : Sidecar_snapshot.t list;
  regions : Region.t list;
  annotation_index : Annotation_index.t;
  reference_index : Reference_index.t;
  reference_uses : Reference_use.t list;
  relations : Relation.t list;
  endpoint_resolutions :
    (Region_address.t * Endpoint_resolution.t) list;
  diagnostics : Diagnostic.t list;
  coverage : coverage;
}

let observation (value : t) = value.observation
let query_region (value : t) = value.query_region
let region_scope (value : t) = value.region_scope
let query_direction (value : t) = value.query_direction
let predicate (value : t) = value.predicate
let limit (value : t) = value.limit
let matches (value : t) = value.matches
let diagnostics (value : t) = value.diagnostics
let result_status (value : t) = value.result_status
let coverage (value : t) = value.coverage
let truncated (value : t) = value.truncated
let direction (value : edge) = value.direction
let kind (value : edge) = value.kind
let edge_predicate (value : edge) = value.predicate
let source (value : edge) = value.source
let target (value : edge) = value.target
let reference (value : edge) = value.reference
let annotation (value : edge) = value.annotation
let occurrence_range (value : edge) = value.occurrence_range
let source_resolution (value : edge) = value.source_resolution
let target_resolution (value : edge) = value.target_resolution

let find_observation observations id =
  List.find_opt (fun observation -> Observation_id.equal id (Observation.id observation))
    observations

let terminal_error result =
  match Command_result.termination result with
  | Command_result.Completed -> None
  | Command_result.Usage_failure message -> Some (Usage message)
  | Command_result.Internal_failure _ ->
      Some (Internal "workspace observation failed")

let same_representation left right =
  match Observation.representation left, Observation.representation right with
  | Observation.Bytes left, Observation.Bytes right -> String.equal left right
  | ( Observation.Structured { schema = left_schema; value = left_value },
      Observation.Structured { schema = right_schema; value = right_value } ) ->
      String.equal left_schema right_schema
      && Normalized_value.equal left_value right_value
  | Observation.Bytes _, Observation.Structured _
  | Observation.Structured _, Observation.Bytes _ ->
      false

let same_observation left right =
  Observation_id.equal (Observation.id left) (Observation.id right)
  && Observation.compare_origin (Observation.origin left) (Observation.origin right) = 0
  && Observation_identity.equal
       (Observation.identity left)
       (Observation.identity right)
  && Option.equal Content_identity.equal
       (Observation.content_identity left)
       (Observation.content_identity right)
  && same_representation left right

let sort_observations observations =
  List.sort
    (fun left right -> Observation_id.compare (Observation.id left) (Observation.id right))
    observations

let validate_unique_observation_ids observations =
  let rec loop = function
    | left :: (right :: _ as rest) ->
        if Observation_id.equal (Observation.id left) (Observation.id right) then
          Error
            (Query_error
               (Internal
                  "Resource Observers returned duplicate ObservationId values"))
        else loop rest
    | [] | [ _ ] -> Ok ()
  in
  observations |> sort_observations |> loop

let same_inventory left right =
  let left = sort_observations left in
  let right = sort_observations right in
  List.length left = List.length right
  && List.for_all2 same_observation left right

let same_sidecar_inventory left right =
  let sort = List.sort Sidecar_snapshot.compare in
  let left = sort left in
  let right = sort right in
  List.length left = List.length right
  && List.for_all2
       (fun left right -> Sidecar_snapshot.compare left right = 0)
       left right

let same_diagnostics left right =
  let sort = List.sort Diagnostic.compare in
  let left = sort left in
  let right = sort right in
  List.length left = List.length right
  && List.for_all2 (fun left right -> Diagnostic.compare left right = 0) left right

let same_scan_inventory left right =
  same_inventory (Command_result.observations left)
    (Command_result.observations right)
  && same_sidecar_inventory (Command_result.sidecar_snapshots left)
       (Command_result.sidecar_snapshots right)
  && Coverage.equal (Command_result.coverage left)
       (Command_result.coverage right)
  && same_diagnostics (Command_result.diagnostics left)
       (Command_result.diagnostics right)

let select_interpreter registry observation =
  Interpreter_dispatcher.select registry observation
  |> Result.map_error (fun message -> Query_error (Usage message))

let existing_inspection = function
  | Ok inspection -> Ok inspection
  | Error Workspace_inspect.Observation_changed -> Error Unstable_workspace
  | Error (Workspace_inspect.Invalid_observation message) ->
      Error (Query_error (Internal message))

let inspect_fixed ~registry ~observation ~sidecar_snapshots =
  Workspace_inspect.inspect_fixed_observation_with_registry ~observation
    ~sidecar_snapshots ~base_diagnostics:[] ~registry
  |> existing_inspection

let scan_workspace ~registry ~workspace =
  Workspace_scan.scan_with_classifier ~workspace
    ~classify:(Interpreter_dispatcher.classify_path registry)

let origin_of_address address = Some (Region_address.origin address)

let origin_of_region_ref = function
  | Region_ref.Address address -> origin_of_address address
  | Region_ref.Resolved _ -> None

let demanded_origins ~sidecar_scopes annotation_index reference_index
    reference_uses =
  let from_definitions =
    Reference_index.consistent_values reference_index
    |> List.map (fun reference ->
           Reference.target_origin (Reference.target reference))
  in
  let from_annotations =
    Annotation_index.consistent_values annotation_index
    |> List.concat_map (fun annotation ->
           let subject = origin_of_region_ref (Annotation.subject annotation) in
           let object_ =
             match Annotation.object_ annotation with
             | Annotation.Region_object region ->
                 origin_of_region_ref region
             | Annotation.Reference_object _ | Annotation.Literal _ -> None
           in
           Option.to_list subject @ Option.to_list object_)
  in
  let from_direct_uses =
    reference_uses
    |> List.filter_map (fun use ->
           match Reference_use.target use with
           | Reference_use.Named _ -> None
           | Reference_use.Direct address -> origin_of_address address)
  in
  sidecar_scopes @ from_definitions @ from_annotations @ from_direct_uses
  |> List.sort_uniq Origin.compare

let decode_sidecar_contents snapshots =
  List.filter_map
    (fun snapshot ->
      match Sidecar_v2.decode snapshot with
      | Ok contents -> Some contents
      | Error _ -> None)
    snapshots

let observation_has_origin observations origin =
  List.exists
    (fun observation -> Origin.equal origin (Observation.origin observation))
    observations

let orphan_sidecar_contents observations contents =
  List.filter
    (fun contents ->
      not
        (observation_has_origin observations (Sidecar_contents.scope contents)))
    contents

let workspace_observation_id path =
  Observation_id.make
    ("observation:" ^ Workspace_path.to_canonical_string path)

let diagnostic_has_observation diagnostics observation =
  List.exists
    (fun diagnostic ->
      match Diagnostic.location diagnostic with
      | Some { observation = Some candidate; _ } ->
          Observation_id.equal observation candidate
      | Some { observation = None; _ } | None -> false)
    diagnostics

let unobserved_origin_gaps ~scan_diagnostics observations origins =
  origins
  |> List.filter (fun origin -> not (observation_has_origin observations origin))
  |> List.fold_left
       (fun result origin ->
         let* primary_resources, unsupported, failed, diagnostics = result in
         match origin with
         | Origin.Extension _ ->
             Ok (primary_resources, unsupported, failed, diagnostics)
         | Origin.Workspace path ->
             let* observation =
               workspace_observation_id path
               |> Result.map_error (fun message -> Query_error (Internal message))
             in
             if diagnostic_has_observation scan_diagnostics observation then
               Ok (primary_resources, unsupported, failed, diagnostics)
             else
               let message =
                 "Workspace Origin is not available for observation: "
                 ^ Workspace_path.to_canonical_string path
               in
               let* diagnostic =
                 Diagnostic.make ~code:Diagnostic.Observation_failure ~message
                   ~location:
                     {
                       Diagnostic.observation = Some observation;
                       region = None;
                       annotation = None;
                       range = None;
                     }
                   ()
                 |> Result.map_error (fun message ->
                        Query_error (Internal message))
               in
               Ok
                 ( primary_resources + 1,
                   unsupported,
                   failed + 1,
                   diagnostic :: diagnostics )
         | Origin.Git _ | Origin.Web _ | Origin.Generated _
         | Origin.External _ ->
             let message =
               "Origin has no available Resource Observer: "
               ^ Agent_format.origin origin
             in
             let* diagnostic =
               Diagnostic.make ~code:Diagnostic.Observation_failure ~message ()
               |> Result.map_error (fun message -> Query_error (Internal message))
             in
             Ok
               ( primary_resources + 1,
                 unsupported + 1,
                 failed,
                 diagnostic :: diagnostics ))
       (Ok (0, 0, 0, []))

let observer_diagnostic ?failure message =
  let code =
    match failure with
    | Some _ -> Diagnostic.Extension_failure
    | None -> Diagnostic.Unresolved_ref
  in
  Diagnostic.make ~code ~message ?extension_failure:failure ()

let observe_extension_origins registry origins =
  List.fold_left
    (fun result origin ->
      let* observations, diagnostics, unsupported, failed = result in
      match Resource_observer_runner.observe registry origin with
      | Error message -> Error (Query_error (Usage message))
      | Ok Resource_observer_runner.Unsupported ->
          let* diagnostic =
            observer_diagnostic
              "Extension Origin has no installed Resource Observer"
            |> Result.map_error (fun message ->
                   Query_error (Internal message))
          in
          Ok
            ( observations,
              diagnostic :: diagnostics,
              unsupported + 1,
              failed )
      | Ok (Resource_observer_runner.Failure { failure; _ }) ->
          let* diagnostic =
            observer_diagnostic ~failure (Extension_failure.message failure)
            |> Result.map_error (fun message ->
                   Query_error (Internal message))
          in
          Ok
            ( observations,
              diagnostic :: diagnostics,
              unsupported,
              failed + 1 )
      | Ok (Resource_observer_runner.Observed { observation; _ }) ->
          Ok
            ( observation :: observations,
              diagnostics,
              unsupported,
              failed ))
    (Ok ([], [], 0, 0)) origins
  |> Result.map (fun (observations, diagnostics, unsupported, failed) ->
         ( sort_observations observations,
           List.sort Diagnostic.compare diagnostics,
           unsupported,
           failed ))

let diagnostic_exists diagnostics code message =
  List.exists
    (fun diagnostic ->
      Diagnostic.code diagnostic = code
      && String.equal (Diagnostic.message diagnostic) message)
    diagnostics

let index_diagnostics ~existing annotation_index reference_index =
  let candidates =
    let annotation_diagnostics =
      Annotation_index.entries annotation_index
      |> List.filter_map (fun (_id, entry) ->
             match entry with
             | Annotation_index.Conflict { occurrences } ->
                 let annotation =
                   Nonempty.head occurrences
                   |> Annotation_occurrence.annotation
                 in
                 let local =
                   Annotation.id annotation |> Annotation_id.local
                   |> Identifier.to_string
                 in
                 Some
                   ( Diagnostic.Divergent,
                     "annotation " ^ local ^ " has divergent occurrences" )
             | Annotation_index.Consistent { value = annotation; _ } -> (
                 match Annotation.object_ annotation with
                 | Annotation.Reference_object id
                   when Option.is_none
                          (Reference_index.find id reference_index) ->
                     let local =
                       Annotation.id annotation |> Annotation_id.local
                       |> Identifier.to_string
                     in
                     Some
                       ( Diagnostic.Unresolved_ref,
                         "annotation " ^ local
                         ^ " refers to an undefined reference" )
                 | Annotation.Reference_object _
                 | Annotation.Region_object _
                 | Annotation.Literal _ ->
                     None))
    in
    let reference_diagnostics =
      Reference_index.entries reference_index
      |> List.filter_map (fun (_id, entry) ->
             match entry with
             | Reference_index.Conflict { occurrences } ->
                 let reference =
                   Nonempty.head occurrences
                   |> Reference_definition_occurrence.reference
                 in
                 let local =
                   Reference.id reference |> Reference_id.local
                   |> Identifier.to_string
                 in
                 Some
                   ( Diagnostic.Divergent,
                     "reference " ^ local ^ " has divergent definitions" )
             | Reference_index.Consistent _ -> None)
    in
    annotation_diagnostics @ reference_diagnostics
  in
  candidates
  |> List.sort_uniq Stdlib.compare
  |> List.filter (fun (code, message) ->
         not (diagnostic_exists existing code message))
  |> List.fold_left
       (fun result (code, message) ->
         let* diagnostics = result in
         let* diagnostic =
           Diagnostic.make ~code ~message ()
           |> Result.map_error (fun message -> Query_error (Internal message))
         in
         Ok (diagnostic :: diagnostics))
       (Ok [])
  |> Result.map List.rev

let has_undefined_annotation_reference annotation_index reference_index =
  Annotation_index.consistent_values annotation_index
  |> List.exists (fun annotation ->
         match Annotation.object_ annotation with
         | Annotation.Reference_object id ->
             Option.is_none (Reference_index.find id reference_index)
         | Annotation.Region_object _ | Annotation.Literal _ -> false)

let addresses_of_region_ref = function
  | Region_ref.Address address -> [ address ]
  | Region_ref.Resolved _ -> []

let demanded_addresses annotation_index reference_index reference_uses =
  let references =
    Reference_index.consistent_values reference_index
    |> List.map Reference.target
  in
  let annotations =
    Annotation_index.consistent_values annotation_index
    |> List.concat_map (fun annotation ->
           let subject = addresses_of_region_ref (Annotation.subject annotation) in
           let object_ =
             match Annotation.object_ annotation with
             | Annotation.Region_object region -> addresses_of_region_ref region
             | Annotation.Reference_object _ | Annotation.Literal _ -> []
           in
           subject @ object_)
  in
  let direct_uses =
    reference_uses
    |> List.filter_map (fun use ->
           match Reference_use.target use with
           | Reference_use.Direct address -> Some address
           | Reference_use.Named _ -> None)
  in
  references @ annotations @ direct_uses
  |> List.sort_uniq Region_address.compare

let same_region left right =
  Stdlib.compare (Normal.Region.normalize left) (Normal.Region.normalize right)
  = 0

let merge_regions existing resolved =
  let sorted =
    List.rev_append resolved existing
    |> List.sort (fun left right -> Region_id.compare (Region.id left) (Region.id right))
  in
  let rec loop acc = function
    | left :: right :: rest
      when Region_id.equal (Region.id left) (Region.id right) ->
        if same_region left right then loop acc (left :: rest)
        else
          Error
            (Query_error
               (Internal
                  "Region resolution conflicts with an interpreted RegionId"))
    | value :: rest -> loop (value :: acc) rest
    | [] -> Ok (List.rev acc)
  in
  loop [] sorted

let endpoint_resolution_without_observation address =
  match Region_address.origin address with
  | Origin.Workspace _ | Origin.Extension _ -> Endpoint_resolution.Unresolved
  | Origin.Git _ | Origin.Web _ | Origin.Generated _ | Origin.External _ ->
      Endpoint_resolution.Not_checked

let resolution_failure_diagnostic observation failure =
  Diagnostic.make ~code:Diagnostic.Extension_failure
    ~message:(Extension_failure.message failure)
    ~extension_failure:failure
    ~location:
      {
        Diagnostic.observation = Some (Observation.id observation);
        region = None;
        annotation = None;
        range = None;
      }
    ()

let resolve_demanded_addresses ~registry ~observations ~regions addresses =
  List.fold_left
    (fun result address ->
      let* resolved_regions, resolutions, diagnostics, failed = result in
      match
        List.find_opt
          (fun observation ->
            Origin.equal (Observation.origin observation)
              (Region_address.origin address))
          observations
      with
      | None ->
          Ok
            ( resolved_regions,
              (address, endpoint_resolution_without_observation address)
              :: resolutions,
              diagnostics,
              failed )
      | Some observation ->
          let* outcome =
            Region_address_resolver.resolve ~registry ~observation
              ~existing_regions:regions address
            |> Result.map_error (fun message -> Query_error (Usage message))
          in
          let resolved_regions =
            match Region_address_resolver.region outcome with
            | Some region -> region :: resolved_regions
            | None -> resolved_regions
          in
          let* diagnostics, failed =
            match Region_address_resolver.extension_failure outcome with
            | None -> Ok (diagnostics, failed)
            | Some failure ->
                let* diagnostic =
                  resolution_failure_diagnostic observation failure
                  |> Result.map_error (fun message ->
                         Query_error (Internal message))
                in
                Ok (diagnostic :: diagnostics, failed + 1)
          in
          Ok
            ( resolved_regions,
              (address, Region_address_resolver.resolution outcome)
              :: resolutions,
              diagnostics,
              failed ))
    (Ok ([], [], [], 0)) addresses
  |> fun result ->
  Result.bind result (fun (resolved, resolutions, diagnostics, failed) ->
         let* regions = merge_regions regions resolved in
         Ok
           ( regions,
             List.rev resolutions,
             List.rev diagnostics,
             failed ))

let build_once ~registry ~workspace =
  let scan = scan_workspace ~registry ~workspace in
  match terminal_error scan with
  | Some error -> Error (Query_error error)
  | None ->
      let scanned = Command_result.observations scan |> sort_observations in
      let sidecar_snapshots = Command_result.sidecar_snapshots scan in
      let sidecar_contents = decode_sidecar_contents sidecar_snapshots in
      let sidecar_scopes =
        List.map Sidecar_contents.scope sidecar_contents
        |> List.sort_uniq Origin.compare
      in
      let rec interpret regions reference_definitions annotation_occurrences
          reference_uses diagnostics interpreted unsupported failed
          external_observations external_origins external_diagnostics
          external_unsupported external_failed = function
        | [] ->
            let all_observations =
              sort_observations
                (List.rev_append external_observations scanned)
            in
            let* () = validate_unique_observation_ids all_observations in
            let orphan_sidecars =
              orphan_sidecar_contents all_observations sidecar_contents
            in
            let final_annotation_occurrences =
              List.rev annotation_occurrences
              @ List.concat_map Sidecar_contents.annotations orphan_sidecars
            in
            let final_reference_definitions =
              List.rev reference_definitions
              @ List.concat_map Sidecar_contents.reference_definitions
                  orphan_sidecars
            in
            let final_reference_uses = List.rev reference_uses in
            let annotation_index =
              Annotation_index.make final_annotation_occurrences
            in
            let reference_index =
              Reference_index.make final_reference_definitions
            in
            let relations =
              Annotation_index.entries annotation_index
              |> List.filter_map (fun (_, entry) ->
                     Relation.of_index_entry ~reference_index entry)
            in
            let* index_diagnostics =
              index_diagnostics ~existing:diagnostics annotation_index
                reference_index
            in
            let diagnostics =
              List.rev_append index_diagnostics diagnostics
            in
            let discovered_origins =
              demanded_origins ~sidecar_scopes annotation_index reference_index
                final_reference_uses
            in
            let new_origins =
              List.filter
                (fun origin ->
                  match origin with
                  | Origin.Extension _ ->
                      not
                        (List.exists (Origin.equal origin) external_origins)
                  | Origin.Workspace _ | Origin.Git _ | Origin.Web _
                  | Origin.Generated _ | Origin.External _ ->
                      false)
                discovered_origins
            in
            if new_origins <> [] then
              let* new_observations, new_diagnostics, new_unsupported,
                   new_failed =
                observe_extension_origins registry new_origins
              in
              interpret regions reference_definitions annotation_occurrences
                reference_uses diagnostics interpreted
                (unsupported + new_unsupported)
                (failed + new_failed)
                (List.rev_append new_observations external_observations)
                (List.rev_append new_origins external_origins
                |> List.sort_uniq Origin.compare)
                (List.rev_append new_diagnostics external_diagnostics)
                (external_unsupported + new_unsupported)
                (external_failed + new_failed) new_observations
            else
              let scan_coverage = Command_result.coverage scan in
              let metadata_failed = Coverage.metadata_failed scan_coverage in
              let* demanded_primary_resources, demanded_unsupported,
                   demanded_failed, demanded_diagnostics =
                unobserved_origin_gaps
                  ~scan_diagnostics:(Command_result.diagnostics scan)
                  all_observations discovered_origins
              in
              let unsupported = unsupported + demanded_unsupported in
              let failed = failed + demanded_failed in
              let addresses =
                demanded_addresses annotation_index reference_index
                  final_reference_uses
              in
              let* final_regions, endpoint_resolutions,
                   resolution_diagnostics, resolution_failed =
                resolve_demanded_addresses ~registry
                  ~observations:all_observations ~regions:(List.rev regions)
                  addresses
              in
              let complete =
                unsupported = 0 && failed = 0 && metadata_failed = 0
                && resolution_failed = 0
                && Annotation_index.conflicts annotation_index = []
                && Reference_index.conflicts reference_index = []
                && not
                     (has_undefined_annotation_reference annotation_index
                        reference_index)
              in
              let* coverage =
                Coverage.make
                  ~primary_resources:
                    (Coverage.primary_resources scan_coverage
                    + List.length external_origins
                    + demanded_primary_resources)
                  ~observed:
                    (Coverage.observed scan_coverage
                    + List.length external_observations)
                  ~interpreted ~unsupported ~failed
                  ~metadata_discovered:
                    (Coverage.metadata_discovered scan_coverage)
                  ~metadata_decoded:(Coverage.metadata_decoded scan_coverage)
                  ~metadata_failed ~complete
                |> Result.map_error (fun message ->
                       Query_error (Internal message))
              in
              let final_scan = scan_workspace ~registry ~workspace in
              (match terminal_error final_scan with
              | Some error -> Error (Query_error error)
              | None ->
                  if not (same_scan_inventory scan final_scan) then
                    Error Unstable_workspace
                  else
                    let* final_external_observations,
                         final_external_diagnostics,
                         final_external_unsupported, final_external_failed =
                      observe_extension_origins registry external_origins
                    in
                    if
                      not
                        (same_inventory external_observations
                           final_external_observations)
                      || not
                           (same_diagnostics external_diagnostics
                              final_external_diagnostics)
                      || external_unsupported <> final_external_unsupported
                      || external_failed <> final_external_failed
                    then Error Unstable_workspace
                    else
                      Ok
                        {
                          observations = all_observations;
                          sidecar_snapshots;
                          regions = final_regions;
                          annotation_index;
                          reference_index;
                          reference_uses = final_reference_uses;
                          relations;
                          endpoint_resolutions;
                          diagnostics =
                            List.rev_append (Command_result.diagnostics scan)
                              (List.rev_append demanded_diagnostics
                                 (List.rev_append external_diagnostics
                                    (List.rev_append resolution_diagnostics
                                       diagnostics)))
                            |> List.sort_uniq Diagnostic.compare;
                          coverage;
                        })
        | scanned_observation :: rest ->
            let* selected = select_interpreter registry scanned_observation in
            let unsupported =
              match selected with
              | None -> unsupported + 1
              | Some _ -> unsupported
            in
            let* inspection =
              inspect_fixed ~registry ~observation:scanned_observation
                ~sidecar_snapshots
            in
            let result = inspection.result in
            (match terminal_error result with
            | Some (Usage message) ->
                Error
                  (Query_error
                     (Internal
                        ("workspace observation could not be inspected: "
                       ^ message)))
            | Some (Internal message) -> Error (Query_error (Internal message))
            | None ->
                let result_diagnostics = Command_result.diagnostics result in
                let has_error =
                  List.exists
                    (fun diagnostic ->
                      Diagnostic.effective_severity diagnostic = Diagnostic.Error)
                    result_diagnostics
                in
                interpret
                  (List.rev_append (Command_result.regions result) regions)
                  (List.rev_append
                     (Command_result.reference_definitions result)
                     reference_definitions)
                  (List.rev_append
                     (Command_result.annotation_occurrences result)
                     annotation_occurrences)
                  (List.rev_append inspection.reference_uses reference_uses)
                  (List.rev_append result_diagnostics diagnostics)
                  (interpreted
                  + if Option.is_some inspection.interpretation then 1 else 0)
                  unsupported (failed + if has_error then 1 else 0)
                  external_observations external_origins external_diagnostics
                  external_unsupported external_failed rest)
      in
      interpret [] [] [] [] [] 0 0 0 [] [] [] 0 0 scanned

let build_inputs ~workspace =
  match build_once ~registry:Registry_snapshot.empty ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match build_once ~registry:Registry_snapshot.empty ~workspace with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let build_inputs_with_registry ~workspace ~registry =
  match build_once ~registry ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match
        build_once ~registry ~workspace
      with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let origin_of_observation_id snapshot id =
  match find_observation snapshot.observations id with
  | Some observation -> Ok (Observation.origin observation)
  | None -> Error (Internal "graph endpoint observation is not in the workspace")

let address_of_region_id snapshot id =
  match
    List.find_opt (fun region -> Region_id.equal id (Region.id region))
      snapshot.regions
  with
  | None -> Error (Internal "graph relation region is not in the observation")
  | Some region ->
      let* origin = origin_of_observation_id snapshot (Region_id.observation id) in
      (match Region.interpreter_identity region with
      | None ->
          if Selector.compare (Region.selector region) Selector.Whole_observation = 0
          then
            Region_address.make ~origin
              ~selector:Selector.Whole_observation ()
          else Error "partial Region has no Interpreter identity"
      | Some interpreter ->
          let selector = Selector.Region_id (Region_id.local id) in
          Region_address.make ~origin ~selector
            ~interpreter:(Interpreter.name interpreter)
            ~interpreter_version:(Interpreter.version interpreter) ())
      |> Result.map_error (fun message -> Internal message)

let address_of_region_ref snapshot = function
  | Region_ref.Resolved id -> address_of_region_id snapshot id
  | Region_ref.Address address -> Ok address

let source_of_occurrence snapshot occurrence =
  match Reference_use.source_region occurrence with
  | Reference_use.Region id -> address_of_region_id snapshot id
  | Reference_use.Whole_observation ->
      let* origin =
        origin_of_observation_id snapshot
          (Reference_use.source_observation occurrence)
      in
      Region_address.make ~origin:origin ~selector:Selector.Whole_observation ()
      |> Result.map_error (fun message -> Internal message)

let find_reference snapshot id =
  match Reference_index.find id snapshot.reference_index with
  | Some (Reference_index.Consistent { value; _ }) -> Some value
  | Some (Reference_index.Conflict _) | None -> None

let find_observation_by_origin snapshot origin =
  List.find_opt
    (fun observation ->
      Observation.compare_origin origin (Observation.origin observation) = 0)
    snapshot.observations

let region_matches_address observation address region =
  Observation_id.equal (Observation.id observation) (Region.observation region)
  && Selector.compare (Region.selector region)
       (Region_address.selector address)
     = 0
  &&
  match Region_address.interpreter_identity address with
  | None -> true
  | Some expected -> (
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal expected actual
      | None -> false)

let address_resolution snapshot address =
  match
    List.find_opt
      (fun (candidate, _) -> Region_address.compare candidate address = 0)
      snapshot.endpoint_resolutions
  with
  | Some (_, resolution) -> resolution
  | None -> (
  match Region_address.origin address with
  | (Origin.Workspace _ | Origin.Extension _) as origin -> (
      match find_observation_by_origin snapshot origin with
      | None -> Unresolved
      | Some observation -> (
      match Region_address.selector address with
      | Selector.Whole_observation -> Resolved
      | Selector.Region_id local ->
          if
            List.exists
              (fun region ->
                Observation_id.equal (Observation.id observation)
                  (Region.observation region)
                && Identifier.equal local (Region.id region |> Region_id.local)
                &&
                match Region_address.interpreter_identity address with
                | None -> true
                | Some expected -> (
                    match Region.interpreter_identity region with
                    | Some actual -> Interpreter.equal expected actual
                    | None -> false))
              snapshot.regions
          then Resolved
          else Unresolved
      | Selector.Text_range range -> (
          match Observation.bytes observation with
          | Some content when Text_range.end_ range <= String.length content ->
              Resolved
          | Some _ -> Invalid_selector
          | None -> Unreadable)
      | Selector.Row_filter filter -> (
          match
            ( Region_address.interpreter_identity address,
              Observation.bytes observation )
          with
          | Some interpreter, Some content
            when String.equal (Interpreter.name interpreter) "jsonl"
                 && String.equal (Interpreter.version interpreter) "1" -> (
              match Jsonl_interpreter.select filter content with
              | Ok (Jsonl_interpreter.One _) -> Resolved
              | Ok Jsonl_interpreter.No_match -> Unresolved
              | Ok Jsonl_interpreter.Ambiguous | Error _ -> Invalid_selector)
          | Some _, Some _ -> Invalid_selector
          | _, None -> Unreadable
          | None, Some _ -> Invalid_selector)
      | Selector.Extension _ ->
          if
            List.exists (region_matches_address observation address)
              snapshot.regions
          then Resolved
          else Unresolved))
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _ ->
      Not_checked)

let reference_resolution snapshot reference =
  address_resolution snapshot (Reference.target reference)

let direct_resolution = address_resolution

let target_of_occurrence snapshot occurrence =
  match Reference_use.target occurrence with
  | Reference_use.Direct address ->
      Ok (Address_target address, None, direct_resolution snapshot address)
  | Reference_use.Named id -> (
      match find_reference snapshot id with
      | None -> Ok (Unresolved_reference_target id, Some id, Unresolved)
      | Some reference ->
          Ok
            ( Address_target (Reference.target reference),
              Some id,
              reference_resolution snapshot reference ))

let reference_edge_of_occurrence snapshot occurrence =
  let* source = source_of_occurrence snapshot occurrence in
  let* target, _, target_resolution =
    target_of_occurrence snapshot occurrence
  in
  let target =
    match target with
    | Address_target address -> Reference_edge.Address address
    | Unresolved_reference_target reference ->
        Reference_edge.Unresolved_reference reference
  in
  Ok
    (Reference_edge.make ~source ~target
       ~source_resolution:(direct_resolution snapshot source)
       ~target_resolution ~use:occurrence)

let finalize_snapshot inputs =
  let* reference_edges =
    List.fold_left
      (fun result occurrence ->
        let* edges = result in
        let* edge = reference_edge_of_occurrence inputs occurrence in
        Ok (edge :: edges))
      (Ok []) inputs.reference_uses
  in
  Ok
    (Workspace_graph_snapshot.make ~observations:inputs.observations
       ~sidecar_snapshots:inputs.sidecar_snapshots ~regions:inputs.regions
       ~annotation_index:inputs.annotation_index
       ~reference_index:inputs.reference_index
       ~reference_uses:inputs.reference_uses ~relations:inputs.relations
       ~reference_edges:(List.rev reference_edges)
       ~endpoint_resolutions:inputs.endpoint_resolutions
       ~diagnostics:inputs.diagnostics ~coverage:inputs.coverage)

let inputs_of_snapshot snapshot =
  {
    observations = Workspace_graph_snapshot.observations snapshot;
    sidecar_snapshots = Workspace_graph_snapshot.sidecar_snapshots snapshot;
    regions = Workspace_graph_snapshot.regions snapshot;
    annotation_index = Workspace_graph_snapshot.annotation_index snapshot;
    reference_index = Workspace_graph_snapshot.reference_index snapshot;
    reference_uses = Workspace_graph_snapshot.reference_uses snapshot;
    relations = Workspace_graph_snapshot.relations snapshot;
    endpoint_resolutions =
      Workspace_graph_snapshot.endpoint_resolutions snapshot;
    diagnostics = Workspace_graph_snapshot.diagnostics snapshot;
    coverage = Workspace_graph_snapshot.coverage snapshot;
  }

let resolve_address snapshot address =
  address_resolution (inputs_of_snapshot snapshot) address

let target_observation snapshot address =
  match resolve_address snapshot address with
  | Resolved ->
      find_observation_by_origin
        (inputs_of_snapshot snapshot)
        (Region_address.origin address)
  | Unresolved | Invalid_selector | Unreadable | Not_checked -> None

let snapshot_result = function
  | Ok inputs -> finalize_snapshot inputs
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace ->
      Error (Internal "workspace changed during graph observation")

let build_snapshot ~workspace =
  build_inputs ~workspace |> snapshot_result

let build_snapshot_with_registry ~workspace ~registry =
  build_inputs_with_registry ~workspace ~registry |> snapshot_result

let build = build_inputs
let build_with_registry = build_inputs_with_registry

let endpoint_origin address = Region_address.origin address

type query_selection =
  | Selected_observation of Origin.t
  | Selected_region of {
      observation : Observation.t;
      region : Region.t;
      scope : region_scope;
      registry : Registry_snapshot.t;
    }

let address_accepts_region_interpreter address region =
  match Region_address.interpreter_identity address with
  | None -> true
  | Some expected -> (
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal expected actual
      | None -> false)

let select_unique_region ~missing ~ambiguous regions =
  match regions with
  | [ region ] -> Ok region
  | [] -> Error (Internal missing)
  | _ -> Error (Internal ambiguous)

let region_of_address snapshot observation address =
  match Region_address.selector address with
  | Selector.Whole_observation ->
      let id =
        Region_id.make ~observation:(Observation.id observation)
          ~local:"whole-observation"
      in
      Result.map
        (fun id ->
          Region.whole ~id
            ~observation_identity:(Observation.identity observation))
        id
      |> Result.map_error (fun message -> Internal message)
  | Selector.Region_id local -> (
      snapshot.regions
      |> List.filter (fun region ->
             Observation_id.equal (Region.observation region)
               (Observation.id observation)
             && Identifier.equal (Region.id region |> Region_id.local) local
             && address_accepts_region_interpreter address region)
      |> select_unique_region
           ~missing:"region endpoint is not present in the graph"
           ~ambiguous:
             "multiple Regions with the same exact identity are present in the graph")
  | selector -> (
      snapshot.regions
      |> List.filter (fun region ->
             Observation_id.equal (Region.observation region)
               (Observation.id observation)
             && Selector.compare (Region.selector region) selector = 0
             && address_accepts_region_interpreter address region)
      |> select_unique_region
           ~missing:
             "addressed region endpoint is not present in the interpreted graph"
           ~ambiguous:
             "multiple Regions match the same exact RegionAddress in the graph")

let endpoint_matches snapshot selection address =
  match selection with
  | Selected_observation selected ->
      Ok (Observation.compare_origin selected (endpoint_origin address) = 0)
  | Selected_region selected ->
      if
        Observation.compare_origin (Observation.origin selected.observation)
          (endpoint_origin address)
        <> 0
      then Ok false
      else
        let* endpoint =
          region_of_address snapshot selected.observation address
        in
        (match
           Region_extent_dispatcher.classify ~registry:selected.registry
             ~observation:selected.observation ~left:selected.region
             ~right:endpoint
         with
        | Error failure ->
            Error
              (Internal
                 (Printf.sprintf "region relation failed [%s]: %s"
                    (Extension_failure.code failure)
                    (Extension_failure.message failure)))
        | Ok relation ->
            Ok
              (match selected.scope, relation with
              | Exact, Region_extent_relation.Equal -> true
              | Contained,
                (Region_extent_relation.Equal | Region_extent_relation.Contains)
                ->
                  true
              | Exact, _ | Contained, _ -> false))

let classify_direction snapshot selection source target =
  let* source_matches = endpoint_matches snapshot selection source in
  let* target_matches =
    match target with
    | Address_target address -> endpoint_matches snapshot selection address
    | Unresolved_reference_target _ -> Ok false
  in
  match (source_matches, target_matches) with
  | true, true -> Ok (Some Internal_edge)
  | true, false -> Ok (Some Outgoing_edge)
  | false, true -> Ok (Some Incoming_edge)
  | false, false -> Ok None

let include_direction query edge =
  match (query, edge) with
  | Both, _ -> true
  | Incoming, (Incoming_edge | Internal_edge) -> true
  | Outgoing, (Outgoing_edge | Internal_edge) -> true
  | Incoming, Outgoing_edge | Outgoing, Incoming_edge -> false

let edge_of_reference_edge snapshot selection reference_edge =
  let source = Reference_edge.source reference_edge in
  let target =
    match Reference_edge.target reference_edge with
    | Reference_edge.Address address -> Address_target address
    | Reference_edge.Unresolved_reference reference ->
        Unresolved_reference_target reference
  in
  let* direction = classify_direction snapshot selection source target in
  match direction with
  | None -> Ok None
  | Some direction ->
      let use = Reference_edge.use reference_edge in
      let reference =
        match Reference_use.target use with
        | Reference_use.Named reference -> Some reference
        | Reference_use.Direct _ -> None
      in
      Ok
        (Some
           {
             direction;
             kind = Reference_use;
             predicate = "references";
             source;
             target;
             reference;
             annotation = None;
             occurrence_range = Some (Reference_use.source_range use);
             source_resolution = Reference_edge.source_resolution reference_edge;
             target_resolution = Reference_edge.target_resolution reference_edge;
           })

let target_of_relation snapshot relation =
  let* address = address_of_region_ref snapshot (Relation.object_ relation) in
  let annotation =
    Relation.evidence relation |> Nonempty.head
    |> Annotation_occurrence.annotation
  in
  let reference =
    match Annotation.object_ annotation with
    | Annotation.Reference_object id -> Some id
    | Annotation.Region_object _ | Annotation.Literal _ -> None
  in
  Ok (Address_target address, reference, direct_resolution snapshot address)

let edge_of_relation snapshot selection relation =
  let* source = address_of_region_ref snapshot (Relation.subject relation) in
  let* target, reference, resolution = target_of_relation snapshot relation in
  let* direction = classify_direction snapshot selection source target in
  match direction with
  | None -> Ok None
  | Some direction ->
      Ok
        (Some
           {
             direction;
             kind = Semantic_relation;
             predicate = Relation.predicate relation;
             source;
             target;
             reference;
             annotation = Some (Relation.id relation);
             occurrence_range = None;
             source_resolution = direct_resolution snapshot source;
             target_resolution = resolution;
           })

let direction_rank = function
  | Outgoing_edge -> 0
  | Incoming_edge -> 1
  | Internal_edge -> 2

let kind_rank = function Reference_use -> 0 | Semantic_relation -> 1

let compare_target left right =
  match left, right with
  | Address_target left, Address_target right -> Region_address.compare left right
  | Unresolved_reference_target left, Unresolved_reference_target right ->
      Reference_id.compare left right
  | Address_target _, Unresolved_reference_target _ -> -1
  | Unresolved_reference_target _, Address_target _ -> 1

let compare_optional compare left right = Option.compare compare left right

let compare_edge left right =
  match Int.compare (direction_rank left.direction) (direction_rank right.direction) with
  | 0 -> (
      match String.compare left.predicate right.predicate with
      | 0 -> (
          match Region_address.compare left.source right.source with
          | 0 -> (
              match compare_target left.target right.target with
              | 0 -> (
                  match Int.compare (kind_rank left.kind) (kind_rank right.kind) with
                  | 0 -> (
                      match
                        compare_optional Reference_id.compare left.reference
                          right.reference
                      with
                      | 0 ->
                          compare_optional Annotation_id.compare left.annotation
                            right.annotation
                      | other -> other)
                  | other -> other)
              | other -> other)
          | other -> other)
      | other -> other)
  | other -> other

let rec take count values =
  if count = 0 then []
  else
    match values with
    | [] -> []
    | value :: rest -> value :: take (count - 1) rest

let make_query_selection ~workspace:_ ~observation ~region ~scope ~registry
    snapshot =
  let selected_origin = Observation.workspace observation in
  match find_observation_by_origin snapshot selected_origin with
  | None -> Error (Usage "observation does not exist")
  | Some _ when region = None -> Ok (Selected_observation selected_origin)
  | Some selected_observation -> (
      let local = Option.get region in
      match
        List.find_opt
          (fun candidate ->
            Observation_id.equal (Region.observation candidate)
              (Observation.id selected_observation)
            && Identifier.equal (Region.id candidate |> Region_id.local) local)
          snapshot.regions
      with
      | None -> Error (Usage "selected region does not exist in the interpreted graph")
      | Some selected_region ->
          Ok
            (Selected_region
               {
                 observation = selected_observation;
                 region = selected_region;
                 scope = Option.value ~default:Contained scope;
                 registry;
               }))

let query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit snapshot =
  let* graph = finalize_snapshot snapshot in
  let* selection =
    make_query_selection ~workspace ~observation ~region ~scope ~registry snapshot
  in
    let* occurrences =
      List.fold_left
        (fun result occurrence ->
          let* edges = result in
          let* edge =
            edge_of_reference_edge snapshot selection occurrence
          in
          Ok (match edge with None -> edges | Some edge -> edge :: edges))
        (Ok []) (Workspace_graph_snapshot.reference_edges graph)
    in
    let* relations =
      List.fold_left
        (fun result relation ->
          let* edges = result in
          let* edge = edge_of_relation snapshot selection relation in
          Ok (match edge with None -> edges | Some edge -> edge :: edges))
        (Ok []) (Workspace_graph_snapshot.relations graph)
    in
    let all =
      List.rev_append occurrences relations
      |> List.filter (fun edge -> include_direction direction edge.direction)
      |> List.filter (fun edge ->
             match predicate with
             | None -> true
             | Some predicate -> String.equal predicate (edge : edge).predicate)
      |> List.sort compare_edge
    in
    let truncated = List.length all > limit in
    Ok
      {
        observation;
        query_region = region;
        region_scope = scope;
        query_direction = direction;
        predicate;
        limit;
        matches = take limit all;
        diagnostics = Workspace_graph_snapshot.diagnostics graph;
        result_status =
          (if Coverage.complete (Workspace_graph_snapshot.coverage graph) then
             Complete
           else Incomplete);
        coverage = Workspace_graph_snapshot.coverage graph;
        truncated;
      }

let finish_query ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit = function
  | Ok snapshot ->
      query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
        ~predicate ~limit snapshot
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace ->
      Error (Internal "workspace changed during graph observation")

let query ~workspace ~observation ~direction ~predicate ~limit =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build ~workspace
    |> finish_query ~workspace ~observation ~region:None ~scope:None
         ~registry:Registry_snapshot.empty ~direction ~predicate ~limit

let query_with_registry ~workspace ~observation ~direction ~predicate ~limit
    ~registry =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build_with_registry ~workspace ~registry
    |> finish_query ~workspace ~observation ~region:None ~scope:None ~registry
         ~direction ~predicate ~limit

let query_for_region_with_registry ~workspace ~observation ~region ~scope
    ~direction ~predicate ~limit ~registry =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build_with_registry ~workspace ~registry
    |> finish_query ~workspace ~observation ~region:(Some region)
         ~scope:(Some scope) ~registry ~direction ~predicate ~limit

let query_for_region ~workspace ~observation ~region ~scope ~direction
    ~predicate ~limit =
  query_for_region_with_registry ~workspace ~observation ~region ~scope
    ~direction ~predicate ~limit ~registry:Registry_snapshot.empty
