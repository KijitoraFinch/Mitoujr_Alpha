type entry_kind =
  | Regular_file
  | Directory
  | Symlink
  | Reparse_point
  | Other

let open_root path =
  if Sys.win32 then Filesystem_windows.open_root path
  else Filesystem_posix.open_root path

let open_dir_at directory name =
  if Sys.win32 then Filesystem_windows.open_dir_at directory name
  else Filesystem_posix.open_dir_at directory name

let open_regular_at directory name =
  if Sys.win32 then Filesystem_windows.open_regular_at directory name
  else Filesystem_posix.open_regular_at directory name

let create_exclusive_at directory name mode =
  if Sys.win32 then Filesystem_windows.create_exclusive_at directory name mode
  else Filesystem_posix.create_exclusive_at directory name mode

let entry_kind_at directory name =
  if Sys.win32 then
    match Filesystem_windows.entry_kind_at directory name with
    | Filesystem_windows.Regular_file -> Regular_file
    | Filesystem_windows.Directory -> Directory
    | Filesystem_windows.Reparse_point -> Reparse_point
    | Filesystem_windows.Other -> Other
  else
    match Filesystem_posix.entry_kind_at directory name with
    | Filesystem_posix.Regular_file -> Regular_file
    | Filesystem_posix.Directory -> Directory
    | Filesystem_posix.Symlink -> Symlink
    | Filesystem_posix.Other -> Other

let entries directory =
  if Sys.win32 then Filesystem_windows.entries directory
  else Filesystem_posix.entries directory

let rename_at source_directory source target_directory target =
  if Sys.win32 then
    Filesystem_windows.rename_at source_directory source target_directory target
  else Filesystem_posix.rename_at source_directory source target_directory target

let rename_noreplace_at source_directory source target_directory target =
  if Sys.win32 then
    Filesystem_windows.rename_noreplace_at source_directory source
      target_directory target
  else
    Filesystem_posix.rename_noreplace_at source_directory source target_directory
      target

let unlink_at directory name =
  if Sys.win32 then Filesystem_windows.unlink_at directory name
  else Filesystem_posix.unlink_at directory name
