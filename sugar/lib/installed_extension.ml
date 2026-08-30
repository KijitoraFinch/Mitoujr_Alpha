type t = {
  manifest : Extension_manifest.t;
  executable : string;
  arguments : string list;
}

let contains_nul value = String.contains value '\000'

let valid_argument value = Utf8.is_valid value && not (contains_nul value)

let make ~manifest ~executable ~arguments =
  if String.length executable = 0 then
    Error "installed extension executable must not be empty"
  else if Filename.is_relative executable then
    Error "installed extension executable must be an absolute path"
  else if not (valid_argument executable) then
    Error "installed extension executable must be UTF-8 and contain no NUL"
  else if not (List.for_all valid_argument arguments) then
    Error "installed extension arguments must be UTF-8 and contain no NUL"
  else Ok { manifest; executable; arguments }

let manifest value = value.manifest
let capability value = Extension_manifest.capability value.manifest
let executable value = value.executable
let arguments value = value.arguments

let compare left right =
  match Capability.compare (capability left) (capability right) with
  | 0 -> (
      match String.compare left.executable right.executable with
      | 0 -> List.compare String.compare left.arguments right.arguments
      | other -> other)
  | other -> other
