let interpret ~observation ~parsed =
  let ( let* ) = Result.bind in
  let* interpreter = Interpreter.make ~name:"markdown" ~version:"1" () in
  let* whole_id =
    Region_id.make ~observation:(Observation.id observation)
      ~local:"whole-observation"
  in
  let whole =
    Region.whole ~id:whole_id
      ~observation_identity:(Observation.identity observation)
  in
  Interpretation.make ~interpreter ~observation
    ~regions:(whole :: parsed.Markdown_inspect.regions)
