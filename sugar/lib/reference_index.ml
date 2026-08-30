type entry =
  | Consistent of {
      value : Reference.t;
      occurrences : Reference_definition_occurrence.t Nonempty.t;
    }
  | Conflict of { occurrences : Reference_definition_occurrence.t Nonempty.t }

type t = (Reference_id.t * entry) list

let build_entry occurrences =
  match Nonempty.of_list occurrences with
  | None -> invalid_arg "Reference_index.build_entry requires a non-empty group"
  | Some occurrences ->
      let first = Nonempty.head occurrences in
      let rest = Nonempty.tail occurrences in
      let value = Reference_definition_occurrence.reference first in
      if
        List.for_all
          (fun occurrence ->
            Reference.equal value
              (Reference_definition_occurrence.reference occurrence))
          rest
      then Consistent { value; occurrences }
      else Conflict { occurrences }

let make occurrences =
  let sorted = List.sort Reference_definition_occurrence.compare occurrences in
  let rec collect current_id current reversed_groups = function
    | [] -> (
        match current_id with
        | None -> List.rev reversed_groups
        | Some id -> List.rev ((id, build_entry (List.rev current)) :: reversed_groups))
    | occurrence :: rest ->
        let id =
          Reference_definition_occurrence.reference occurrence |> Reference.id
        in
        (match current_id with
        | Some current_id when Reference_id.equal current_id id ->
            collect (Some current_id) (occurrence :: current) reversed_groups rest
        | Some current_id ->
            collect (Some id) [ occurrence ]
              ((current_id, build_entry (List.rev current)) :: reversed_groups)
              rest
        | None -> collect (Some id) [ occurrence ] reversed_groups rest)
  in
  collect None [] [] sorted

let entries value = value

let find id value =
  List.find_map
    (fun (candidate, entry) ->
      if Reference_id.equal id candidate then Some entry else None)
    value

let conflicts value =
  List.filter_map
    (function id, (Conflict _ as entry) -> Some (id, entry) | _, Consistent _ -> None)
    value

let consistent_values value =
  List.filter_map
    (function _, Consistent entry -> Some entry.value | _, Conflict _ -> None)
    value
