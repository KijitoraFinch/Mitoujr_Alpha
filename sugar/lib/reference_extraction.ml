type t = {
  definitions : Reference.t list;
  uses : Reference_occurrence.t list;
}

let make ~observation ~definitions ~uses =
  let observation_id = Observation.id observation in
  let foreign_definition =
    List.find_opt
      (fun reference ->
        not
          (Observation_id.equal observation_id
             (Reference.id reference |> Reference_id.observation)))
      definitions
  in
  let foreign_use =
    List.find_opt
      (fun use ->
        not
          (Observation_id.equal observation_id
             (Reference_occurrence.source_observation use)))
      uses
  in
  match (foreign_definition, foreign_use) with
  | Some _, _ ->
      Error "reference definition is outside the extracted observation"
  | _, Some _ -> Error "reference use is outside the extracted observation"
  | None, None -> Ok { definitions; uses }

let definitions value = value.definitions
let uses value = value.uses
