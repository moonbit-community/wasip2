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
/// Run an async entrypoint with the event loop and a task group.
pub fn with_event_loop(f : async (TaskGroup[Unit]) -> Unit) -> Unit raise {
  match @ev.async_run(() => with_task_group(f)) {
    Err(_) => fail("with_event_loop failed")
    Ok(_) => ()
  }
}

///|
/// `sleep` will wait for the given time (in milliseconds) before returning.
/// Other task can still run while current task is sleeping.
/// If current task is cancelled, `sleep` will return early with an error.
pub async fn sleep(duration_ms : Int) -> Unit {
  @wasip2.sleep(duration_ms)
}

///|
/// `is_cancellation_error(err)` return `true`
/// if `err` is the special error used to represent cancellation internally.
///
/// Note that `is_cancellation_error` may not be accurate:
/// async code may fail and raise other error during cancellation handling,
/// in this case the error may be replaced by something else.
/// For accurate detection of cancellation, use `is_being_cancelled` instead.
pub fn is_cancellation_error(error : Error) -> Bool {
  error is @ev.Cancelled
}

///|
/// Get current time, measured in milliseconds.
/// `now` uses the same clock as timers in `moonbitlang/async`.
///
/// `now` can be used to measure elapsed time, such as benchmarking,
/// but the meaning of the absolute time value returned by `now`
/// is undefined, and should not be depended on.
pub fn now() -> Int64 {
  let ns = @monotonicClock.now()
  (ns / 1000000UL).reinterpret_as_int64()
}
