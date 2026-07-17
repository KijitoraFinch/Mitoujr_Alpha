let is_valid value =
  let rec loop offset =
    if offset = String.length value then true
    else
      let decoded = String.get_utf_8_uchar value offset in
      if not (Uchar.utf_decode_is_valid decoded) then false
      else loop (offset + Uchar.utf_decode_length decoded)
  in
  loop 0
