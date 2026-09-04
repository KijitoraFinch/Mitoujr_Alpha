let failure operation code message =
  Extension_failure.make ~operation ~code ~message () |> Result.get_ok

let invalid message =
  Error
    (failure Extension_failure.Classify_region_extents "invalid-regions" message)

let runtime_failure operation value =
  failure operation (Extension_runtime.failure_code value)
    (Extension_runtime.failure_message value)

let call_with_observation session ~method_name ~params observation =
  match Observation.bytes observation with
  | Some content ->
      Extension_runtime.call_with_content session ~method_name ~params ~content
  | None -> Extension_runtime.call session ~method_name ~params

let classify_external ~observation ~left ~right extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_protocol.classify_region_extents_params ~observation
      ~left ~right
  with
  | Error message -> invalid message
  | Ok params -> (
      match
        Extension_runtime.with_checked_session
          ~executable:(Installed_extension.executable extension)
          ~arguments:(Installed_extension.arguments extension)
          ~authority:(Installed_extension.authority extension)
          ~limits:Extension_runtime.default_limits ~manifest (fun session ->
            match
              call_with_observation session
                ~method_name:"monika.classifyRegionExtents" ~params observation
            with
            | Ok result -> Ok (`Result result)
            | Error value -> Ok (`Method_failure value))
      with
      | Error value -> Error (runtime_failure Extension_failure.Session value)
      | Ok (`Method_failure value) ->
          Error
            (runtime_failure Extension_failure.Classify_region_extents value)
      | Ok (`Result result) -> (
          match Extension_protocol.decode_classify_result result with
          | Error message ->
              Error
                (failure Extension_failure.Classify_region_extents
                   "invalid-result" message)
          | Ok (Extension_protocol.Classify_failure value) ->
              Error value
          | Ok (Extension_protocol.Classified relation) ->
              Ok relation))

let classify ~registry ~observation ~left ~right =
  if
    not
      (Observation_id.equal (Observation.id observation)
         (Region.observation left))
    || not
         (Observation_id.equal (Observation.id observation)
            (Region.observation right))
    || not
      (Observation_identity.equal (Observation.identity observation)
         (Region.observation_identity left))
    || not
         (Observation_identity.equal (Observation.identity observation)
            (Region.observation_identity right))
  then invalid "both regions must belong to the fixed observation"
  else
    match
      ( Region.interpreter_identity left,
        Region.interpreter_identity right )
    with
    | None, _ | _, None ->
        Region_extent_relation.classify_builtin left right
        |> Result.map_error (fun message ->
               failure Extension_failure.Classify_region_extents
                 "invalid-regions" message)
    | Some left_interpreter, Some right_interpreter ->
        if not (Interpreter.equal left_interpreter right_interpreter) then
          invalid "cannot compare partial regions from different interpreters"
        else
          match Interpreter_dispatcher.find_exact registry left_interpreter with
          | Error message -> invalid message
          | Ok None ->
              invalid
                (Printf.sprintf "required interpreter %s@%s is not installed"
                   (Interpreter.name left_interpreter)
                   (Interpreter.version left_interpreter))
          | Ok (Some (Interpreter_dispatcher.Installed extension)) ->
              classify_external ~observation ~left ~right extension
          | Ok (Some
              (Interpreter_dispatcher.Built_in_markdown
              | Interpreter_dispatcher.Built_in_jsonl)) ->
              Region_extent_relation.classify_builtin left right
              |> Result.map_error (fun message ->
                     failure Extension_failure.Classify_region_extents
                       "invalid-regions" message)
