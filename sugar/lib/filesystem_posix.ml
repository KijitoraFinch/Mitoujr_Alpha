type entry_kind = Regular_file | Directory | Symlink | Other

external open_dir_at_raw : Unix.file_descr -> string -> Unix.file_descr
  = "monika_sugar_open_dir_at"

external open_regular_at : Unix.file_descr -> string -> Unix.file_descr
  = "monika_sugar_open_regular_at"

external create_exclusive_at : Unix.file_descr -> string -> int -> Unix.file_descr
  = "monika_sugar_create_exclusive_at"

external entry_kind_at_raw : Unix.file_descr -> string -> int
  = "monika_sugar_entry_kind_at"

external entries_raw : Unix.file_descr -> string array
  = "monika_sugar_entries_at"

external rename_at :
  Unix.file_descr -> string -> Unix.file_descr -> string -> unit
  = "monika_sugar_rename_at"

external rename_noreplace_at :
  Unix.file_descr -> string -> Unix.file_descr -> string -> unit
  = "monika_sugar_rename_noreplace_at"

external unlink_at : Unix.file_descr -> string -> unit
  = "monika_sugar_unlink_at"

let require_posix () =
  if Sys.win32 then invalid_arg "POSIX filesystem adapter is unavailable on Windows"

let open_root path =
  require_posix ();
  Unix.realpath path |> fun physical_path ->
  open_dir_at_raw Unix.stdin physical_path

let open_dir_at directory name =
  require_posix ();
  open_dir_at_raw directory name

let entry_kind_at directory name =
  require_posix ();
  match entry_kind_at_raw directory name with
  | 0 -> Regular_file
  | 1 -> Directory
  | 2 -> Symlink
  | 3 -> Other
  | _ -> failwith "filesystem adapter returned an unknown entry kind"

let entries directory =
  require_posix ();
  entries_raw directory |> Array.to_list |> List.sort String.compare
