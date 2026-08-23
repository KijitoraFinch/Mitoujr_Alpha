type t = {
  regions : Region.t list;
  references : Reference.t list;
  annotations : Annotation.t list;
}

let make ~observation ~regions ~references ~annotations =
  Command_result.make ~command:"interpretation-validation"
    ~termination:Command_result.Completed ~effect:Command_result.No_change
    ~observations:[ observation ] ~regions ~references ~annotations ()
  |> Result.map (fun _ -> { regions; references; annotations })

let regions value = value.regions
let references value = value.references
let annotations value = value.annotations
