#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int monika_posix_fd(value descriptor)
{
  return Int_val(descriptor);
}

static value monika_posix_descriptor(int descriptor)
{
  return Val_int(descriptor);
}

static const char *monika_posix_segment(value segment, const char *operation)
{
  const char *name = String_val(segment);
  mlsize_t length = caml_string_length(segment);

  if (length == 0 || strlen(name) != length || strchr(name, '/') != NULL ||
      (length == 1 && name[0] == '.') ||
      (length == 2 && name[0] == '.' && name[1] == '.')) {
    caml_invalid_argument(operation);
  }
  return name;
}

static int monika_open_flags(int flags)
{
  return flags | O_CLOEXEC | O_NOFOLLOW;
}
#endif

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <limits.h>
#include <stddef.h>
#include <wchar.h>

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

#ifndef FILE_OPEN_REPARSE_POINT
#define FILE_OPEN_REPARSE_POINT 0x00200000
#endif
#ifndef FILE_DIRECTORY_FILE
#define FILE_DIRECTORY_FILE 0x00000001
#endif
#ifndef FILE_SYNCHRONOUS_IO_NONALERT
#define FILE_SYNCHRONOUS_IO_NONALERT 0x00000020
#endif
#ifndef FILE_NON_DIRECTORY_FILE
#define FILE_NON_DIRECTORY_FILE 0x00000040
#endif
#ifndef FILE_OPEN
#define FILE_OPEN 0x00000001
#endif
#ifndef FILE_CREATE
#define FILE_CREATE 0x00000002
#endif
#ifndef NT_SUCCESS
#define NT_SUCCESS(status) (((NTSTATUS)(status)) >= 0)
#endif

typedef NTSTATUS(NTAPI *monika_nt_create_file_fn)(
    PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES, PIO_STATUS_BLOCK, PLARGE_INTEGER,
    ULONG, ULONG, ULONG, ULONG, PVOID, ULONG);
typedef NTSTATUS(NTAPI *monika_nt_set_information_file_fn)(
    HANDLE, PIO_STATUS_BLOCK, PVOID, ULONG, FILE_INFORMATION_CLASS);
typedef ULONG(WINAPI *monika_rtl_nt_status_to_dos_error_fn)(NTSTATUS);

typedef struct monika_file_rename_information {
  BOOLEAN ReplaceIfExists;
  HANDLE RootDirectory;
  ULONG FileNameLength;
  WCHAR FileName[1];
} monika_file_rename_information;

typedef struct monika_file_disposition_information {
  BOOLEAN DeleteFile;
} monika_file_disposition_information;

static FARPROC monika_ntdll_function(const char *name)
{
  HMODULE module = GetModuleHandleW(L"ntdll.dll");
  FARPROC function;
  if (module == NULL) caml_failwith("ntdll.dll is unavailable");
  function = GetProcAddress(module, name);
  if (function == NULL) caml_failwith("required ntdll function is unavailable");
  return function;
}

static monika_nt_create_file_fn monika_nt_create_file(void)
{
  FARPROC raw = monika_ntdll_function("NtCreateFile");
  monika_nt_create_file_fn function;
  memcpy(&function, &raw, sizeof(function));
  return function;
}

static monika_nt_set_information_file_fn monika_nt_set_information_file(void)
{
  FARPROC raw = monika_ntdll_function("NtSetInformationFile");
  monika_nt_set_information_file_fn function;
  memcpy(&function, &raw, sizeof(function));
  return function;
}

CAMLnoret static void monika_windows_nt_error(NTSTATUS status,
                                              const char *operation,
                                              value argument)
{
  FARPROC raw = monika_ntdll_function("RtlNtStatusToDosError");
  monika_rtl_nt_status_to_dos_error_fn convert;
  memcpy(&convert, &raw, sizeof(convert));
  win32_maperr(convert(status));
  uerror(operation, argument);
}

CAMLnoret static void monika_windows_last_error(const char *operation,
                                                value argument)
{
  win32_maperr(GetLastError());
  uerror(operation, argument);
}

static HANDLE monika_windows_handle(value descriptor)
{
  if (Descr_kind_val(descriptor) != KIND_HANDLE)
    caml_invalid_argument("filesystem adapter requires a file handle");
  return Handle_val(descriptor);
}

static wchar_t *monika_windows_segment(value segment, const char *operation,
                                       USHORT *byte_length)
{
  wchar_t *wide = monika_utf8_to_wide(segment);
  size_t length = wcslen(wide);
  size_t index;
  if (length == 0 || length > USHRT_MAX / sizeof(wchar_t) ||
      (length == 1 && wide[0] == L'.') ||
      (length == 2 && wide[0] == L'.' && wide[1] == L'.')) {
    caml_stat_free(wide);
    caml_invalid_argument(operation);
  }
  for (index = 0; index < length; index++) {
    if (wide[index] == L'/' || wide[index] == L'\\') {
      caml_stat_free(wide);
      caml_invalid_argument(operation);
    }
  }
  *byte_length = (USHORT)(length * sizeof(wchar_t));
  return wide;
}

static HANDLE monika_windows_open_relative(value directory, value segment,
                                           ACCESS_MASK access,
                                           ULONG disposition, ULONG options,
                                           const char *operation)
{
  USHORT name_length;
  wchar_t *name = monika_windows_segment(segment, operation, &name_length);
  UNICODE_STRING unicode_name;
  OBJECT_ATTRIBUTES attributes;
  IO_STATUS_BLOCK io_status;
  HANDLE result = INVALID_HANDLE_VALUE;
  NTSTATUS status;

  unicode_name.Length = name_length;
  unicode_name.MaximumLength = name_length;
  unicode_name.Buffer = name;
  attributes.Length = sizeof(attributes);
  attributes.RootDirectory = monika_windows_handle(directory);
  attributes.ObjectName = &unicode_name;
  attributes.Attributes = 0;
  attributes.SecurityDescriptor = NULL;
  attributes.SecurityQualityOfService = NULL;
  status = monika_nt_create_file()(
      &result, access, &attributes, &io_status, NULL, FILE_ATTRIBUTE_NORMAL,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, disposition,
      options | FILE_OPEN_REPARSE_POINT | FILE_SYNCHRONOUS_IO_NONALERT, NULL,
      0);
  caml_stat_free(name);
  if (!NT_SUCCESS(status)) monika_windows_nt_error(status, operation, segment);
  return result;
}

static DWORD monika_windows_attributes(HANDLE handle, value argument)
{
  FILE_ATTRIBUTE_TAG_INFO information;
  if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &information,
                                    sizeof(information))) {
    DWORD error = GetLastError();
    CloseHandle(handle);
    SetLastError(error);
    monika_windows_last_error("GetFileInformationByHandleEx", argument);
  }
  return information.FileAttributes;
}

static void monika_windows_reject_reparse(HANDLE handle, value argument)
{
  if ((monika_windows_attributes(handle, argument) &
       FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    CloseHandle(handle);
    errno = ELOOP;
    uerror("reparse-point", argument);
  }
}

static char *monika_wide_to_utf8(const wchar_t *input, int input_length)
{
  int output_length =
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input, input_length,
                          NULL, 0, NULL, NULL);
  char *output;
  if (output_length <= 0) return NULL;
  output = malloc((size_t)output_length + 1);
  if (output == NULL) return NULL;
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input, input_length,
                          output, output_length, NULL, NULL) != output_length) {
    free(output);
    return NULL;
  }
  output[output_length] = '\0';
  return output;
}
#endif

CAMLprim value monika_sugar_open_dir_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  (void)directory;
  (void)segment;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *name = String_val(segment);
  int base = AT_FDCWD;
  int descriptor;

  if (name[0] != '/') {
    name = monika_posix_segment(segment, "open_dir_at");
    base = monika_posix_fd(directory);
  } else if (strlen(name) != caml_string_length(segment)) {
    caml_invalid_argument("open_root");
  }

  descriptor =
      openat(base, name, monika_open_flags(O_RDONLY | O_DIRECTORY));
  if (descriptor < 0) {
    uerror("openat(directory)", segment);
  }
  CAMLreturn(monika_posix_descriptor(descriptor));
#endif
}

CAMLprim value monika_sugar_open_regular_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  (void)directory;
  (void)segment;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *name = monika_posix_segment(segment, "open_regular_at");
  int descriptor =
      openat(monika_posix_fd(directory), name, monika_open_flags(O_RDONLY));
  struct stat status;

  if (descriptor < 0) {
    uerror("openat(file)", segment);
  }
  if (fstat(descriptor, &status) != 0) {
    int saved_errno = errno;
    close(descriptor);
    errno = saved_errno;
    uerror("fstat", segment);
  }
  if (!S_ISREG(status.st_mode)) {
    close(descriptor);
    errno = EINVAL;
    uerror("openat(regular-file)", segment);
  }
  CAMLreturn(monika_posix_descriptor(descriptor));
#endif
}

CAMLprim value monika_sugar_create_exclusive_at(value directory, value segment,
                                                 value mode)
{
  CAMLparam3(directory, segment, mode);
#ifdef _WIN32
  (void)directory;
  (void)segment;
  (void)mode;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *name = monika_posix_segment(segment, "create_exclusive_at");
  int descriptor =
      openat(monika_posix_fd(directory), name,
             monika_open_flags(O_CREAT | O_EXCL | O_RDWR), Int_val(mode));
  if (descriptor < 0) {
    uerror("openat(temporary-file)", segment);
  }
  CAMLreturn(monika_posix_descriptor(descriptor));
#endif
}

CAMLprim value monika_sugar_entry_kind_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  (void)directory;
  (void)segment;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *name = monika_posix_segment(segment, "entry_kind_at");
  struct stat status;
  int kind;

  if (fstatat(monika_posix_fd(directory), name, &status,
              AT_SYMLINK_NOFOLLOW) != 0) {
    uerror("fstatat", segment);
  }
  if (S_ISREG(status.st_mode))
    kind = 0;
  else if (S_ISDIR(status.st_mode))
    kind = 1;
  else if (S_ISLNK(status.st_mode))
    kind = 2;
  else
    kind = 3;
  CAMLreturn(Val_int(kind));
#endif
}

CAMLprim value monika_sugar_entries_at(value directory)
{
  CAMLparam1(directory);
  CAMLlocal2(result, item);
#ifdef _WIN32
  (void)directory;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  int copied = dup(monika_posix_fd(directory));
  DIR *stream;
  struct dirent *entry;
  char **names = NULL;
  size_t count = 0;
  size_t capacity = 0;
  size_t index;

  if (copied < 0) {
    uerror("dup(directory)", Nothing);
  }
  stream = fdopendir(copied);
  if (stream == NULL) {
    int saved_errno = errno;
    close(copied);
    errno = saved_errno;
    uerror("fdopendir", Nothing);
  }

  errno = 0;
  while ((entry = readdir(stream)) != NULL) {
    char *copy;
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
      continue;
    if (count == capacity) {
      size_t next_capacity = capacity == 0 ? 16 : capacity * 2;
      char **next_names = realloc(names, next_capacity * sizeof(char *));
      if (next_names == NULL) {
        errno = ENOMEM;
        goto error;
      }
      names = next_names;
      capacity = next_capacity;
    }
    copy = strdup(entry->d_name);
    if (copy == NULL) {
      errno = ENOMEM;
      goto error;
    }
    names[count++] = copy;
  }
  if (errno != 0) {
    goto error;
  }
  if (closedir(stream) != 0) {
    stream = NULL;
    goto error;
  }
  stream = NULL;

  result = caml_alloc(count, 0);
  for (index = 0; index < count; index++) {
    item = caml_copy_string(names[index]);
    Store_field(result, index, item);
    free(names[index]);
  }
  free(names);
  CAMLreturn(result);

error:
  {
    int saved_errno = errno;
    for (index = 0; index < count; index++) free(names[index]);
    free(names);
    if (stream != NULL) closedir(stream);
    errno = saved_errno;
    uerror("readdir", Nothing);
  }
#endif
}

CAMLprim value monika_sugar_rename_at(value source_directory,
                                      value source_segment,
                                      value target_directory,
                                      value target_segment)
{
  CAMLparam4(source_directory, source_segment, target_directory,
             target_segment);
#ifdef _WIN32
  (void)source_directory;
  (void)source_segment;
  (void)target_directory;
  (void)target_segment;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *source = monika_posix_segment(source_segment, "rename_at");
  const char *target = monika_posix_segment(target_segment, "rename_at");
  if (renameat(monika_posix_fd(source_directory), source,
               monika_posix_fd(target_directory), target) != 0) {
    uerror("renameat", target_segment);
  }
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_unlink_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  (void)directory;
  (void)segment;
  caml_failwith("POSIX filesystem adapter is unavailable on Windows");
  CAMLreturn(Val_unit);
#else
  const char *name = monika_posix_segment(segment, "unlink_at");
  if (unlinkat(monika_posix_fd(directory), name, 0) != 0) {
    uerror("unlinkat", segment);
  }
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_open_root(value path)
{
  CAMLparam1(path);
#ifdef _WIN32
  wchar_t *wide = monika_utf8_to_wide(path);
  HANDLE handle =
      CreateFileW(wide,
                  FILE_LIST_DIRECTORY | FILE_TRAVERSE | FILE_READ_ATTRIBUTES |
                      SYNCHRONIZE,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                  OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  DWORD attributes;
  caml_stat_free(wide);
  if (handle == INVALID_HANDLE_VALUE)
    monika_windows_last_error("CreateFileW(workspace)", path);
  attributes = monika_windows_attributes(handle, path);
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    CloseHandle(handle);
    win32_maperr(ERROR_DIRECTORY);
    uerror("CreateFileW(workspace-directory)", path);
  }
  CAMLreturn(win_alloc_handle(handle));
#else
  (void)path;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_open_dir_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  HANDLE handle = monika_windows_open_relative(
      directory, segment,
      FILE_LIST_DIRECTORY | FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
      FILE_OPEN, FILE_DIRECTORY_FILE, "NtCreateFile(directory)");
  DWORD attributes = monika_windows_attributes(handle, segment);
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    CloseHandle(handle);
    errno = ELOOP;
    uerror("reparse-point", segment);
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    CloseHandle(handle);
    win32_maperr(ERROR_DIRECTORY);
    uerror("NtCreateFile(directory)", segment);
  }
  CAMLreturn(win_alloc_handle(handle));
#else
  (void)directory;
  (void)segment;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_open_regular_at(value directory,
                                                     value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  HANDLE handle = monika_windows_open_relative(
      directory, segment, GENERIC_READ | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
      FILE_OPEN, FILE_NON_DIRECTORY_FILE, "NtCreateFile(regular-file)");
  DWORD attributes = monika_windows_attributes(handle, segment);
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    CloseHandle(handle);
    errno = ELOOP;
    uerror("reparse-point", segment);
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      GetFileType(handle) != FILE_TYPE_DISK) {
    CloseHandle(handle);
    win32_maperr(ERROR_INVALID_DATA);
    uerror("NtCreateFile(regular-file)", segment);
  }
  CAMLreturn(win_alloc_handle(handle));
#else
  (void)directory;
  (void)segment;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_create_exclusive_at(value directory,
                                                         value segment,
                                                         value mode)
{
  CAMLparam3(directory, segment, mode);
#ifdef _WIN32
  HANDLE handle;
  (void)mode;
  handle = monika_windows_open_relative(
      directory, segment,
      GENERIC_READ | GENERIC_WRITE | DELETE | FILE_READ_ATTRIBUTES |
          SYNCHRONIZE,
      FILE_CREATE, FILE_NON_DIRECTORY_FILE, "NtCreateFile(temporary-file)");
  CAMLreturn(win_alloc_handle(handle));
#else
  (void)directory;
  (void)segment;
  (void)mode;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_entry_kind_at(value directory,
                                                   value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  HANDLE handle = monika_windows_open_relative(
      directory, segment, FILE_READ_ATTRIBUTES | SYNCHRONIZE, FILE_OPEN, 0,
      "NtCreateFile(entry)");
  DWORD attributes = monika_windows_attributes(handle, segment);
  DWORD file_type = GetFileType(handle);
  int kind;
  CloseHandle(handle);
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    kind = 2;
  else if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    kind = 1;
  else if (file_type == FILE_TYPE_DISK)
    kind = 0;
  else
    kind = 3;
  CAMLreturn(Val_int(kind));
#else
  (void)directory;
  (void)segment;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_entries_at(value directory)
{
  CAMLparam1(directory);
  CAMLlocal2(result, item);
#ifdef _WIN32
  HANDLE copied = ReOpenFile(
      monika_windows_handle(directory), FILE_LIST_DIRECTORY | SYNCHRONIZE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT);
  unsigned char *buffer = NULL;
  char **names = NULL;
  size_t count = 0;
  size_t capacity = 0;
  size_t index;
  BOOL restart = TRUE;
  DWORD saved_error = ERROR_SUCCESS;

  if (copied == INVALID_HANDLE_VALUE)
    monika_windows_last_error("ReOpenFile(directory)", Nothing);
  buffer = malloc(65536);
  if (buffer == NULL) {
    saved_error = ERROR_NOT_ENOUGH_MEMORY;
    goto error;
  }
  for (;;) {
    FILE_INFO_BY_HANDLE_CLASS information_class =
        restart ? FileIdBothDirectoryRestartInfo : FileIdBothDirectoryInfo;
    FILE_ID_BOTH_DIR_INFO *entry;
    if (!GetFileInformationByHandleEx(copied, information_class, buffer,
                                      65536)) {
      saved_error = GetLastError();
      if (saved_error == ERROR_NO_MORE_FILES ||
          saved_error == ERROR_HANDLE_EOF)
        break;
      goto error;
    }
    restart = FALSE;
    entry = (FILE_ID_BOTH_DIR_INFO *)buffer;
    for (;;) {
      int wide_length = (int)(entry->FileNameLength / sizeof(wchar_t));
      BOOL dot = wide_length == 1 && entry->FileName[0] == L'.';
      BOOL dot_dot = wide_length == 2 && entry->FileName[0] == L'.' &&
                     entry->FileName[1] == L'.';
      if (!dot && !dot_dot) {
        char *name = monika_wide_to_utf8(entry->FileName, wide_length);
        if (name == NULL) {
          saved_error = ERROR_NO_UNICODE_TRANSLATION;
          goto error;
        }
        if (count == capacity) {
          size_t next_capacity = capacity == 0 ? 16 : capacity * 2;
          char **next_names =
              realloc(names, next_capacity * sizeof(char *));
          if (next_names == NULL) {
            free(name);
            saved_error = ERROR_NOT_ENOUGH_MEMORY;
            goto error;
          }
          names = next_names;
          capacity = next_capacity;
        }
        names[count++] = name;
      }
      if (entry->NextEntryOffset == 0) break;
      entry = (FILE_ID_BOTH_DIR_INFO *)
          ((unsigned char *)entry + entry->NextEntryOffset);
    }
  }
  CloseHandle(copied);
  free(buffer);
  result = caml_alloc(count, 0);
  for (index = 0; index < count; index++) {
    item = caml_copy_string(names[index]);
    Store_field(result, index, item);
    free(names[index]);
  }
  free(names);
  CAMLreturn(result);

error:
  for (index = 0; index < count; index++) free(names[index]);
  free(names);
  free(buffer);
  CloseHandle(copied);
  SetLastError(saved_error);
  monika_windows_last_error("GetFileInformationByHandleEx(directory)", Nothing);
#else
  (void)directory;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_rename_at(value source_directory,
                                              value source_segment,
                                              value target_directory,
                                              value target_segment)
{
  CAMLparam4(source_directory, source_segment, target_directory,
             target_segment);
#ifdef _WIN32
  USHORT target_length;
  wchar_t *target_test =
      monika_windows_segment(target_segment, "NtSetInformationFile(rename)",
                             &target_length);
  HANDLE source;
  wchar_t *target;
  size_t information_size;
  monika_file_rename_information *information;
  IO_STATUS_BLOCK io_status;
  NTSTATUS status;
  caml_stat_free(target_test);
  source = monika_windows_open_relative(
      source_directory, source_segment,
      DELETE | FILE_READ_ATTRIBUTES | SYNCHRONIZE, FILE_OPEN,
      FILE_NON_DIRECTORY_FILE, "NtCreateFile(rename-source)");
  monika_windows_reject_reparse(source, source_segment);
  target = monika_windows_segment(target_segment,
                                  "NtSetInformationFile(rename)",
                                  &target_length);
  information_size =
      offsetof(monika_file_rename_information, FileName) + target_length;
  information = malloc(information_size);
  if (information == NULL) {
    caml_stat_free(target);
    CloseHandle(source);
    win32_maperr(ERROR_NOT_ENOUGH_MEMORY);
    uerror("NtSetInformationFile(rename)", target_segment);
  }
  information->ReplaceIfExists = TRUE;
  information->RootDirectory = monika_windows_handle(target_directory);
  information->FileNameLength = target_length;
  memcpy(information->FileName, target, target_length);
  caml_stat_free(target);
  status = monika_nt_set_information_file()(
      source, &io_status, information, (ULONG)information_size,
      (FILE_INFORMATION_CLASS)10);
  free(information);
  CloseHandle(source);
  if (!NT_SUCCESS(status))
    monika_windows_nt_error(status, "NtSetInformationFile(rename)",
                            target_segment);
  CAMLreturn(Val_unit);
#else
  (void)source_directory;
  (void)source_segment;
  (void)target_directory;
  (void)target_segment;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value monika_sugar_windows_unlink_at(value directory, value segment)
{
  CAMLparam2(directory, segment);
#ifdef _WIN32
  HANDLE handle = monika_windows_open_relative(
      directory, segment, DELETE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
      FILE_OPEN, FILE_NON_DIRECTORY_FILE, "NtCreateFile(unlink)");
  monika_file_disposition_information information;
  IO_STATUS_BLOCK io_status;
  NTSTATUS status;
  monika_windows_reject_reparse(handle, segment);
  information.DeleteFile = TRUE;
  status = monika_nt_set_information_file()(
      handle, &io_status, &information, sizeof(information),
      (FILE_INFORMATION_CLASS)13);
  CloseHandle(handle);
  if (!NT_SUCCESS(status))
    monika_windows_nt_error(status, "NtSetInformationFile(unlink)", segment);
  CAMLreturn(Val_unit);
#else
  (void)directory;
  (void)segment;
  caml_failwith("Windows filesystem adapter is unavailable");
  CAMLreturn(Val_unit);
#endif
}
