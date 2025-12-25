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
let event_loop : Map[Int, Coroutine] = {}

///|
pub async fn suspend_for_pollable(pollable : @poll.Pollable) -> Unit {
  defer pollable.drop()
  let coro = current_coroutine()
  event_loop.set(pollable.0, coro)
  defer event_loop.remove(pollable.0)
  suspend()
}

///|
pub fn async_run(f : async () -> Unit) -> Result[Unit, Unit] {
  let mut err = false
  let _ = spawn(async fn() -> Unit { f() catch { _ => err = true } })
  while !no_more_work() {
    reschedule()
    if event_loop.is_empty() {
      continue
    }
    let keys = event_loop.keys().to_array().map(k => @poll.Pollable(k))
    let woken = @poll.poll(keys)
    for k in woken {
      let k = k.reinterpret_as_int()
      let coro = event_loop.get(keys[k].0).unwrap()
      coro.wake()
    }
  }
  if err {
    Err(())
  } else {
    Ok(())
  }
}
