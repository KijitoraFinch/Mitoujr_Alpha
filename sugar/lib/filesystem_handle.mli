type entry_kind =
  | Regular_file
  | Directory
  | Symlink
  | Reparse_point
  | Other

val open_root : string -> Unix.file_descr
val open_dir_at : Unix.file_descr -> string -> Unix.file_descr
val open_regular_at : Unix.file_descr -> string -> Unix.file_descr
val create_exclusive_at : Unix.file_descr -> string -> int -> Unix.file_descr
val entry_kind_at : Unix.file_descr -> string -> entry_kind
val entries : Unix.file_descr -> string list

val rename_at :
  Unix.file_descr -> string -> Unix.file_descr -> string -> unit

val unlink_at : Unix.file_descr -> string -> unit
