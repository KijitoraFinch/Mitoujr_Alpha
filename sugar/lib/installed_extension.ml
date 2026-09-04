type t = {
  manifest : Extension_manifest.t;
  executable : string;
  arguments : string list;
  authority : Extension_authority.t;
}

let contains_nul value = String.contains value '\000'

let valid_argument value = Utf8.is_valid value && not (contains_nul value)

let arguments_exceed_byte_limit arguments =
  let rec loop remaining = function
    | [] -> false
    | argument :: rest ->
        let length = String.length argument in
        length > remaining || loop (remaining - length) rest
  in
  loop (64 * 1024) arguments

let make ~manifest ~executable ~arguments ~authority =
  if String.length executable = 0 then
    Error "installed extension executable must not be empty"
  else if not (Extension_authority.is_absolute_path executable) then
    Error "installed extension executable must be an absolute path"
  else if not (valid_argument executable) then
    Error "installed extension executable must be UTF-8 and contain no NUL"
  else if not (List.for_all valid_argument arguments) then
    Error "installed extension arguments must be UTF-8 and contain no NUL"
  else if List.length arguments > 128 then
    Error "installed extension arguments exceed the 128-argument limit"
  else if arguments_exceed_byte_limit arguments then
    Error "installed extension arguments exceed the 64 KiB byte limit"
  else
    Extension_authority.validate_for_capability
      (Extension_manifest.capability manifest) authority
    |> Result.map (fun () -> { manifest; executable; arguments; authority })

let manifest value = value.manifest
let capability value = Extension_manifest.capability value.manifest
let executable value = value.executable
let arguments value = value.arguments
let authority value = value.authority

let compare left right =
  match Capability.compare (capability left) (capability right) with
  | 0 -> (
      match String.compare left.executable right.executable with
      | 0 -> (
          match List.compare String.compare left.arguments right.arguments with
          | 0 -> Extension_authority.compare left.authority right.authority
          | other -> other)
      | other -> other)
  | other -> other
