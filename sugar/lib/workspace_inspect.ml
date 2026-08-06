let ( let* ) = Result.bind

type observation = {
  result : Command_result.t;
  content : string option;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
}

let empty_observation result =
  { result; content = None; occurrences = []; relations = [] }

let complete_observation ~content ~occurrences ~annotations result =
  {
    result;
    content = Some content;
    occurrences;
    relations = List.filter_map Relation.of_annotation annotations;
  }

let command_result ?summary ?(diagnostics = []) ?(artifacts = [])
    ?(regions = []) ?(references = []) ?(annotations = []) ~termination () =
  match
    Command_result.make ~command:"inspect" ~termination
      ~effect:Command_result.No_change ~diagnostics ~artifacts ~regions
      ~references ~annotations ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid inspect CommandResult: " ^ message)

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

let artifact_id path =
  Artifact_id.make ("artifact:" ^ Workspace_path.to_canonical_string path)

let artifact ~media_type path file =
  let* id = artifact_id path in
  Artifact.make ~id ~origin:(Artifact.workspace path) ~media_type
    ~content_identity:(Workspace_read.content_identity file) ()

let diagnostic ~artifact_id ~code message =
  Diagnostic.make ~code ~message
    ~location:
      {
        Diagnostic.artifact = Some artifact_id;
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
  diagnostic ~artifact_id:sidecar_id ~code:Diagnostic.Authored_override
    (Printf.sprintf
       "authored %s %s overrides a different derived entry"
       kind override.local)

let diagnostic_result ~artifacts diagnostic =
  command_result ~termination:Command_result.Completed ~artifacts
    ~diagnostics:[ diagnostic ]
    ~summary:
      [
        ("annotations", Command_result.Count 0);
        ("references", Command_result.Count 0);
        ("regions", Command_result.Count 0);
      ]
    ()

let read_primary ~workspace path =
  match Workspace_read.read ~workspace ~path with
  | Ok file -> Ok file
  | Error Workspace_read.Invalid_workspace ->
      Error (`Usage "workspace must be an existing directory")
  | Error Workspace_read.Missing_artifact ->
      Error (`Usage "artifact does not exist")
  | Error (Workspace_read.Unsafe _) ->
      Error (`Usage "artifact is outside the safe workspace read policy")
  | Error Workspace_read.Unstable_content -> Error (`Internal "read-stable-artifact")
  | Error (Workspace_read.Filesystem_io operation) -> Error (`Internal operation)

let sidecar_path primary =
  let segments = Workspace_path.segments primary in
  match List.rev segments with
  | [] -> invalid_arg "workspace path has no segments"
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
              Artifact.compare_origin
                (Reference.target_artifact (Reference.target selected))
                (Reference.target_artifact (Reference.target reference))
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
  match (Region_address.artifact address, Region_address.selector address) with
  | Origin.Workspace path, Selector.Region_id local ->
      let* artifact =
        Artifact_id.make ("artifact:" ^ Workspace_path.to_canonical_string path)
      in
      Region_id.make ~artifact ~local:(Identifier.to_string local)
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

let inspect_supported ~workspace ~artifact_path primary_file primary_artifact =
  let primary_id = Artifact.id primary_artifact in
  let content = Workspace_read.content primary_file in
  match
    Markdown_inspect.inspect ~artifact:primary_id ~path:artifact_path
      content
  with
  | Error message ->
      let diagnostic =
        diagnostic ~artifact_id:primary_id ~code:Diagnostic.Invalid_selector
          message
        |> Result.get_ok
      in
      empty_observation
        (diagnostic_result ~artifacts:[ primary_artifact ] diagnostic)
  | Ok markdown -> (
      let sidecar_path = Result.get_ok (sidecar_path artifact_path) in
      match Workspace_read.read ~workspace ~path:sidecar_path with
      | Error Workspace_read.Missing_artifact ->
          if
            not
              (references_cover_annotations markdown.references
                 markdown.annotations)
          then
            let diagnostic =
              diagnostic ~artifact_id:primary_id
                ~code:Diagnostic.Invalid_selector
                "inline annotation refers to an undeclared reference"
              |> Result.get_ok
            in
            empty_observation
              (diagnostic_result ~artifacts:[ primary_artifact ] diagnostic)
          else
            let result =
              command_result ~termination:Command_result.Completed
                ~artifacts:[ primary_artifact ] ~regions:markdown.regions
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
            complete_observation ~content ~occurrences:markdown.occurrences
              ~annotations:markdown.annotations result
      | Error Workspace_read.Invalid_workspace ->
          empty_observation (usage "workspace must be an existing directory")
      | Error Workspace_read.Unstable_content ->
          empty_observation
            (internal ~location:sidecar_path "read-stable-sidecar")
      | Error (Workspace_read.Filesystem_io operation) ->
          empty_observation (internal ~location:sidecar_path operation)
      | Error (Workspace_read.Unsafe _) ->
          let diagnostic =
            diagnostic ~artifact_id:primary_id ~code:Diagnostic.Invalid_sidecar
              "sidecar is outside the safe workspace read policy"
            |> Result.get_ok
          in
          empty_observation
            (diagnostic_result ~artifacts:[ primary_artifact ] diagnostic)
      | Ok sidecar_file ->
          let sidecar_artifact =
            artifact ~media_type:"application/yaml" sidecar_path sidecar_file
            |> Result.get_ok
          in
          let sidecar_id = Artifact.id sidecar_artifact in
          let artifacts = [ primary_artifact; sidecar_artifact ] in
          (match
             Sidecar_v1.decode ~primary_artifact:primary_id
               ~sidecar_artifact:sidecar_id ~sidecar_path
               (Workspace_read.content sidecar_file)
           with
          | Error message ->
              let diagnostic =
                diagnostic ~artifact_id:sidecar_id ~code:Diagnostic.Invalid_sidecar
                  message
                |> Result.get_ok
              in
              empty_observation (diagnostic_result ~artifacts diagnostic)
          | Ok sidecar -> (
              let ownership_diagnostics =
                sidecar.overrides
                |> List.map (sidecar_override_diagnostic sidecar_id)
                |> List.map Result.get_ok
              in
              match merge_inline_references sidecar.references markdown.references with
              | Error message ->
                  let diagnostic =
                    diagnostic ~artifact_id:primary_id ~code:Diagnostic.Divergent
                      message
                    |> Result.get_ok
                  in
                  empty_observation (diagnostic_result ~artifacts diagnostic)
              | Ok (references, reference_divergence_messages) ->
                  (match
                     merge_annotations markdown.regions markdown.annotations
                       sidecar.annotations
                   with
                  | Error message ->
                    let diagnostic =
                      diagnostic ~artifact_id:primary_id
                        ~code:Diagnostic.Divergent
                        message
                      |> Result.get_ok
                    in
                    empty_observation
                      (diagnostic_result ~artifacts diagnostic)
                  | Ok (annotations, divergence_messages) ->
                  let divergence_diagnostics =
                    (reference_divergence_messages @ divergence_messages)
                    |> List.map (fun message ->
                           diagnostic ~artifact_id:primary_id
                             ~code:Diagnostic.Divergent message
                           |> Result.get_ok)
                  in
                  let diagnostics =
                    ownership_diagnostics @ divergence_diagnostics
                  in
                  if not (references_cover_annotations references annotations) then
                    let diagnostic =
                      diagnostic ~artifact_id:sidecar_id
                        ~code:Diagnostic.Invalid_sidecar
                        "annotation refers to an undeclared reference"
                      |> Result.get_ok
                    in
                    empty_observation
                      (diagnostic_result ~artifacts diagnostic)
                  else
                    let result =
                      command_result ~termination:Command_result.Completed
                        ~artifacts ~regions:markdown.regions ~references
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
                    complete_observation
                      ~content ~occurrences:markdown.occurrences ~annotations
                      result))))

let inspect_observation ~workspace ~artifact:artifact_path =
  match read_primary ~workspace artifact_path with
  | Error (`Usage message) -> empty_observation (usage message)
  | Error (`Internal operation) ->
      empty_observation (internal ~location:artifact_path operation)
  | Ok primary_file ->
      let primary_artifact =
        artifact ~media_type:"text/markdown" artifact_path primary_file
        |> Result.get_ok
      in
      if is_markdown artifact_path then
        inspect_supported ~workspace ~artifact_path primary_file
          primary_artifact
      else
        let diagnostic =
          diagnostic ~artifact_id:(Artifact.id primary_artifact)
            ~code:Diagnostic.Unsupported_artifact
            "no standard interpreter supports this artifact"
          |> Result.get_ok
        in
        empty_observation
          (diagnostic_result ~artifacts:[ primary_artifact ] diagnostic)

let inspect ~workspace ~artifact =
  (inspect_observation ~workspace ~artifact).result
