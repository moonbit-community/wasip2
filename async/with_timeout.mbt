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
pub suberror TimeoutError derive(Show)

///|
/// `with_timeout(timeout, f)` run the async function `f`.
///
/// - If `f` return `value` before `timeout`,
///   `with_timeout` will return `value` immediately.
///
/// - If `f` fail before `timeout`, `with_timeout` will fail immediately.
///
/// - If `f` is still running after `timeout` milliseconds,
///   `with_timeout` will fail with `TimeoutError`,
///   or the value of `error`, if explicitly specified.
pub async fn[X] with_timeout(
  time : Int,
  f : async () -> X,
  error~ : Error = TimeoutError,
) -> X {
  with_task_group(fn(group) {
    group.spawn_bg(no_wait=true, fn() {
      @wasip2.sleep(time)
      raise error
    })
    f()
  })
}

///|
/// `with_timeout_opt(timeout, f)` run the async function `f`.
///
/// - If `f` return `value` before `timeout`,
///   `with_timeout_opt` will return `Some(value)` immediately.
///
/// - If `f` fail before `timeout`, `with_timeout_opt` will fail immediately.
///
/// - If `f` is still running after `timeout` milliseconds,
/// ` with_timeout_opt` will return `None` immediately, and `f` will be cancelled.
pub async fn[X] with_timeout_opt(time : Int, f : async () -> X) -> X? {
  with_task_group(fn(group) {
    group.spawn_bg(no_wait=true, fn() {
      @wasip2.sleep(time)
      group.return_immediately(None)
    })
    Some(f())
  })
}
