#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static wchar_t *monika_utf8_to_wide(value path)
{
  const char *input = String_val(path);
  int input_length = caml_string_length(path);
  int wide_length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input, input_length,
                          NULL, 0);
  wchar_t *wide;

  if (wide_length <= 0) {
    caml_failwith("invalid UTF-8 Windows path");
  }

  wide = caml_stat_alloc((wide_length + 1) * sizeof(wchar_t));
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input, input_length,
                          wide, wide_length) != wide_length) {
    caml_stat_free(wide);
    caml_failwith("invalid UTF-8 Windows path");
  }
  wide[wide_length] = L'\0';
  return wide;
}
#endif

CAMLprim value monika_sugar_replace_file(value replacement, value target)
{
  CAMLparam2(replacement, target);
#ifdef _WIN32
  wchar_t *replacement_w = monika_utf8_to_wide(replacement);
  wchar_t *target_w = monika_utf8_to_wide(target);
  BOOL ok =
      ReplaceFileW(target_w, replacement_w, NULL, REPLACEFILE_WRITE_THROUGH,
                   NULL, NULL);
  caml_stat_free(replacement_w);
  caml_stat_free(target_w);
  if (!ok) {
    caml_failwith("ReplaceFileW failed");
  }
#else
  if (rename(String_val(replacement), String_val(target)) != 0) {
    uerror("rename", target);
  }
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value monika_sugar_is_reparse_point(value path)
{
  CAMLparam1(path);
#ifdef _WIN32
  wchar_t *path_w = monika_utf8_to_wide(path);
  DWORD attributes = GetFileAttributesW(path_w);
  caml_stat_free(path_w);
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    caml_failwith("GetFileAttributesW failed");
  }
  CAMLreturn(Val_bool((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0));
#else
  (void)path;
  CAMLreturn(Val_false);
#endif
}
