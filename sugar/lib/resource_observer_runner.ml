type result =
  | Unsupported
  | Failure of {
      capability : Capability.t option;
      failure : Extension_failure.t;
    }
  | Observed of {
      capability : Capability.t;
      observation : Observation.t;
    }

let runtime_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let invalid_result message =
  Extension_failure.make ~operation:Extension_failure.Observe_resource
    ~code:"invalid-extension-result" ~message
    ~data:(`Assoc [ ("decoder", `String "monika.observeResource") ]) ()

let observe registry origin =
  match Resource_observer_dispatcher.select registry origin with
  | Error _ as error -> error
  | Ok None | Ok (Some Resource_observer_dispatcher.Built_in_workspace_file) ->
      Ok Unsupported
  | Ok (Some (Resource_observer_dispatcher.Installed extension)) ->
      let manifest = Installed_extension.manifest extension in
      let capability = Installed_extension.capability extension in
      let execution =
        Extension_runtime.with_checked_session
          ~executable:(Installed_extension.executable extension)
          ~arguments:(Installed_extension.arguments extension)
          ~authority:(Installed_extension.authority extension)
          ~limits:Extension_runtime.default_limits ~manifest (fun session ->
            Extension_runtime.call_receiving_content session
              ~method_name:"monika.observeResource"
              ~params:(Extension_protocol.observe_resource_params ~origin))
      in
      (match execution with
      | Error runtime ->
          runtime_failure Extension_failure.Observe_resource runtime
          |> Result.map (fun failure ->
                 Failure { capability = Some capability; failure })
      | Ok (json, content) -> (
          match
            Extension_protocol.decode_observe_resource_result ~manifest
              ~requested_origin:origin ~content json
          with
          | Ok (Extension_protocol.Observed observation) ->
              Ok (Observed { capability; observation })
          | Ok (Extension_protocol.Observe_failure failure) ->
              Ok (Failure { capability = Some capability; failure })
          | Error message ->
              invalid_result message
              |> Result.map (fun failure ->
                     Failure { capability = Some capability; failure })))
