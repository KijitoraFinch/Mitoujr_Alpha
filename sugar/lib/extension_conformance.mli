type failure =
  | Session_runtime of Extension_runtime.failure
  | Method_runtime of {
      operation : Extension_failure.operation;
      method_name : string;
      failure : Extension_runtime.failure;
    }
  | Invalid_result of {
      operation : Extension_failure.operation;
      method_name : string;
      message : string;
    }

val check :
  session:Extension_runtime.session ->
  manifest:Extension_manifest.t ->
  (string list, failure) result
