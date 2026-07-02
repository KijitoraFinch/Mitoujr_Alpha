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
      patch_id : Identifier.t;
      target : Workspace_path.t;
    }
  | Identity_mismatch of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      expected : Content_identity.t;
      actual : Content_identity.t;
    }
  | Result_identity_mismatch of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      declared : Content_identity.t;
      actual : Content_identity.t;
    }
  | Range_out_of_bounds of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      range : Text_range.t;
      content_length : int;
    }
  | Overlapping_edits of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      left : Text_range.t;
      right : Text_range.t;
    }
  | Filesystem_safety of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      reason : filesystem_safety_reason;
    }

val compare : t -> t -> int
val target : t -> Workspace_path.t
val patch_id : t -> Identifier.t
val filesystem_safety_reason_string : filesystem_safety_reason -> string
