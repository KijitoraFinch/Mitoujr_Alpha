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

(** Runs the replacement commit protocol.

    A failure from [atomic_replace] is conservatively classified as
    [Committed_or_unknown], because a platform adapter may be unable to prove
    whether a failed replacement became visible. Every later failure is also
    classified that way. Consequently, callers cannot accidentally translate
    a durability or read-back failure into a successful applied result. *)
val run :
  ('temporary, 'error) operations -> (unit, 'error failure) result
