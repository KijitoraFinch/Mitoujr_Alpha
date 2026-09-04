type matcher =
  | Basename of string
  | Relative_path of string list

type rule = {
  base : string list;
  matcher : matcher;
  directory_only : bool;
  negated : bool;
}

type t = rule list

let empty = []

let is_escaped value index =
  let rec count backslashes position =
    if position >= 0 && Char.equal value.[position] '\\' then
      count (backslashes + 1) (position - 1)
    else backslashes
  in
  count 0 (index - 1) mod 2 = 1

let strip_cr value =
  let length = String.length value in
  if length > 0 && Char.equal value.[length - 1] '\r' then
    String.sub value 0 (length - 1)
  else value

let trim_unescaped_trailing_spaces value =
  let rec finish length =
    if
      length > 0
      && Char.equal value.[length - 1] ' '
      && not (is_escaped value (length - 1))
    then finish (length - 1)
    else length
  in
  let length = finish (String.length value) in
  if length = String.length value then value else String.sub value 0 length

let has_unescaped_slash value =
  let rec loop index =
    if index = String.length value then false
    else if
      Char.equal value.[index] '/' && not (is_escaped value index)
    then true
    else loop (index + 1)
  in
  loop 0

let split_components value =
  let length = String.length value in
  let buffer = Buffer.create length in
  let finish components =
    let component = Buffer.contents buffer in
    Buffer.clear buffer;
    component :: components
  in
  let rec loop index components =
    if index = length then List.rev (finish components)
    else
      match value.[index] with
      | '\\' when index + 1 < length ->
          Buffer.add_char buffer value.[index];
          Buffer.add_char buffer value.[index + 1];
          loop (index + 2) components
      | '/' -> loop (index + 1) (finish components)
      | character ->
          Buffer.add_char buffer character;
          loop (index + 1) components
  in
  loop 0 []

let parse_line base line =
  let line = line |> strip_cr |> trim_unescaped_trailing_spaces in
  let length = String.length line in
  if length = 0 || Char.equal line.[0] '#' then None
  else
    let negated, start =
      if Char.equal line.[0] '!' then (true, 1) else (false, 0)
    in
    if start = length then None
    else
      let anchored =
        start < length && Char.equal line.[start] '/'
        && not (is_escaped line start)
      in
      let start = if anchored then start + 1 else start in
      let directory_only =
        start < length
        && Char.equal line.[length - 1] '/'
        && not (is_escaped line (length - 1))
      in
      let finish = if directory_only then length - 1 else length in
      if finish <= start then None
      else
        let pattern = String.sub line start (finish - start) in
        let path_pattern = anchored || has_unescaped_slash pattern in
        let matcher =
          if path_pattern then Relative_path (split_components pattern)
          else Basename pattern
        in
        Some { base; matcher; directory_only; negated }

let add_patterns ~base content rules =
  let base =
    match base with
    | None -> []
    | Some path -> Workspace_path.segments path
  in
  String.split_on_char '\n' content
  |> List.fold_left
       (fun rules line ->
         match parse_line base line with
         | None -> rules
         | Some rule -> rule :: rules)
       rules

let class_character pattern index =
  if index >= String.length pattern then None
  else if Char.equal pattern.[index] '\\' then
    if index + 1 = String.length pattern then None
    else Some (pattern.[index + 1], index + 2)
  else Some (pattern.[index], index + 1)

let named_class_matches name candidate =
  let code = Char.code candidate in
  let between lower upper =
    Char.code lower <= code && code <= Char.code upper
  in
  let alpha = between 'a' 'z' || between 'A' 'Z' in
  let digit = between '0' '9' in
  match name with
  | "alnum" -> alpha || digit
  | "alpha" -> alpha
  | "blank" -> Char.equal candidate ' ' || Char.equal candidate '\t'
  | "cntrl" -> code < 0x20 || code = 0x7f
  | "digit" -> digit
  | "graph" -> 0x21 <= code && code <= 0x7e
  | "lower" -> between 'a' 'z'
  | "print" -> 0x20 <= code && code <= 0x7e
  | "punct" -> 0x21 <= code && code <= 0x7e && not (alpha || digit)
  | "space" ->
      Char.equal candidate ' '
      || Char.equal candidate '\t'
      || Char.equal candidate '\n'
      || Char.equal candidate '\r'
      || Char.equal candidate '\011'
      || Char.equal candidate '\012'
  | "upper" -> between 'A' 'Z'
  | "xdigit" -> digit || between 'a' 'f' || between 'A' 'F'
  | _ -> false

let named_class pattern index candidate =
  let length = String.length pattern in
  if
    index + 3 >= length
    || not (Char.equal pattern.[index] '[')
    || not (Char.equal pattern.[index + 1] ':')
  then
    None
  else
    let rec closing position =
      if position + 1 >= length then None
      else if
        Char.equal pattern.[position] ':'
        && Char.equal pattern.[position + 1] ']'
      then Some position
      else closing (position + 1)
    in
    match closing (index + 2) with
    | None -> None
    | Some finish ->
        let name = String.sub pattern (index + 2) (finish - index - 2) in
        Some (named_class_matches name candidate, finish + 2)

let class_match pattern start candidate =
  let length = String.length pattern in
  let index = start + 1 in
  let negated, index =
    if
      index < length
      && (Char.equal pattern.[index] '!'
         || Char.equal pattern.[index] '^')
    then (true, index + 1)
    else (false, index)
  in
  let rec loop index first matched =
    if index >= length then None
    else if Char.equal pattern.[index] ']' && not first then
      Some ((if negated then not matched else matched), index + 1)
    else
      match named_class pattern index candidate with
      | Some (accepted, next) -> loop next false (matched || accepted)
      | None -> (
          match class_character pattern index with
          | None -> None
          | Some (lower, next) ->
              if
                next + 1 < length
                && Char.equal pattern.[next] '-'
                && not (Char.equal pattern.[next + 1] ']')
              then
                (match class_character pattern (next + 1) with
                | None -> None
                | Some (upper, after) ->
                    let code = Char.code candidate in
                    let lower = Char.code lower in
                    let upper = Char.code upper in
                    loop after false
                      (matched || (lower <= code && code <= upper)))
              else
                loop next false (matched || Char.equal lower candidate))
  in
  loop index true false

let component_match pattern value =
  let pattern_length = String.length pattern in
  let value_length = String.length value in
  let memo = Hashtbl.create 64 in
  let rec matches pattern_index value_index =
    match Hashtbl.find_opt memo (pattern_index, value_index) with
    | Some result -> result
    | None ->
        let result =
          if pattern_index = pattern_length then value_index = value_length
          else
            match pattern.[pattern_index] with
            | '\\' ->
                pattern_index + 1 < pattern_length
                && value_index < value_length
                && Char.equal pattern.[pattern_index + 1] value.[value_index]
                && matches (pattern_index + 2) (value_index + 1)
            | '?' ->
                value_index < value_length
                && matches (pattern_index + 1) (value_index + 1)
            | '*' ->
                let rec after_stars index =
                  if index < pattern_length && Char.equal pattern.[index] '*'
                  then after_stars (index + 1)
                  else index
                in
                let next = after_stars (pattern_index + 1) in
                matches next value_index
                || (value_index < value_length
                   && matches pattern_index (value_index + 1))
            | '[' -> (
                if value_index = value_length then false
                else
                  match class_match pattern pattern_index value.[value_index] with
                  | None -> false
                  | Some (accepted, next) ->
                      accepted && matches next (value_index + 1))
            | character ->
                value_index < value_length
                && Char.equal character value.[value_index]
                && matches (pattern_index + 1) (value_index + 1)
        in
        Hashtbl.add memo (pattern_index, value_index) result;
        result
  in
  matches 0 0

let relative_segments base path =
  let rec drop base path =
    match (base, path) with
    | [], rest -> Some rest
    | expected :: base, actual :: path when String.equal expected actual ->
        drop base path
    | _ -> None
  in
  drop base path

let path_match patterns values =
  let patterns = Array.of_list patterns in
  let values = Array.of_list values in
  let pattern_length = Array.length patterns in
  let value_length = Array.length values in
  let memo = Hashtbl.create 64 in
  let rec matches pattern_index value_index =
    match Hashtbl.find_opt memo (pattern_index, value_index) with
    | Some result -> result
    | None ->
        let result =
          if pattern_index = pattern_length then value_index = value_length
          else if String.equal patterns.(pattern_index) "**" then
            if pattern_index + 1 = pattern_length then
              value_index < value_length
            else
              matches (pattern_index + 1) value_index
              || (value_index < value_length
                 && matches pattern_index (value_index + 1))
          else
            value_index < value_length
            && component_match patterns.(pattern_index) values.(value_index)
            && matches (pattern_index + 1) (value_index + 1)
        in
        Hashtbl.add memo (pattern_index, value_index) result;
        result
  in
  matches 0 0

let rule_matches rule ~path ~directory =
  if rule.directory_only && not directory then false
  else
    match relative_segments rule.base path with
    | None | Some [] -> false
    | Some relative -> (
        match rule.matcher with
        | Basename pattern ->
            let basename =
              List.fold_left (fun _ segment -> segment) "" relative
            in
            component_match pattern basename
        | Relative_path patterns -> path_match patterns relative)

let is_ignored rules ~path ~directory =
  let path = Workspace_path.segments path in
  match List.find_opt (fun rule -> rule_matches rule ~path ~directory) rules with
  | None -> false
  | Some rule -> not rule.negated
