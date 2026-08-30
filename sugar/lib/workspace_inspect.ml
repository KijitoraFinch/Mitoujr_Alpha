let ( let* ) = Result.bind

type inspection = {
  result : Command_result.t;
  content : string option;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
}

let empty_inspection result =
  { result; content = None; occurrences = []; relations = [] }

let complete_inspection ~content ~occurrences ~annotations result =
  {
    result;
    content = Some content;
    occurrences;
    relations = List.filter_map Relation.of_annotation annotations;
  }

let command_result ?summary ?(diagnostics = []) ?(observations = [])
    ?(regions = []) ?(references = []) ?(annotations = [])
    ?(capabilities = []) ~termination () =
  match
    Command_result.make ~command:"inspect" ~termination
      ~effect:Command_result.No_change ~diagnostics ~observations ~regions
      ~references ~annotations ~capabilities ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"inspect"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let usage message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal ?location operation =
  let summary =
    [
      ("errorCode", Command_result.Text "filesystem-io");
      ("operation", Command_result.Text operation);
    ]
    @
    match location with
    | None -> []
    | Some path ->
        [
          ( "location",
            Command_result.Text (Workspace_path.to_canonical_string path) );
        ]
  in
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~summary ()

let observation_id path =
  Observation_id.make ("observation:" ^ Workspace_path.to_canonical_string path)

let observation observation_type path file =
  let* id = observation_id path in
  Ok
    (Observation.of_content ~id ~origin:(Observation.workspace path)
       ~observation_type
       ~content_identity:(Workspace_read.content_identity file))

let diagnostic ~observation_id ~code message =
  Diagnostic.make ~code ~message
    ~location:
      {
        Diagnostic.observation = Some observation_id;
        region = None;
        annotation = None;
        range = None;
      }
    ()

let sidecar_override_diagnostic sidecar_id
    (override : Sidecar_v1.override) =
  let kind =
    match override.kind with
    | Sidecar_v1.Reference_override -> "reference"
    | Sidecar_v1.Annotation_override -> "annotation"
  in
  diagnostic ~observation_id:sidecar_id ~code:Diagnostic.Authored_override
    (Printf.sprintf
       "authored %s %s overrides a different derived entry"
       kind override.local)

let diagnostic_result ~observations = function
  | Error _ -> internal "construct-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed ~observations
        ~diagnostics:[ diagnostic ]
        ~summary:
          [
            ("annotations", Command_result.Count 0);
            ("references", Command_result.Count 0);
            ("regions", Command_result.Count 0);
          ]
        ()

let extension_failure_result ?observation_id ~observations ~capabilities
    ~diagnostic_code failure =
  let location =
    Option.map
      (fun observation ->
        {
          Diagnostic.observation = Some observation;
          region = None;
          annotation = None;
          range = None;
        })
      observation_id
  in
  match
    Diagnostic.make ~code:diagnostic_code
      ~message:(Extension_failure.message failure) ?location
      ~extension_failure:failure ()
  with
  | Error _ -> internal "construct-extension-failure-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed ~observations
        ~capabilities ~diagnostics:[ diagnostic ]
        ~summary:
          [
            ("annotations", Command_result.Count 0);
            ("references", Command_result.Count 0);
            ("regions", Command_result.Count 0);
          ]
        ()

let runtime_extension_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let invalid_extension_result operation message =
  Extension_failure.make ~operation ~code:"invalid-result" ~message ()

let collect_results values =
  List.fold_right
    (fun value result ->
      let* value = value in
      let* values = result in
      Ok (value :: values))
    values (Ok [])

let read_primary ~workspace path =
  match Workspace_read.read ~workspace ~path with
  | Ok file -> Ok file
  | Error Workspace_read.Invalid_workspace ->
      Error (`Usage "workspace must be an existing directory")
  | Error Workspace_read.Missing_file ->
      Error (`Usage "observation does not exist")
  | Error (Workspace_read.Unsafe _) ->
      Error (`Usage "observation is outside the safe workspace read policy")
  | Error Workspace_read.Unstable_content -> Error (`Internal "read-stable-observation")
  | Error (Workspace_read.Filesystem_io operation) -> Error (`Internal operation)

let sidecar_path primary =
  let segments = Workspace_path.segments primary in
  match List.rev segments with
  | [] -> Error "workspace path has no segments"
  | basename :: reversed_parent ->
      let stem =
        match String.rindex_opt basename '.' with
        | Some index when index > 0 -> String.sub basename 0 index
        | _ -> basename
      in
      Workspace_path.of_segments
        (List.rev reversed_parent @ [ stem ^ ".annotations.yaml" ])

let is_markdown path =
  match List.rev (Workspace_path.segments path) with
  | [] -> false
  | basename :: _ ->
      Filename.check_suffix basename ".md"
      || Filename.check_suffix basename ".markdown"

let is_markdown_observation observation =
  Observation_type.equal
    (Observation.observation_type observation)
    Observation_type.markdown

let extension_associated_observation_type manifest path =
  let capability = Extension_manifest.capability manifest in
  match Extension_applicability.associate capability ~path with
  | Error _ as error -> error
  | Ok Extension_applicability.Not_associated ->
      Error "extension does not apply to the selected observation"
  | Ok (Extension_applicability.Associated observation_type) ->
      Ok observation_type

let require_interpreter_manifest manifest =
  let capability = Extension_manifest.capability manifest in
  match Capability.kind capability with
  | Capability.Interpreter -> Ok ()
  | _ -> Error "extension inspect requires an interpreter capability"

let binding_equal left right =
  match (left, right) with
  | Reference.Pinned, Reference.Pinned
  | Reference.Tracking, Reference.Tracking
  | Reference.Floating, Reference.Floating ->
      true
  | _ -> false

let provenance_is_authored provenance =
  match Provenance.detail provenance with
  | Some detail -> String.ends_with ~suffix:"#authored" detail
  | None -> false

let reference_is_authored reference =
  List.exists provenance_is_authored (Reference.provenance reference)

let merge_inline_references sidecar inline =
  let rec merge declared additions divergences = function
    | [] -> Ok (declared @ List.rev additions, List.rev divergences)
    | reference :: rest -> (
        match
          List.find_opt
            (fun value ->
              Reference_id.equal (Reference.id reference) (Reference.id value))
            declared
        with
        | Some selected ->
            let equivalent =
              Observation.compare_origin
                (Reference.target_origin (Reference.target selected))
                (Reference.target_origin (Reference.target reference))
              = 0
            in
            let merged, divergences =
              if equivalent then
                ( Reference.make ~id:(Reference.id selected)
                    ~target:(Reference.target selected)
                    ~binding:(Reference.binding selected)
                    ~expectations:(Reference.expectations selected)
                    ~provenance:
                      (Reference.provenance selected
                      @ Reference.provenance reference)
                    (),
                  divergences )
              else
                let chosen =
                  if reference_is_authored selected then selected else reference
                in
                ( Reference.make ~id:(Reference.id chosen)
                    ~target:(Reference.target chosen)
                    ~binding:(Reference.binding chosen)
                    ~expectations:(Reference.expectations chosen)
                    ~provenance:
                      (Reference.provenance selected
                      @ Reference.provenance reference)
                    (),
                  "inline and sidecar references with the same ID disagree"
                  :: divergences )
            in
            let declared =
              List.map
                (fun item ->
                  if Reference_id.equal (Reference.id item) (Reference.id merged)
                  then merged
                  else item)
                declared
            in
            merge declared additions divergences rest
        | None -> (
            match
              List.find_opt
                (fun existing ->
                  Reference_id.equal (Reference.id existing)
                    (Reference.id reference))
                additions
            with
            | None -> merge declared (reference :: additions) divergences rest
            | Some existing ->
                if
                  Reference.compare_target (Reference.target existing)
                    (Reference.target reference)
                  <> 0
                  || not
                       (binding_equal (Reference.binding existing)
                          (Reference.binding reference))
                then Error "inline reference ID has divergent targets"
                else
                  let combined =
                    Reference.make ~id:(Reference.id existing)
                      ~target:(Reference.target existing)
                      ~binding:(Reference.binding existing)
                      ~expectations:(Reference.expectations existing)
                      ~provenance:
                        (Reference.provenance existing
                        @ Reference.provenance reference)
                      ()
                  in
                  merge declared
                    (combined
                    :: List.filter
                         (fun item ->
                           not
                             (Reference_id.equal (Reference.id item)
                                (Reference.id existing)))
                         additions)
                    divergences rest))
  in
  merge sidecar [] [] inline

let references_cover_annotations references annotations =
  let has_reference id =
    List.exists (fun value -> Reference_id.equal id (Reference.id value))
      references
  in
  List.for_all
    (fun annotation ->
      match Annotation.object_ annotation with
      | Annotation.Reference_object id -> has_reference id
      | Annotation.Region_object _ | Annotation.Literal _ -> true)
    annotations

let region_id_of_address address =
  match (Region_address.origin address, Region_address.selector address) with
  | Origin.Workspace path, Selector.Region_id local ->
      let* observation =
        Observation_id.make ("observation:" ^ Workspace_path.to_canonical_string path)
      in
      Region_id.make ~observation ~local:(Identifier.to_string local)
  | _ -> Error "annotation address is not a region-id selector"

let resolved_subject regions annotation =
  match Annotation.subject annotation with
  | Annotation.Region (Region_ref.Resolved id) -> Some id
  | Annotation.Region (Region_ref.Address address) -> (
      match region_id_of_address address with
      | Ok id when List.exists (fun region -> Region_id.equal id (Region.id region)) regions -> Some id
      | Ok _ | Error _ -> None)

let same_annotation_object left right =
  match (Annotation.object_ left, Annotation.object_ right) with
  | Annotation.Reference_object l, Annotation.Reference_object r -> Reference_id.equal l r
  | Annotation.Region_object l, Annotation.Region_object r -> Region_ref.compare l r = 0
  | Annotation.Literal l, Annotation.Literal r -> String.equal l r
  | _ -> false

let annotation_is_authored annotation =
  List.exists provenance_is_authored (Annotation.provenance annotation)

let merge_annotations regions inline sidecar =
  let rec merge remaining_inline merged divergences = function
    | [] ->
        Ok (List.rev_append merged remaining_inline, List.rev divergences)
    | declared :: rest -> (
        match
          List.find_opt
            (fun candidate ->
              Annotation_id.equal (Annotation.id declared)
                (Annotation.id candidate))
            remaining_inline
        with
        | None -> merge remaining_inline (declared :: merged) divergences rest
        | Some candidate ->
            let equivalent =
              String.equal (Annotation.predicate declared)
                (Annotation.predicate candidate)
              && same_annotation_object declared candidate
              &&
              match
                (resolved_subject regions declared, resolved_subject regions candidate)
              with
              | Some left, Some right -> Region_id.equal left right
              | _ -> false
            in
            if not equivalent then
              let selected =
                if annotation_is_authored declared then declared else candidate
              in
              let* selected =
                Annotation.make ~id:(Annotation.id selected)
                  ~subject:(Annotation.subject selected)
                  ~predicate:(Annotation.predicate selected)
                  ~object_:(Annotation.object_ selected)
                  ~provenance:
                    (Annotation.provenance declared
                    @ Annotation.provenance candidate)
                  ~materialization:
                    (Annotation.materialization declared
                    @ Annotation.materialization candidate)
              in
              let remaining_inline =
                List.filter
                  (fun item ->
                    not
                      (Annotation_id.equal (Annotation.id item)
                         (Annotation.id candidate)))
                  remaining_inline
              in
              merge remaining_inline (selected :: merged)
                ("inline and sidecar annotations with the same ID disagree"
                :: divergences)
                rest
            else
              let* subject =
                match resolved_subject regions candidate with
                | Some id -> Ok (Annotation.Region (Region_ref.Resolved id))
                | None -> Error "inline annotation subject does not resolve"
              in
              let* combined =
                Annotation.make ~id:(Annotation.id candidate) ~subject
                  ~predicate:(Annotation.predicate candidate)
                  ~object_:(Annotation.object_ candidate)
                  ~provenance:
                    (Annotation.provenance candidate
                    @ Annotation.provenance declared)
                  ~materialization:
                    (Annotation.materialization candidate
                    @ Annotation.materialization declared)
              in
              let remaining_inline =
                List.filter
                  (fun item ->
                    not
                      (Annotation_id.equal (Annotation.id item)
                         (Annotation.id candidate)))
                  remaining_inline
              in
              merge remaining_inline (combined :: merged) divergences rest)
  in
  merge inline [] [] sidecar

let inspect_supported ~workspace ~observation_path primary_file primary_observation =
  let primary_id = Observation.id primary_observation in
  let content = Workspace_read.content primary_file in
  match
    Markdown_inspect.inspect ~observation:primary_id ~path:observation_path
      content
  with
  | Error message ->
      empty_inspection
        (diagnostic_result ~observations:[ primary_observation ]
           (diagnostic ~observation_id:primary_id
              ~code:Diagnostic.Invalid_selector message))
  | Ok markdown -> (
      match sidecar_path observation_path with
      | Error _ -> empty_inspection (internal "construct-sidecar-path")
      | Ok sidecar_path -> (
      match Workspace_read.read ~workspace ~path:sidecar_path with
      | Error Workspace_read.Missing_file ->
          if
            not
              (references_cover_annotations markdown.references
                 markdown.annotations)
          then
            empty_inspection
              (diagnostic_result ~observations:[ primary_observation ]
                 (diagnostic ~observation_id:primary_id
                    ~code:Diagnostic.Invalid_selector
                    "inline annotation refers to an undeclared reference"))
          else
            let result =
              command_result ~termination:Command_result.Completed
                ~observations:[ primary_observation ] ~regions:markdown.regions
                ~references:markdown.references
                ~annotations:markdown.annotations
                ~summary:
                  [
                    ( "annotations",
                      Command_result.Count
                        (List.length markdown.annotations) );
                    ( "references",
                      Command_result.Count
                        (List.length markdown.references) );
                    ("regions", Command_result.Count (List.length markdown.regions));
                  ]
                ()
            in
            complete_inspection ~content ~occurrences:markdown.occurrences
              ~annotations:markdown.annotations result
      | Error Workspace_read.Invalid_workspace ->
          empty_inspection (usage "workspace must be an existing directory")
      | Error Workspace_read.Unstable_content ->
          empty_inspection
            (internal ~location:sidecar_path "read-stable-sidecar")
      | Error (Workspace_read.Filesystem_io operation) ->
          empty_inspection (internal ~location:sidecar_path operation)
      | Error (Workspace_read.Unsafe _) ->
          empty_inspection
            (diagnostic_result ~observations:[ primary_observation ]
               (diagnostic ~observation_id:primary_id
                  ~code:Diagnostic.Invalid_sidecar
                  "sidecar is outside the safe workspace read policy"))
      | Ok sidecar_file -> (
          match
            observation Observation_type.yaml sidecar_path sidecar_file
          with
          | Error _ ->
              empty_inspection (internal "construct-sidecar-observation")
          | Ok sidecar_observation ->
          let sidecar_id = Observation.id sidecar_observation in
          let observations = [ primary_observation; sidecar_observation ] in
          (match
             Sidecar_v1.decode ~primary_observation:primary_id
               ~sidecar_observation:sidecar_id ~sidecar_path
               (Workspace_read.content sidecar_file)
           with
          | Error message ->
              empty_inspection
                (diagnostic_result ~observations
                   (diagnostic ~observation_id:sidecar_id
                      ~code:Diagnostic.Invalid_sidecar message))
          | Ok sidecar -> (
              match
                sidecar.overrides
                |> List.map (sidecar_override_diagnostic sidecar_id)
                |> collect_results
              with
              | Error _ ->
                  empty_inspection (internal "construct-override-diagnostic")
              | Ok ownership_diagnostics ->
              match merge_inline_references sidecar.references markdown.references with
              | Error message ->
                  empty_inspection
                    (diagnostic_result ~observations
                       (diagnostic ~observation_id:primary_id
                          ~code:Diagnostic.Divergent message))
              | Ok (references, reference_divergence_messages) ->
                  (match
                     merge_annotations markdown.regions markdown.annotations
                       sidecar.annotations
                   with
                  | Error message ->
                    empty_inspection
                      (diagnostic_result ~observations
                         (diagnostic ~observation_id:primary_id
                            ~code:Diagnostic.Divergent message))
                  | Ok (annotations, divergence_messages) ->
                  (match
                     (reference_divergence_messages @ divergence_messages)
                     |> List.map (fun message ->
                            diagnostic ~observation_id:primary_id
                              ~code:Diagnostic.Divergent message)
                     |> collect_results
                   with
                  | Error _ ->
                      empty_inspection
                        (internal "construct-divergence-diagnostic")
                  | Ok divergence_diagnostics ->
                  let diagnostics =
                    ownership_diagnostics @ divergence_diagnostics
                  in
                  if not (references_cover_annotations references annotations) then
                    empty_inspection
                      (diagnostic_result ~observations
                         (diagnostic ~observation_id:sidecar_id
                            ~code:Diagnostic.Invalid_sidecar
                            "annotation refers to an undeclared reference"))
                  else
                    let result =
                      command_result ~termination:Command_result.Completed
                        ~observations ~regions:markdown.regions ~references
                        ~annotations
                        ~diagnostics
                        ~summary:
                          [
                            ( "annotations",
                              Command_result.Count
                                (List.length annotations) );
                            ( "references",
                              Command_result.Count
                                (List.length references) );
                            ( "regions",
                              Command_result.Count
                                (List.length markdown.regions) );
                          ]
                        ()
                    in
                    complete_inspection
                      ~content ~occurrences:markdown.occurrences ~annotations
                      result)))))))

let inspect_observation ~workspace ~observation:observation_path =
  match read_primary ~workspace observation_path with
  | Error (`Usage message) -> empty_inspection (usage message)
  | Error (`Internal operation) ->
      empty_inspection (internal ~location:observation_path operation)
  | Ok primary_file -> (
      let observation_type =
        Workspace_observation_type.classify observation_path
      in
      match observation observation_type observation_path primary_file with
      | Error _ -> empty_inspection (internal "construct-primary-observation")
      | Ok primary_observation ->
      if is_markdown observation_path then
        inspect_supported ~workspace ~observation_path primary_file
          primary_observation
      else
        empty_inspection
          (diagnostic_result ~observations:[ primary_observation ]
             (diagnostic ~observation_id:(Observation.id primary_observation)
                ~code:Diagnostic.Unsupported_observation
                "no standard interpreter supports this observation")))

type existing_observation_error =
  | Observation_changed
  | Invalid_observation of string

let read_existing_observation ~workspace observation =
  match Observation.origin observation with
  | Origin.Workspace path -> (
      match Observation.content_identity observation with
      | None ->
          Error
            (Invalid_observation
               "workspace observation must have a content identity")
      | Some expected -> (
          match read_primary ~workspace path with
          | Error (`Usage message) ->
              Ok (path, Error (empty_inspection (usage message)))
          | Error (`Internal operation) ->
              Ok
                ( path,
                  Error
                    (empty_inspection
                       (internal ~location:path operation)) )
          | Ok file ->
              if
                Content_identity.equal expected
                  (Workspace_read.content_identity file)
              then Ok (path, Ok file)
              else Error Observation_changed))
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _
  | Origin.Extension _ ->
      Error
        (Invalid_observation
           "workspace inspection requires a workspace observation origin")

let inspect_existing_observation ~workspace ~observation =
  match read_existing_observation ~workspace observation with
  | Error _ as error -> error
  | Ok (_, Error inspection) -> Ok inspection
  | Ok (path, Ok file) ->
      if is_markdown_observation observation then
        Ok
          (inspect_supported ~workspace ~observation_path:path file observation)
      else
        Ok
          (empty_inspection
             (diagnostic_result ~observations:[ observation ]
                (diagnostic ~observation_id:(Observation.id observation)
                   ~code:Diagnostic.Unsupported_observation
                   "no standard interpreter supports this observation")))

let interpret_extension_file ~primary_observation ~primary_file ~manifest
    ~session =
  let content = Workspace_read.content primary_file in
  let params =
    Extension_interpreter_protocol.interpret_params
      ~observation:primary_observation
  in
  match
    Extension_runtime.call_with_content session
      ~method_name:"monika.interpretObservation" ~params ~content
  with
  | Error failure ->
      empty_inspection
        (match
           runtime_extension_failure Extension_failure.Interpret_observation
             failure
         with
        | Error _ -> internal "construct-extension-runtime-failure"
        | Ok failure ->
            extension_failure_result
              ~observation_id:(Observation.id primary_observation)
              ~observations:[ primary_observation ]
              ~capabilities:[ Extension_manifest.capability manifest ]
              ~diagnostic_code:Diagnostic.Extension_failure failure)
  | Ok result -> (
      match
        Extension_interpreter_protocol.decode_interpret_result ~manifest
          ~primary_observation result
      with
      | Error message ->
          empty_inspection
            (match
               invalid_extension_result Extension_failure.Interpret_observation
                 message
             with
            | Error _ -> internal "construct-invalid-extension-result"
            | Ok failure ->
                extension_failure_result
                  ~observation_id:(Observation.id primary_observation)
                  ~observations:[ primary_observation ]
                  ~capabilities:[ Extension_manifest.capability manifest ]
                  ~diagnostic_code:Diagnostic.Extension_failure failure)
      | Ok
          (Extension_interpreter_protocol.Interpret_failure failure) ->
          let diagnostic_code =
            if
              String.equal (Extension_failure.code failure)
                "unsupported-observation"
            then Diagnostic.Unsupported_observation
            else Diagnostic.Extension_failure
          in
          empty_inspection
            (extension_failure_result
               ~observation_id:(Observation.id primary_observation)
               ~observations:[ primary_observation ]
               ~capabilities:[ Extension_manifest.capability manifest ]
               ~diagnostic_code failure)
      | Ok
          (Extension_interpreter_protocol.Interpretation interpretation) ->
          let regions = Interpretation.regions interpretation in
          let references = Interpretation.references interpretation in
          let annotations = Interpretation.annotations interpretation in
          let result =
            command_result ~termination:Command_result.Completed
              ~observations:[ primary_observation ] ~regions ~references
              ~annotations
              ~capabilities:[ Extension_manifest.capability manifest ]
              ~summary:
                [
                  ( "annotations",
                    Command_result.Count (List.length annotations) );
                  ( "references",
                    Command_result.Count (List.length references) );
                  ("regions", Command_result.Count (List.length regions));
                  ("runtimeChecked", Command_result.Flag true);
                ]
              ()
          in
          complete_inspection ~content ~occurrences:[] ~annotations result)

let inspect_existing_observation_with_extension_session ~workspace
    ~observation ~manifest ~session =
  let capability = Extension_manifest.capability manifest in
  match require_interpreter_manifest manifest with
  | Error message -> Error (Invalid_observation message)
  | Ok () -> (
      match Extension_applicability.accepts capability ~observation with
      | Error message -> Error (Invalid_observation message)
      | Ok false ->
          Error
            (Invalid_observation
               "extension does not accept the fixed observation")
      | Ok true -> (
          match read_existing_observation ~workspace observation with
          | Error _ as error -> error
          | Ok (_, Error inspection) -> Ok inspection
          | Ok (_, Ok file) ->
              Ok
                (interpret_extension_file ~primary_observation:observation
                   ~primary_file:file ~manifest ~session)))

let inspect_observation_with_extension_session ~workspace
    ~observation:observation_path ~manifest ~session =
  match
    ( require_interpreter_manifest manifest,
      extension_associated_observation_type manifest observation_path )
  with
  | Error message, _ | _, Error message -> empty_inspection (usage message)
  | Ok (), Ok observation_type -> (
      match read_primary ~workspace observation_path with
      | Error (`Usage message) -> empty_inspection (usage message)
      | Error (`Internal operation) ->
          empty_inspection (internal ~location:observation_path operation)
      | Ok primary_file -> (
          match observation observation_type observation_path primary_file with
          | Error _ ->
              empty_inspection (internal "construct-primary-observation")
          | Ok primary_observation ->
              interpret_extension_file ~primary_observation ~primary_file
                ~manifest ~session))

let inspect_with_extension_session ~workspace ~observation ~manifest ~session =
  (inspect_observation_with_extension_session ~workspace ~observation ~manifest
     ~session)
    .result

let inspect_with_extension ~workspace ~observation ~manifest ~executable
    ~arguments =
  match
    ( require_interpreter_manifest manifest,
      extension_associated_observation_type manifest observation )
  with
  | Error message, _ | _, Error message -> usage message
  | Ok (), Ok _ -> (
      match
        Extension_runtime.with_checked_session ~executable ~arguments
          ~limits:Extension_runtime.default_limits ~manifest (fun session ->
            Ok
              (inspect_with_extension_session ~workspace ~observation ~manifest
                 ~session))
      with
      | Ok result -> result
      | Error failure ->
          (match runtime_extension_failure Extension_failure.Session failure with
          | Error _ -> internal "construct-extension-session-failure"
          | Ok failure ->
              extension_failure_result ~observations:[]
                ~capabilities:[ Extension_manifest.capability manifest ]
                ~diagnostic_code:Diagnostic.Extension_failure failure))

let inspect_existing_observation_with_installed_extension ~workspace
    ~observation ~extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        inspect_existing_observation_with_extension_session ~workspace
          ~observation ~manifest ~session
        |> function
        | Ok inspection -> Ok (`Inspection inspection)
        | Error error -> Ok (`Existing_error error))
  with
  | Ok (`Inspection inspection) -> Ok inspection
  | Ok (`Existing_error error) -> Error error
  | Error runtime_failure ->
      let result =
        match runtime_extension_failure Extension_failure.Session runtime_failure with
        | Error _ -> internal "construct-extension-session-failure"
        | Ok failure ->
            extension_failure_result ~observations:[ observation ]
              ~capabilities:[ Installed_extension.capability extension ]
              ~diagnostic_code:Diagnostic.Extension_failure failure
      in
      Ok (empty_inspection result)

let inspect_with_registry ~workspace ~observation:observation_path ~registry =
  match Interpreter_dispatcher.classify_path registry observation_path with
  | Error message -> usage message
  | Ok observation_type -> (
      match read_primary ~workspace observation_path with
      | Error (`Usage message) -> usage message
      | Error (`Internal operation) -> internal ~location:observation_path operation
      | Ok primary_file -> (
          match observation observation_type observation_path primary_file with
          | Error _ -> internal "construct-primary-observation"
          | Ok primary_observation -> (
              match Interpreter_dispatcher.select registry primary_observation with
              | Error message -> usage message
              | Ok None ->
                  diagnostic_result ~observations:[ primary_observation ]
                    (diagnostic
                       ~observation_id:(Observation.id primary_observation)
                       ~code:Diagnostic.Unsupported_observation
                       "no installed interpreter supports this observation")
              | Ok (Some Interpreter_dispatcher.Built_in_markdown) ->
                  (inspect_supported ~workspace ~observation_path primary_file
                     primary_observation)
                    .result
              | Ok
                  (Some
                    (Interpreter_dispatcher.Built_in_jsonl
                    | Interpreter_dispatcher.Built_in_sidecar_v1)) ->
                  diagnostic_result ~observations:[ primary_observation ]
                    (diagnostic
                       ~observation_id:(Observation.id primary_observation)
                       ~code:Diagnostic.Unsupported_observation
                       "the selected built-in interpreter does not construct an inspection graph")
              | Ok (Some (Interpreter_dispatcher.Installed extension)) ->
                  (match
                     inspect_existing_observation_with_installed_extension
                       ~workspace ~observation:primary_observation ~extension
                   with
                  | Ok inspection -> inspection.result
                  | Error Observation_changed ->
                      internal "observation-changed-during-inspection"
                  | Error (Invalid_observation message) -> usage message))))

let inspect ~workspace ~observation =
  (inspect_observation ~workspace ~observation).result
