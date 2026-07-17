type entry_kind = Regular_file | Directory | Reparse_point | Other

external open_root : string -> Unix.file_descr
  = "monika_sugar_windows_open_root"

external open_dir_at : Unix.file_descr -> string -> Unix.file_descr
  = "monika_sugar_windows_open_dir_at"

external open_regular_at : Unix.file_descr -> string -> Unix.file_descr
  = "monika_sugar_windows_open_regular_at"

external create_exclusive_at : Unix.file_descr -> string -> int -> Unix.file_descr
  = "monika_sugar_windows_create_exclusive_at"

external entry_kind_at_raw : Unix.file_descr -> string -> int
  = "monika_sugar_windows_entry_kind_at"

external entries_raw : Unix.file_descr -> string array
  = "monika_sugar_windows_entries_at"

external rename_at :
  Unix.file_descr -> string -> Unix.file_descr -> string -> unit
  = "monika_sugar_windows_rename_at"

external unlink_at : Unix.file_descr -> string -> unit
  = "monika_sugar_windows_unlink_at"

let require_windows () =
  if not Sys.win32 then
    invalid_arg "Windows filesystem adapter is unavailable on this platform"

let entry_kind_at directory name =
  require_windows ();
  match entry_kind_at_raw directory name with
  | 0 -> Regular_file
  | 1 -> Directory
  | 2 -> Reparse_point
  | 3 -> Other
  | _ -> failwith "filesystem adapter returned an unknown Windows entry kind"

let entries directory =
  require_windows ();
  entries_raw directory |> Array.to_list |> List.sort String.compare
