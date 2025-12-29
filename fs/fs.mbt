// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
pub(all) suberror FsError {
  NoPreopen
  PathOutsidePreopens
  InvalidPath
  InvalidPosition
  NotDirectory
  NotFile
  Unsupported
  UnexpectedEof
  Wasi(@types.ErrorCode)
} derive(Show, Eq)

///|
pub(all) struct Timestamp {
  seconds : Int64
  nanoseconds : Int
} derive(Show, Eq)

///|
pub(all) struct Stat {
  kind : FileKind
  size : Int64
  link_count : UInt64
  atime : Timestamp?
  mtime : Timestamp?
  ctime : Timestamp?
} derive(Show, Eq)

///|
pub(all) enum FileKind {
  Unknown
  Regular
  Directory
  SymLink
  Socket
  Pipe
  BlockDevice
  CharDevice
} derive(Show, Eq)

///|
pub(all) enum Mode {
  ReadOnly
  WriteOnly
  ReadWrite
} derive(Show, Eq)

///|
pub(all) enum SyncMode {
  NoSync
  Data
  Full
} derive(Show, Eq)

///|
struct File {
  desc : @types.Descriptor
  read_buf : @io.ReaderBuffer
  mut read_pos : UInt64
  mut write_pos : UInt64
  append : Bool
}

///|
struct Directory {
  desc : @types.Descriptor
}

///|
pub(all) struct DirEntry {
  name : String
  kind : FileKind
} derive(Show, Eq)

///|
pub(all) struct Preopen {
  dir : Directory
  path : String
}

fn normalize_path(path : StringView) -> String {
  let raw = path.to_string()
  if raw == "" {
    return ""
  }
  let is_abs = raw.has_prefix("/")
  let parts : Array[String] = []
  for part_view in raw.split("/") {
    let part = part_view.to_string()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 {
        ignore(parts.pop())
      }
      continue
    }
    parts.push(part)
  }
  let joined = parts.join("/")
  if is_abs {
    if joined == "" { "/" } else { "/" + joined }
  } else {
    joined
  }
}

fn path_flags(follow_symlink : Bool) -> @types.PathFlags {
  let mut flags = @types.PathFlags::default()
  if follow_symlink {
    flags = flags.set(@types.PathFlagsFlag::SYMLINK_FOLLOW)
  }
  flags
}

fn descriptor_flags(mode : Mode) -> @types.DescriptorFlags {
  let mut flags = @types.DescriptorFlags::default()
  match mode {
    ReadOnly => {
      flags = flags.set(@types.DescriptorFlagsFlag::READ)
    }
    WriteOnly => {
      flags = flags.set(@types.DescriptorFlagsFlag::WRITE)
    }
    ReadWrite => {
      flags = flags.set(@types.DescriptorFlagsFlag::READ)
      flags = flags.set(@types.DescriptorFlagsFlag::WRITE)
    }
  }
  flags
}

fn make_open_flags(create : Int?, truncate : Bool?, directory : Bool) -> @types.OpenFlags {
  let mut flags = @types.OpenFlags::default()
  if create is Some(_) {
    flags = flags.set(@types.OpenFlagsFlag::CREATE)
  }
  if truncate is Some(true) {
    flags = flags.set(@types.OpenFlagsFlag::TRUNCATE)
  }
  if directory {
    flags = flags.set(@types.OpenFlagsFlag::DIRECTORY)
  }
  flags
}

fn to_file_kind(kind : @types.DescriptorType) -> FileKind {
  match kind {
    UNKNOWN => Unknown
    REGULAR_FILE => Regular
    DIRECTORY => Directory
    SYMBOLIC_LINK => SymLink
    SOCKET => Socket
    FIFO => Pipe
    BLOCK_DEVICE => BlockDevice
    CHARACTER_DEVICE => CharDevice
  }
}

fn to_timestamp(value : @wallClock.Datetime) -> Timestamp {
  {
    seconds: value.seconds.reinterpret_as_int64(),
    nanoseconds: value.nanoseconds.reinterpret_as_int(),
  }
}

fn to_stat(stat : @types.DescriptorStat) -> Stat {
  {
    kind: to_file_kind(stat.type_),
    size: stat.size.reinterpret_as_int64(),
    link_count: stat.link_count,
    atime: stat.data_access_timestamp.map(to_timestamp),
    mtime: stat.data_modification_timestamp.map(to_timestamp),
    ctime: stat.status_change_timestamp.map(to_timestamp),
  }
}

fn timestamp_pair(value : @wallClock.Datetime?) -> (Int64, Int) {
  match value {
    None => (0L, 0)
    Some(ts) => {
      let converted = to_timestamp(ts)
      (converted.seconds, converted.nanoseconds)
    }
  }
}

fn timestamp_pair_from_stat(value : Timestamp?) -> (Int64, Int) {
  match value {
    None => (0L, 0)
    Some(ts) => (ts.seconds, ts.nanoseconds)
  }
}

fn[T] unwrap_fs(result : Result[T, @types.ErrorCode]) -> T raise FsError {
  match result {
    Ok(value) => value
    Err(err) => raise FsError::Wasi(err)
  }
}

fn resolve_path(path : StringView) -> (@types.Descriptor, String) raise FsError {
  let normalized = normalize_path(path)
  guard normalized != "" else { raise FsError::InvalidPath }
  let dirs = @preopens.get_directories()
  guard dirs.length() > 0 else { raise FsError::NoPreopen }

  let roots : Array[(@types.Descriptor, String)] = []
  let mut has_root = false
  for i = 0; i < dirs.length(); i = i + 1 {
    let (desc, root_raw) = dirs[i]
    let root = normalize_path(root_raw)
    if root == "/" {
      has_root = true
    }
    roots.push((desc, root))
  }

  if normalized.has_prefix("/") {
    guard has_root else { raise FsError::PathOutsidePreopens }
    let mut best_desc : @types.Descriptor? = None
    let mut best_root = ""
    for i = 0; i < roots.length(); i = i + 1 {
      let (desc, root) = roots[i]
      if normalized == root || normalized.has_prefix(root + "/") {
        if best_desc is None || root.length() > best_root.length() {
          best_desc = Some(desc)
          best_root = root
        }
      }
    }
    match best_desc {
      None => raise FsError::PathOutsidePreopens
      Some(desc) => {
        let view = normalized[:]
        let rel =
          if best_root == "/" {
            if normalized == "/" { "" } else { view.view(start_offset=1).to_string() }
          } else if normalized == best_root {
            ""
          } else {
            view.view(start_offset=best_root.length() + 1).to_string()
          }
        (desc, rel)
      }
    }
  } else {
    let mut best_desc : @types.Descriptor? = None
    let mut best_root = ""
    let mut best_rel = ""
    for i = 0; i < roots.length(); i = i + 1 {
      let (desc, root) = roots[i]
      if root == "/" {
        continue
      }
      let root_rel = root[:].view(start_offset=1).to_string()
      if normalized == root_rel || normalized.has_prefix(root_rel + "/") {
        if best_desc is None || root_rel.length() > best_root.length() {
          best_desc = Some(desc)
          best_root = root_rel
          if normalized == root_rel {
            best_rel = ""
          } else {
            best_rel = normalized[:].view(start_offset=root_rel.length() + 1).to_string()
          }
        }
      }
    }
    match best_desc {
      Some(desc) => (desc, best_rel)
      None =>
        if roots.length() == 1 {
          let (desc, _) = roots[0]
          (desc, normalized)
        } else {
          raise FsError::PathOutsidePreopens
        }
    }
  }
}

fn split_parent(path : StringView) -> (String, String) raise FsError {
  let normalized = normalize_path(path)
  guard normalized != "" && normalized != "/" else { raise FsError::InvalidPath }
  match normalized.rev_find("/") {
    None => ("", normalized)
    Some(0) => ("/", normalized[:].view(start_offset=1).to_string())
    Some(i) => (
      normalized[:].view(end_offset=i).to_string(),
      normalized[:].view(start_offset=i + 1).to_string(),
    )
  }
}

fn make_file(
  desc : @types.Descriptor,
  append : Bool,
) -> File {
  { desc, read_buf: @io.ReaderBuffer::new(), read_pos: 0, write_pos: 0, append }
}

fn ensure_file(desc : @types.Descriptor) -> Unit raise FsError {
  match unwrap_fs(desc.get_type()) {
    DIRECTORY => raise FsError::NotFile
    _ => ()
  }
}

fn ensure_dir(desc : @types.Descriptor) -> Unit raise FsError {
  match unwrap_fs(desc.get_type()) {
    DIRECTORY => ()
    _ => raise FsError::NotDirectory
  }
}

///|
pub fn preopens() -> Array[Preopen] {
  let result = []
  let dirs = @preopens.get_directories()
  for i = 0; i < dirs.length(); i = i + 1 {
    let (desc, path) = dirs[i]
    let dir = { desc, }
    result.push({ dir, path })
  }
  result
}

///|
pub fn open(
  path : StringView,
  mode~ : Mode,
  sync? : SyncMode = NoSync,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool,
) -> File raise FsError {
  let (desc, rel) = resolve_path(path)
  let flags = descriptor_flags(mode)
  let open_flags = make_open_flags(create, truncate, false)
  let file_desc =
    if rel == "" {
      desc
    } else {
      unwrap_fs(desc.open_at(@types.PathFlags::default(), rel, open_flags, flags))
    }
  ensure_file(file_desc)
  let file = make_file(file_desc, append)
  if append {
    let stat = unwrap_fs(file.desc.stat())
    file.write_pos = stat.size
  }
  if sync is Data {
    unwrap_fs(file.desc.sync_data())
  } else if sync is Full {
    unwrap_fs(file.desc.sync())
  }
  file
}

///|
pub fn create(
  path : StringView,
  permission~ : Int,
  sync? : SyncMode = NoSync,
) -> File raise FsError {
  ignore(permission)
  open(path, mode=ReadWrite, sync=sync, create=0, truncate=true)
}

///|
pub fn opendir(path : StringView) -> Directory raise FsError {
  let (desc, rel) = resolve_path(path)
  let open_flags = make_open_flags(None, None, true)
  let dir_desc =
    if rel == "" {
      desc
    } else {
      unwrap_fs(
        desc.open_at(
          @types.PathFlags::default(),
          rel,
          open_flags,
          descriptor_flags(ReadOnly),
        ),
      )
    }
  ensure_dir(dir_desc)
  { desc: dir_desc }
}

///|
pub fn exists(path : StringView) -> Bool {
  let result = stat(path, follow_symlink=true) catch { _ => return false }
  match result {
    None => false
    Some(_) => true
  }
}

///|
pub fn stat(
  path : StringView,
  follow_symlink? : Bool = true,
) -> Stat? raise FsError {
  let (desc, rel) = resolve_path(path)
  let flags = path_flags(follow_symlink)
  let result =
    if rel == "" {
      desc.stat()
    } else {
      desc.stat_at(flags, rel)
    }
  match result {
    Ok(value) => Some(to_stat(value))
    Err(@types.ErrorCode::NO_ENTRY) => None
    Err(@types.ErrorCode::NOT_DIRECTORY) => None
    Err(e) => raise FsError::Wasi(e)
  }
}

///|
pub fn kind(
  path : StringView,
  follow_symlink? : Bool = true,
) -> FileKind raise FsError {
  match stat(path, follow_symlink=follow_symlink) {
    None => raise FsError::InvalidPath
    Some(info) => info.kind
  }
}

///|
pub fn atime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) raise FsError {
  match stat(path, follow_symlink=follow_symlink) {
    None => raise FsError::InvalidPath
    Some(info) => timestamp_pair_from_stat(info.atime)
  }
}

///|
pub fn mtime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) raise FsError {
  match stat(path, follow_symlink=follow_symlink) {
    None => raise FsError::InvalidPath
    Some(info) => timestamp_pair_from_stat(info.mtime)
  }
}

///|
pub fn ctime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) raise FsError {
  match stat(path, follow_symlink=follow_symlink) {
    None => raise FsError::InvalidPath
    Some(info) => timestamp_pair_from_stat(info.ctime)
  }
}

///|
pub fn can_read(path : StringView) -> Bool {
  let result = open(path, mode=ReadOnly) catch { _ => return false }
  result.close()
  true
}

///|
pub fn can_write(path : StringView) -> Bool {
  let result = open(path, mode=WriteOnly) catch { _ => return false }
  result.close()
  true
}

///|
pub fn can_execute(path : StringView) -> Bool {
  ignore(path)
  false
}

///|
pub fn chmod(path : StringView, mode : Int) -> Unit raise FsError {
  ignore(path)
  ignore(mode)
  raise FsError::Unsupported
}

///|
pub fn mkdir(path : StringView, permission~ : Int) -> Unit raise FsError {
  ignore(permission)
  let (desc, rel) = resolve_path(path)
  guard rel != "" else { raise FsError::InvalidPath }
  unwrap_fs(desc.create_directory_at(rel))
}

///|
pub fn remove(path : StringView) -> Unit raise FsError {
  let (desc, rel) = resolve_path(path)
  guard rel != "" else { raise FsError::InvalidPath }
  match kind(path, follow_symlink=false) {
    Directory => unwrap_fs(desc.remove_directory_at(rel))
    _ => unwrap_fs(desc.unlink_file_at(rel))
  }
}

///|
pub fn rmdir(
  path : StringView,
  recursive? : Bool = false,
) -> Unit raise FsError {
  let (desc, rel) = resolve_path(path)
  guard rel != "" else { raise FsError::InvalidPath }
  if recursive {
    let entries = read_dir_entries(path, include_hidden=true, include_special=false)
    for entry in entries {
      let child = join_path(path.to_string(), entry.name)
      if entry.kind is Directory {
        rmdir(child, recursive=true)
      } else {
        remove(child)
      }
    }
  }
  unwrap_fs(desc.remove_directory_at(rel))
}

///|
pub fn symlink(
  target~ : StringView,
  path : StringView,
) -> Unit raise FsError {
  let (parent, name) = split_parent(path)
  let (desc, rel) = resolve_path(parent)
  let prefix = if rel == "" { name } else { rel + "/" + name }
  unwrap_fs(desc.symlink_at(target.to_string(), prefix))
}

///|
pub async fn read_file(
  path : StringView,
  sync_timestamp? : Bool = false,
) -> &@io.Data raise {
  let file = open(path, mode=ReadOnly)
  defer file.close()
  let data = file.read_all()
  if sync_timestamp {
    file.sync(only_data=true)
  }
  data
}

///|
#deprecated
pub async fn read_text_file(
  path : StringView,
  encoding~ : @io.Encoding = UTF8,
) -> String raise {
  guard encoding is UTF8
  read_file(path).text()
}

///|
pub async fn write_file(
  path : StringView,
  data : &@io.Data,
  sync? : SyncMode = NoSync,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool,
) -> Unit raise {
  let file = open(
    path,
    mode=WriteOnly,
    sync=sync,
    append=append,
    create?=create,
    truncate?=truncate,
  )
  defer file.close()
  file.write(data)
  if sync is Data {
    file.sync(only_data=true)
  } else if sync is Full {
    file.sync(only_data=false)
  }
}

///|
#deprecated
pub async fn write_text_file(
  path : StringView,
  data : String,
  encoding~ : @io.Encoding = UTF8,
  sync? : SyncMode = NoSync,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool,
) -> Unit raise {
  guard encoding is UTF8
  write_file(
    path,
    data,
    sync=sync,
    append=append,
    create?=create,
    truncate?=truncate,
  )
}

///|
pub fn readdir(
  path : StringView,
  include_hidden? : Bool = false,
  include_special? : Bool = false,
  sort? : Bool = false,
) -> Array[String] raise FsError {
  let entries = read_dir_entries(path, include_hidden=include_hidden, include_special=include_special)
  let names = entries.map(e => e.name)
  if sort {
    names.sort()
  }
  names
}

///|
pub fn read_dir_entries(
  path : StringView,
  include_hidden? : Bool = false,
  include_special? : Bool = false,
) -> Array[DirEntry] raise FsError {
  let dir = opendir(path)
  defer dir.close()
  dir.read_entries(include_hidden=include_hidden, include_special=include_special)
}

///|
pub fn realpath(path : StringView) -> String raise FsError {
  let normalized = normalize_path(path)
  if normalized.has_prefix("/") {
    normalized
  } else {
    let dirs = @preopens.get_directories()
    guard dirs.length() > 0 else { raise FsError::NoPreopen }
    let (_, root_raw) = dirs[0]
    let root = normalize_path(root_raw[:])
    if root == "/" {
      "/" + normalized
    } else if normalized == "" {
      root
    } else {
      root + "/" + normalized
    }
  }
}

///|
pub async fn walk(
  path : StringView,
  f : async (String, Array[String]) -> Unit,
  max_concurrency? : Int = 8,
  allow_failure? : Bool = false,
) -> Unit raise {
  let limit = if max_concurrency <= 0 { 1 } else { max_concurrency }
  let sem = @semaphore.Semaphore::new(limit)
  @demo.with_task_group(fn(tg) {
    async fn visit(dir_path : String) -> Unit {
      sem.acquire()
      defer sem.release()
      let entries = read_dir_entries(dir_path[:], include_hidden=true, include_special=false)
      let names = entries.map(e => e.name)
      f(dir_path, names)
      for entry in entries {
        if entry.kind is Directory {
          let child = join_path(dir_path, entry.name)
          tg.spawn_bg(() => visit(child), allow_failure=allow_failure)
        }
      }
    }
    tg.spawn_bg(() => visit(path.to_string()), allow_failure=allow_failure)
    ()
  })
}

///|
pub fn Directory::close(self : Directory) -> Unit {
  self.desc.drop()
}

///|
pub fn Directory::read_entries(
  self : Directory,
  include_hidden? : Bool = false,
  include_special? : Bool = false,
) -> Array[DirEntry] raise FsError {
  let stream = unwrap_fs(self.desc.read_directory())
  defer stream.drop()
  let entries : Array[DirEntry] = []
  for {
    let next = unwrap_fs(stream.read_directory_entry())
    match next {
      None => break
      Some(entry) => {
        let name = entry.name
        let is_special = name == "." || name == ".."
        let is_hidden = name.has_prefix(".")
        if not(include_special) && is_special {
          continue
        }
        if not(include_hidden) && is_hidden && not(is_special) {
          continue
        }
        entries.push({ name, kind: to_file_kind(entry.type_) })
      }
    }
  }
  entries
}

///|
pub fn Directory::read_all(
  self : Directory,
  include_hidden? : Bool = false,
  include_special? : Bool = false,
) -> Array[String] raise FsError {
  self.read_entries(include_hidden=include_hidden, include_special=include_special)
    .map(e => e.name)
}

///|
pub fn File::close(self : File) -> Unit {
  self.desc.drop()
}

///|
pub fn File::as_dir(self : File) -> Directory raise FsError {
  ensure_dir(self.desc)
  { desc: self.desc }
}

///|
pub fn File::size(self : File) -> Int64 {
  match self.desc.stat() {
    Ok(stat) => stat.size.reinterpret_as_int64()
    Err(_) => 0L
  }
}

///|
pub fn File::sync(self : File, only_data? : Bool = false) -> Unit {
  if only_data {
    ignore(self.desc.sync_data())
  } else {
    ignore(self.desc.sync())
  }
}

///|
pub fn File::atime(self : File) -> (Int64, Int) {
  match self.desc.stat() {
    Ok(stat) => timestamp_pair(stat.data_access_timestamp)
    Err(_) => (0L, 0)
  }
}

///|
pub fn File::mtime(self : File) -> (Int64, Int) {
  match self.desc.stat() {
    Ok(stat) => timestamp_pair(stat.data_modification_timestamp)
    Err(_) => (0L, 0)
  }
}

///|
pub fn File::ctime(self : File) -> (Int64, Int) {
  match self.desc.stat() {
    Ok(stat) => timestamp_pair(stat.status_change_timestamp)
    Err(_) => (0L, 0)
  }
}

///|
pub fn File::kind(self : File) -> FileKind {
  match self.desc.get_type() {
    Ok(kind) => to_file_kind(kind)
    Err(_) => Unknown
  }
}

///|
pub fn File::read_at(
  self : File,
  buf : FixedArray[Byte],
  position~ : Int64,
  offset? : Int = 0,
  len? : Int,
) -> Int raise FsError {
  guard position >= 0 else { raise FsError::InvalidPosition }
  guard offset >= 0 && offset <= buf.length() else { raise FsError::InvalidPosition }
  let len = if len is Some(l) { l } else { buf.length() - offset }
  guard len >= 0 else { raise FsError::InvalidPosition }
  let (data, _) =
    unwrap_fs(self.desc.read(len.to_uint64(), position.reinterpret_as_uint64()))
  let copied = @cmp.minimum(len, data.length())
  data.blit_to(buf, len=copied, dst_offset=offset)
  copied
}

///|
pub fn File::read_exactly_at(
  self : File,
  len : Int,
  position~ : Int64,
) -> Bytes raise FsError {
  guard len >= 0 else { raise FsError::InvalidPosition }
  let buf = FixedArray::make(len, b'\x00')
  let n = self.read_at(buf, position~, offset=0, len=len)
  if n < len {
    raise FsError::UnexpectedEof
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
pub fn File::write_at(
  self : File,
  data : BytesView,
  position~ : Int64,
) -> Unit raise FsError {
  guard position >= 0 else { raise FsError::InvalidPosition }
  let mut offset = 0
  let total = data.length()
  let mut pos = position.reinterpret_as_uint64()
  while offset < total {
    let view = data[offset:]
    let chunk = view.to_fixedarray()
    let written = unwrap_fs(self.desc.write(chunk, pos)).to_int()
    if written <= 0 {
      raise FsError::UnexpectedEof
    }
    offset += written
    pos += written.to_uint64()
  }
}

///|
pub impl @io.Reader for File with _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Reader for File with _direct_read(self, buf, offset~, max_len~) {
  let n = self.read_at(
    buf,
    position=self.read_pos.reinterpret_as_int64(),
    offset=offset,
    len=max_len,
  ) catch {
    _ => 0
  }
  self.read_pos += n.to_uint64()
  n
}

///|
pub impl @io.Writer for File with write_once(self, buf, offset~, len~) {
  let len = if len < 0 { 0 } else { len }
  if len == 0 {
    return 0
  }
  if offset < 0 || offset + len > buf.length() {
    return 0
  }
  let view = buf[offset:offset + len]
  let position =
    if self.append {
      match self.desc.stat() {
        Ok(stat) => stat.size.reinterpret_as_int64()
        Err(_) => self.write_pos.reinterpret_as_int64()
      }
    } else {
      self.write_pos.reinterpret_as_int64()
    }
  self.write_at(view, position~) catch { _ => return 0 }
  if not(self.append) {
    self.write_pos += len.to_uint64()
  }
  len
}

fn join_path(base : String, name : String) -> String {
  if base == "" {
    name
  } else if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}
