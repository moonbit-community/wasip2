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
priv enum LazyState[X] {
  Uninitialized
  Running(@ev.Coroutine)
  Done(X)
  Fail(Error)
}

///|
/// A lazily initialized async value.
///
/// The computation is deferred until `.wait()` is called.
/// Once computed, the result is cached and returned immediately on subsequent calls.
/// If all waiters are cancelled before completion, the computation is cancelled automatically.
struct Lazy[X] {
  worker : async () -> X
  waiters : Set[@ev.Coroutine]
  mut state : LazyState[X]
}

///|
/// Creates a new lazy value from an async function.
///
/// The function `f` will not be executed until `.wait()` is called.
/// Multiple calls to `.wait()` will share the same computation result.
pub fn[X] lazy_init(f : async () -> X) -> Lazy[X] {
  { worker: f, waiters: Set::new(), state: Uninitialized }
}

///|
/// Waits for the lazy value to be computed and returns the result.
///
/// - If already computed, returns the cached result immediately.
/// - If computation failed previously, raises the cached error.
/// - If not yet started, spawns the computation and waits for it.
/// - If all waiters are cancelled before completion, the computation is cancelled.
pub async fn[X] Lazy::wait(self : Lazy[X]) -> X {
  match self.state {
    Done(result) => return result
    Fail(err) => raise err
    Running(_) => ()
    Uninitialized => {
      let coro = @ev.spawn(fn() {
        try (self.worker)() catch {
          err =>
            if err is @ev.Cancelled && @ev.is_being_cancelled() {
              self.state = Uninitialized
            } else {
              self.state = Fail(err)
            }
        } noraise {
          ret => self.state = Done(ret)
        }
        for waiter in self.waiters {
          waiter.wake()
        }
      })
      self.state = Running(coro)
    }
  }
  let curr_coro = @ev.current_coroutine()
  self.waiters.add(curr_coro)
  @ev.suspend() catch {
    err => {
      self.waiters.remove(curr_coro)
      if self.waiters.is_empty() {
        match self.state {
          Running(coro) => coro.cancel()
          _ => ()
        }
      }
      raise err
    }
  }
  self.waiters.remove(curr_coro)
  match self.state {
    Done(result) => result
    Fail(err) => raise err
    Running(_) | Uninitialized => panic()
  }
}
