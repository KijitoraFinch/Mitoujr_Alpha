type 'a t = { head : 'a; tail : 'a list }

let make head tail = { head; tail }
let singleton head = { head; tail = [] }
let of_list = function [] -> None | head :: tail -> Some { head; tail }
let head value = value.head
let tail value = value.tail
let to_list value = value.head :: value.tail
let length value = 1 + List.length value.tail
let map function_ value =
  { head = function_ value.head; tail = List.map function_ value.tail }

let exists predicate value =
  predicate value.head || List.exists predicate value.tail

let iter function_ value =
  function_ value.head;
  List.iter function_ value.tail
