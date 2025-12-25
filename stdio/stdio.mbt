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
struct Input {
  io : @streams.InputStream
  read_buf : @io.ReaderBuffer
}

///|
pub impl @io.Reader for Input with _direct_read(self, buf, offset~, max_len~) {
  let read = self.io.read(max_len.to_uint64()).unwrap_or_error() catch {
      @streams.StreamError::Closed => return 0
      e => raise e
    }
  read.blit_to(buf, len=read.length(), dst_offset=offset)
  read.length()
}

///|
pub impl @io.Reader for Input with _get_internal_buffer(self) {
  self.read_buf
}

///|
struct Output(@streams.OutputStream)

///|
pub impl @io.Writer for Output with write_once(self, buf, offset~, len~) {
  let mut can_write = self.0.check_write().unwrap_or_error()
  if can_write == 0 {
    @ev.suspend_for_pollable(self.0.subscribe())
    can_write = self.0.check_write().unwrap_or_error()
  }
  let buffer = FixedArray::make(@cmp.minimum(can_write.to_int(), len), b'\x00')
  buffer.blit_from_bytes(0, buf, offset, buffer.length())
  self.0.write(buffer).unwrap_or_error()
  can_write.to_int()
}

///|
/// The standard input channel.
/// Using this value will result in standard input being set to non-blocking mode.
/// The standard input will be reset to its original state after the program exits.
pub let stdin : Input = {
  io: @stdin.get_stdin(),
  read_buf: @io.ReaderBuffer::new(),
}

///|
/// The standard output channel.
/// Using this value will result in standard output being set to non-blocking mode.
/// The standard output will be reset to its original state after the program exits.
pub let stdout : Output = @stdout.get_stdout()

///|
/// The standard error channel.
/// Using this value will result in standard error being set to non-blocking mode.
/// The standard error will be reset to its original state after the program exits.
pub let stderr : Output = @stderr.get_stderr()
