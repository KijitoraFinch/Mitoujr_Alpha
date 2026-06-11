type flavor = Posix | Windows
type t = string list

let has_nul value = String.contains value '\000'

let validate_segment segment =
  if String.length segment = 0 then Error "path segment must not be empty"
  else if has_nul segment then Error "path must not contain NUL"
  else if String.contains segment '/' then
    Error "path segment must not contain a separator"
  else if String.equal segment "." || String.equal segment ".." then
    Error "path segment must not be dot or dot-dot"
  else Ok segment

let of_segments segments =
  match segments with
  | [] -> Error "workspace path must not be empty"
  | _ ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | segment :: rest ->
            Result.bind (validate_segment segment) (fun valid ->
                loop (valid :: acc) rest)
      in
      loop [] segments

let is_separator flavor = function
  | '/' -> true
  | '\\' when flavor = Windows -> true
  | _ -> false

let is_windows_absolute value =
  let length = String.length value in
  (length >= 1 && is_separator Windows value.[0])
  || (length >= 2
     && ((value.[0] >= 'A' && value.[0] <= 'Z')
        || (value.[0] >= 'a' && value.[0] <= 'z'))
     && value.[1] = ':')

let split_native flavor value =
  let length = String.length value in
  let rec loop start index acc =
    if index = length then
      List.rev (String.sub value start (index - start) :: acc)
    else if is_separator flavor value.[index] then
      loop (index + 1) (index + 1)
        (String.sub value start (index - start) :: acc)
    else loop start (index + 1) acc
  in
  loop 0 0 []

let of_native_string ~flavor value =
  if String.length value = 0 then Error "workspace path must not be empty"
  else if has_nul value then Error "path must not contain NUL"
  else if value.[0] = '/' || (flavor = Windows && is_windows_absolute value) then
    Error "workspace path must be relative"
  else
    let rec normalize stack = function
      | [] -> of_segments (List.rev stack)
      | "" :: rest | "." :: rest -> normalize stack rest
      | ".." :: rest -> (
          match stack with
          | [] -> Error "workspace path escapes the workspace root"
          | _ :: parent -> normalize parent rest)
      | segment :: rest -> normalize (segment :: stack) rest
    in
    normalize [] (split_native flavor value)

let is_unreserved byte =
  (byte >= Char.code 'A' && byte <= Char.code 'Z')
  || (byte >= Char.code 'a' && byte <= Char.code 'z')
  || (byte >= Char.code '0' && byte <= Char.code '9')
  || List.mem byte
       [ Char.code '-'; Char.code '_'; Char.code '.'; Char.code '~' ]

let hex = "0123456789ABCDEF"

let encode_segment segment =
  let buffer = Buffer.create (String.length segment) in
  String.iter
    (fun char ->
      let byte = Char.code char in
      if is_unreserved byte then Buffer.add_char buffer char
      else (
        Buffer.add_char buffer '%';
        Buffer.add_char buffer hex.[byte lsr 4];
        Buffer.add_char buffer hex.[byte land 0x0f]))
    segment;
  Buffer.contents buffer

let to_canonical_string path =
  String.concat "/" (List.map encode_segment path)

let hex_value = function
  | '0' .. '9' as char -> Some (Char.code char - Char.code '0')
  | 'a' .. 'f' as char -> Some (10 + Char.code char - Char.code 'a')
  | 'A' .. 'F' as char -> Some (10 + Char.code char - Char.code 'A')
  | _ -> None

let decode_segment encoded =
  let length = String.length encoded in
  let buffer = Buffer.create length in
  let rec loop index =
    if index = length then Ok (Buffer.contents buffer)
    else if encoded.[index] <> '%' then (
      Buffer.add_char buffer encoded.[index];
      loop (index + 1))
    else if index + 2 >= length then Error "truncated percent escape"
    else
      match (hex_value encoded.[index + 1], hex_value encoded.[index + 2]) with
      | Some high, Some low ->
          Buffer.add_char buffer (Char.chr ((high lsl 4) lor low));
          loop (index + 3)
      | _ -> Error "invalid percent escape"
  in
  loop 0

let of_canonical_string value =
  if String.length value = 0 || value.[0] = '/'
     || value.[String.length value - 1] = '/'
  then Error "canonical workspace path must be non-empty and relative"
  else
    let encoded_segments = String.split_on_char '/' value in
    let rec loop acc = function
      | [] -> of_segments (List.rev acc)
      | segment :: rest ->
          Result.bind (decode_segment segment) (fun decoded ->
              Result.bind (validate_segment decoded) (fun valid ->
                  loop (valid :: acc) rest))
    in
    loop [] encoded_segments

let segments path = path
let compare left right = List.compare String.compare left right
let equal left right = compare left right = 0
