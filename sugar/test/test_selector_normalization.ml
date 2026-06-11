open Monika_sugar

let expect_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message

let test_row_filter_normalization () =
  let metric = expect_ok (Selector.Field_name.make "metric") in
  let retry = expect_ok (Selector.Field_name.make "retry") in
  let warmup = expect_ok (Selector.Field_name.make "warmup") in
  let filter =
    expect_ok
      (Selector.Row_filter.make
         [
           (warmup, Selector.Literal.Bool true);
           (metric, Selector.Literal.String "latency");
           (retry, Selector.Literal.Int 2);
         ])
  in
  match Normal.Selector.normalize (Selector.Row_filter filter) with
  | Normal.Selector.Row_filter { where } ->
      Alcotest.(check bool)
        "conditions retain typed literals in canonical order"
        true
        (where
        = [
            ("metric", Normal.Selector.String "latency");
            ("retry", Normal.Selector.Int 2);
            ("warmup", Normal.Selector.Bool true);
          ])
  | _ -> Alcotest.fail "expected row-filter normal form"

let () =
  Alcotest.run "monika_sugar selector normalization"
    [
      ( "normalization",
        [
          Alcotest.test_case "row filter" `Quick
            test_row_filter_normalization;
        ] );
    ]
