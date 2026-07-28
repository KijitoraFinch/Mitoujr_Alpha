type filesystem_safety_reason =
  | Invalid_native_path
  | Path_escapes_workspace
  | Symlink_component
  | Target_is_symlink
  | Parent_not_directory
  | Target_not_regular_file
  | Native_spelling_mismatch
  | Reparse_point

type t =
  | Missing_artifact of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
    }
  | Artifact_already_exists of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      actual : Content_identity.t;
    }
  | Identity_mismatch of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      expected : Content_identity.t;
      actual : Content_identity.t;
    }
  | Result_identity_mismatch of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      declared : Content_identity.t;
      actual : Content_identity.t;
    }
  | Range_out_of_bounds of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      range : Text_range.t;
      content_length : int;
    }
  | Overlapping_edits of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      left : Text_range.t;
      right : Text_range.t;
    }
  | Filesystem_safety of {
      patch_id : Patch_id.t;
      target : Workspace_path.t;
      reason : filesystem_safety_reason;
    }

let missing_artifact ~patch_id ~target = Missing_artifact { patch_id; target }
let artifact_already_exists ~patch_id ~target ~actual =
  Artifact_already_exists { patch_id; target; actual }

let identity_mismatch ~patch_id ~target ~expected ~actual =
  if Content_identity.equal expected actual then
    Error "identity mismatch requires different expected and actual identities"
  else Ok (Identity_mismatch { patch_id; target; expected; actual })

let result_identity_mismatch ~patch_id ~target ~declared ~actual =
  if Content_identity.equal declared actual then
    Error "result identity mismatch requires different declared and actual identities"
  else Ok (Result_identity_mismatch { patch_id; target; declared; actual })

let range_out_of_bounds ~patch_id ~target ~range ~content_length =
  if not (Protocol_integer.is_nonnegative_safe content_length) then
    Error "conflict content length must be a non-negative protocol safe integer"
  else if Text_range.end_ range <= content_length then
    Error "range-out-of-bounds conflict requires a range beyond content length"
  else Ok (Range_out_of_bounds { patch_id; target; range; content_length })

let overlapping_edits ~patch_id ~target ~left ~right =
  if
    Text_range.end_ left <= Text_range.start right
    || Text_range.end_ right <= Text_range.start left
  then Error "overlapping-edits conflict requires intersecting ranges"
  else Ok (Overlapping_edits { patch_id; target; left; right })

let filesystem_safety ~patch_id ~target ~reason =
  Filesystem_safety { patch_id; target; reason }

let target = function
  | Missing_artifact value -> value.target
  | Artifact_already_exists value -> value.target
  | Identity_mismatch value -> value.target
  | Result_identity_mismatch value -> value.target
  | Range_out_of_bounds value -> value.target
  | Overlapping_edits value -> value.target
  | Filesystem_safety value -> value.target

let patch_id = function
  | Missing_artifact value -> value.patch_id
  | Artifact_already_exists value -> value.patch_id
  | Identity_mismatch value -> value.patch_id
  | Result_identity_mismatch value -> value.patch_id
  | Range_out_of_bounds value -> value.patch_id
  | Overlapping_edits value -> value.patch_id
  | Filesystem_safety value -> value.patch_id

let filesystem_safety_reason_string = function
  | Invalid_native_path -> "invalid-native-path"
  | Path_escapes_workspace -> "path-escapes-workspace"
  | Symlink_component -> "symlink-component"
  | Target_is_symlink -> "target-is-symlink"
  | Parent_not_directory -> "parent-not-directory"
  | Target_not_regular_file -> "target-not-regular-file"
  | Native_spelling_mismatch -> "native-spelling-mismatch"
  | Reparse_point -> "reparse-point"

let rank = function
  | Missing_artifact _ -> 0
  | Artifact_already_exists _ -> 1
  | Identity_mismatch _ -> 2
  | Result_identity_mismatch _ -> 3
  | Range_out_of_bounds _ -> 4
  | Overlapping_edits _ -> 5
  | Filesystem_safety _ -> 6

let compare left right =
  match Workspace_path.compare (target left) (target right) with
  | 0 -> (
      match Patch_id.compare (patch_id left) (patch_id right) with
      | 0 -> Int.compare (rank left) (rank right)
      | other -> other)
  | other -> other
