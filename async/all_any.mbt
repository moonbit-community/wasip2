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
/// `all(tasks, max_concurrent?)` waits for all tasks to complete and returns their results.
///
/// - All tasks are spawned and executed (optionally with `max_concurrent` limit).
/// - If all tasks succeed, `all` returns an array of results in the same order as `tasks`.
/// - If any task fails, `all` fails with that error and other running tasks are cancelled.
///
/// The `max_concurrent` parameter limits the number of tasks that can run concurrently.
/// If not specified, all tasks run at once.
pub async fn[X] all(
  tasks : ArrayView[async () -> X],
  max_concurrent? : Int,
) -> Array[X] {
  let semaphore = match max_concurrent {
    Some(p) => Some(@semaphore.Semaphore::new(p))
    None => None
  }
  let results : Array[X?] = Array::make(tasks.length(), None)
  with_task_group(
    fn(tg) {
      for i, task in tasks {
        match semaphore {
          Some(sem) => sem.acquire()
          None => ()
        }
        tg.spawn_bg(fn() {
          // We rely on the assumption that the task spawned will 100% executed
          // even if it is cancelled, so that we can release the semaphore properly.
          defer {
            match semaphore {
              Some(sem) => sem.release()
              None => ()
            }
          }
          let result = task()
          results[i] = Some(result)
        })
      }
    },
  )
  results.map(fn(r) { r.unwrap() })
}

///|
/// `any(tasks, max_concurrent?, allow_failure?)` waits for the first task to complete successfully.
///
/// - All tasks are spawned and executed (optionally with `max_concurrent` limit).
/// - When the first task completes successfully, `any` returns its result immediately
///   and all other running tasks are cancelled.
/// - If `allow_failure` is `false` (default), `any` fails as soon as any task fails.
/// - If `allow_failure` is `true`, failing tasks are ignored and `any` waits for the first success.
/// - If all tasks fail, `any` fails with the error from the last task.
///
/// The `max_concurrent` parameter limits the number of tasks that can run concurrently.
/// If not specified, all tasks run at once.
///
/// `any` requires at least one task and will fail if the array is empty.
pub async fn[X] any(
  tasks : ArrayView[async () -> X],
  max_concurrent? : Int,
  allow_failure~ : Bool = false,
) -> X {
  let semaphore = match max_concurrent {
    Some(p) => Some(@semaphore.Semaphore::new(p))
    None => None
  }
  if tasks.is_empty() {
    fail("no tasks provided to any()")
  }
  let result : Ref[Result[X, Error]?] = { val: None }
  with_task_group(
    fn(tg) {
      for task in tasks {
        match semaphore {
          Some(sem) => sem.acquire()
          None => ()
        }
        tg.spawn_bg(fn() {
          // We rely on the assumption that the task spawned will 100% executed
          // even if it is cancelled, so that we can release the semaphore properly.
          defer {
            match semaphore {
              Some(sem) => sem.release()
              None => ()
            }
          }
          try {
            let value = task()
            result.val = Some(Ok(value))
            tg.return_immediately(())
          } catch {
            e =>
              if allow_failure {
                match result.val {
                  None | Some(Err(_)) => result.val = Some(Err(e))
                  Some(Ok(_)) => ()
                }
              } else {
                raise e
              }
          }
        })
      }
    },
  )
  match result.val {
    Some(Ok(value)) => value
    Some(Err(e)) => raise e
    None => panic()
  }
}
