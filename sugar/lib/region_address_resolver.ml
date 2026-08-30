type t = {
  resolution : Endpoint_resolution.t;
  region : Region.t option;
  message : string option;
  extension_failure : Extension_failure.t option;
}

let ( let* ) = Result.bind

let resolution value = value.resolution
let region value = value.region
let message value = value.message
let extension_failure value = value.extension_failure

let resolved ?region () =
  {
    resolution = Endpoint_resolution.Resolved;
    region;
    message = None;
    extension_failure = None;
  }

let failed ?extension_failure resolution message =
  { resolution; region = None; message = Some message; extension_failure }

let invalid message = failed Endpoint_resolution.Invalid_selector message
let unresolved message = failed Endpoint_resolution.Unresolved message
let unreadable message = failed Endpoint_resolution.Unreadable message

let runtime_extension_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let failed_with_extension resolution failure =
  failed ~extension_failure:failure resolution (Extension_failure.message failure)

let selector_identity selector =
  selector |> Normal.Selector.normalize |> Normal_json.selector
  |> Yojson.Safe.to_string |> Content_digest.of_content
  |> Content_digest.to_hex

let make_region_id observation selector =
  Region_id.make ~observation:(Observation.id observation)
    ~local:("resolved-selector-" ^ selector_identity selector)

let make_whole_region observation =
  let* id =
    Region_id.make ~observation:(Observation.id observation)
      ~local:"whole-observation"
  in
  Ok
    (Region.whole ~id
       ~observation_identity:(Observation.identity observation))

let make_selected_region ~observation ~interpreter ~selector ?summary ?range
    ?fingerprint () =
  let* id = make_region_id observation selector in
  Region.make ~id ~observation_identity:(Observation.identity observation)
    ~selector ~interpreter ?summary ?range ?fingerprint ()

let matching_existing_region observation interpreter selector regions =
  List.find_opt
    (fun region ->
      Observation_id.equal (Observation.id observation)
        (Region.observation region)
      && Selector.compare selector (Region.selector region) = 0
      &&
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal interpreter actual
      | None -> false)
    regions

let resolve_text_range observation interpreter selector range =
  match Observation.bytes observation with
  | None -> Ok (unreadable "text-range requires a byte-backed Observation")
  | Some content when Text_range.end_ range > String.length content ->
      Ok (invalid "text range is outside the target Observation")
  | Some content ->
      let selected =
        String.sub content (Text_range.start range) (Text_range.length range)
      in
      let summary = if Utf8.is_valid selected then Some selected else None in
      let* region =
        make_selected_region ~observation ~interpreter ~selector ?summary
          ~range ~fingerprint:(Fingerprint.sha256 selected) ()
      in
      Ok (resolved ~region ())

let resolve_markdown_region_id observation interpreter existing_regions
    selector local =
  match
    matching_existing_region observation interpreter selector existing_regions
  with
  | Some region -> Ok (resolved ~region ())
  | None -> (
      match Observation.bytes observation with
      | None ->
          Ok
            (unreadable
               "Markdown Region ID requires a byte-backed Observation")
      | Some content -> (
          match Markdown_inspect.inspect ~observation content with
          | Error message -> Ok (invalid message)
          | Ok inspection -> (
              match
                List.find_opt
                  (fun region ->
                    Identifier.equal local
                      (Region.id region |> Region_id.local))
                  inspection.regions
              with
              | Some region -> Ok (resolved ~region ())
              | None -> Ok (unresolved "Markdown Region ID does not resolve"))))

let resolve_row_filter observation interpreter selector filter =
  match Observation.bytes observation with
  | None -> Ok (unreadable "row-filter requires a byte-backed Observation")
  | Some content -> (
      match Jsonl_interpreter.select filter content with
      | Error message -> Ok (invalid message)
      | Ok Jsonl_interpreter.No_match ->
          Ok (unresolved "row-filter does not match a JSONL row")
      | Ok Jsonl_interpreter.Ambiguous ->
          Ok (invalid "row-filter resolves to more than one JSONL row")
      | Ok (Jsonl_interpreter.One selected) ->
          let* region =
            make_selected_region ~observation ~interpreter ~selector
              ~summary:selected.display ~range:selected.range
              ~fingerprint:(Fingerprint.sha256 selected.display) ()
          in
          Ok (resolved ~region ()))

let resolve_built_in selected observation existing_regions selector =
  let interpreter = Interpreter_dispatcher.identity selected in
  match selected, selector with
  | _, Selector.Whole_observation -> Ok (resolved ())
  | Interpreter_dispatcher.Built_in_markdown, Selector.Region_id local ->
      resolve_markdown_region_id observation interpreter existing_regions
        selector local
  | Interpreter_dispatcher.Built_in_jsonl, Selector.Region_id _ ->
      Ok (unresolved "JSONL Region ID does not resolve")
  | (Interpreter_dispatcher.Built_in_markdown
    | Interpreter_dispatcher.Built_in_jsonl), Selector.Text_range range ->
      resolve_text_range observation interpreter selector range
  | Interpreter_dispatcher.Built_in_jsonl, Selector.Row_filter filter ->
      resolve_row_filter observation interpreter selector filter
  | Interpreter_dispatcher.Built_in_markdown, Selector.Row_filter _ ->
      Ok (invalid "row-filter is not owned by the Markdown Interpreter")
  | (Interpreter_dispatcher.Built_in_markdown
    | Interpreter_dispatcher.Built_in_jsonl), Selector.Extension _ ->
      Ok (invalid "extension selector requires its declared Interpreter")
  | Interpreter_dispatcher.Installed _, _ ->
      Error "installed Interpreter reached the built-in resolver"

let validate_extension_selector manifest selector =
  match selector with
  | Selector.Extension extension ->
      let capability = Extension_manifest.capability manifest in
      let schemas =
        match Capability.schemas capability with
        | Some schemas -> schemas.selector_schemas
        | None -> []
      in
      let schema = Selector.Extension.schema extension in
      if List.exists (String.equal schema) schemas then Ok ()
      else
        Error
          "extension selector schema does not match the exact Interpreter manifest"
  | Selector.Whole_observation
  | Selector.Region_id _
  | Selector.Text_range _
  | Selector.Row_filter _ ->
      Ok ()

let resolve_installed extension observation selector =
  let manifest = Installed_extension.manifest extension in
  match validate_extension_selector manifest selector with
  | Error message -> Ok (invalid message)
  | Ok () ->
      let params =
        Extension_protocol.resolve_params ~observation ~selector
      in
      let call session =
        match Observation.bytes observation with
        | Some content ->
            Extension_runtime.call_with_content session
              ~method_name:"monika.resolveRegion" ~params ~content
        | None ->
            Extension_runtime.call session ~method_name:"monika.resolveRegion"
              ~params
      in
      (match
         Extension_runtime.with_checked_session
           ~executable:(Installed_extension.executable extension)
           ~arguments:(Installed_extension.arguments extension)
           ~authority:(Installed_extension.authority extension)
           ~limits:Extension_runtime.default_limits ~manifest (fun session ->
             match call session with
             | Ok result -> Ok (`Result result)
             | Error failure -> Ok (`Method_failure failure))
       with
      | Error failure ->
          let* failure =
            runtime_extension_failure Extension_failure.Session failure
          in
          Ok (failed_with_extension Endpoint_resolution.Unresolved failure)
      | Ok (`Method_failure failure) ->
          let* failure =
            runtime_extension_failure Extension_failure.Resolve_region failure
          in
          Ok (failed_with_extension Endpoint_resolution.Unresolved failure)
      | Ok (`Result result) -> (
          match
            Extension_protocol.decode_resolve_result ~manifest
              ~target_observation:observation ~requested_selector:selector
              result
          with
          | Error message ->
              let* failure =
                Extension_failure.make
                  ~operation:Extension_failure.Resolve_region
                  ~code:"invalid-result" ~message ()
              in
              Ok
                (failed_with_extension Endpoint_resolution.Invalid_selector
                   failure)
          | Ok (Extension_protocol.Resolved_region region) ->
              Ok (resolved ~region ())
          | Ok (Extension_protocol.Resolve_failure failure) ->
              let resolution =
                if String.equal (Extension_failure.code failure) "invalid-selector"
                then Endpoint_resolution.Invalid_selector
                else Endpoint_resolution.Unresolved
              in
              Ok (failed_with_extension resolution failure)))

let resolve ~registry ~observation ~existing_regions address =
  if
    not
      (Origin.equal (Observation.origin observation)
         (Region_address.origin address))
  then Error "RegionAddress Origin does not match the fixed Observation"
  else
    match Region_address.selector address with
    | Selector.Whole_observation ->
        let* region = make_whole_region observation in
        Ok (resolved ~region ())
    | selector -> (
        match Region_address.interpreter_identity address with
        | None ->
            Error
              "partial RegionAddress is missing its exact Interpreter identity"
        | Some interpreter -> (
            let* selected =
              Interpreter_dispatcher.find_exact registry interpreter
            in
            match selected with
            | None ->
                Ok
                  (invalid
                     (Printf.sprintf "required interpreter %s@%s is not installed"
                        (Interpreter.name interpreter)
                        (Interpreter.version interpreter)))
            | Some selected ->
                let* accepts = Interpreter_dispatcher.accepts selected observation in
                if not accepts then
                  Ok
                    (invalid
                       (Printf.sprintf
                          "required interpreter %s@%s does not accept the fixed Observation"
                          (Interpreter.name interpreter)
                          (Interpreter.version interpreter)))
                else
                  match selected with
                  | Interpreter_dispatcher.Installed extension ->
                      resolve_installed extension observation selector
                  | Interpreter_dispatcher.Built_in_markdown
                  | Interpreter_dispatcher.Built_in_jsonl ->
                      resolve_built_in selected observation existing_regions
                        selector))
