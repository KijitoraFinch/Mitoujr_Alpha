type stage =
  | Prepare_temporary
  | Verify_source
  | Atomic_replace
  | Flush_parent
  | Verify_result

type commit_state = Not_committed | Committed_or_unknown

type 'error failure = {
  stage : stage;
  commit_state : commit_state;
  cause : 'error;
}

type ('temporary, 'error) operations = {
  prepare_temporary : unit -> ('temporary, 'error) result;
  cleanup_temporary : 'temporary -> unit;
  verify_source : unit -> (unit, 'error) result;
  atomic_replace : 'temporary -> (unit, 'error) result;
  flush_parent : unit -> (unit, 'error) result;
  verify_result : unit -> (unit, 'error) result;
}

let failure stage commit_state cause = Error { stage; commit_state; cause }

let run operations =
  match operations.prepare_temporary () with
  | Error cause -> failure Prepare_temporary Not_committed cause
  | Ok temporary -> (
      match operations.verify_source () with
      | Error cause ->
          operations.cleanup_temporary temporary;
          failure Verify_source Not_committed cause
      | Ok () -> (
          match operations.atomic_replace temporary with
          | Error cause ->
              operations.cleanup_temporary temporary;
              failure Atomic_replace Committed_or_unknown cause
          | Ok () -> (
              match operations.flush_parent () with
              | Error cause ->
                  failure Flush_parent Committed_or_unknown cause
              | Ok () -> (
                  match operations.verify_result () with
                  | Error cause ->
                      failure Verify_result Committed_or_unknown cause
                  | Ok () -> Ok ()))))
