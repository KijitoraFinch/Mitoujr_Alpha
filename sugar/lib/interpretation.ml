type t = {
  interpreter : Interpreter.t;
  observation : Observation_id.t;
  regions : Region.t list;
}

let make ~interpreter ~observation ~regions =
  Result.bind
    (Command_result.make ~command:"interpretation-validation"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~observations:[ observation ] ~regions ())
    (fun _ ->
         match
           List.find_opt
             (fun region ->
               match Region.interpreter_identity region with
               | None -> false
               | Some actual -> not (Interpreter.equal actual interpreter))
             regions
         with
         | Some _ ->
             Error
               "interpretation region belongs to a different interpreter"
         | None ->
             Ok
               {
                 interpreter;
                 observation = Observation.id observation;
                 regions;
               })

let interpreter value = value.interpreter
let observation value = value.observation
let regions value = value.regions
