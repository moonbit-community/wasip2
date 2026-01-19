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
/// Retry strategy for controlling delay between retry attempts.
pub(all) enum RetryMethod {
  /// Retry immediately without any delay
  Immediate
  /// Wait a fixed amount of time (in milliseconds) between retries
  FixedDelay(Int)
  /// Use exponential backoff with configurable initial delay, multiplier factor, and maximum delay
  ExponentialDelay(initial~ : Int, factor~ : Double, maximum~ : Int)
}

///|
/// `retry(strategy, max_retry?, fatal_error?, f)` executes `f` and retries on failure.
///
/// - `strategy` controls the delay between retry attempts
/// - `max_retry` limits the number of retry attempts (default: unlimited)
/// - `fatal_error` is a predicate that returns `true` for errors that should not be retried
/// - Returns the result of `f` if it succeeds
/// - Raises the last error if all retries are exhausted or a fatal error occurs
///
/// If the current task is being cancelled, retry will stop and raise the error.
pub async fn[X] retry(
  strategy : RetryMethod,
  max_retry? : Int,
  fatal_error? : (Error) -> Bool,
  f : async () -> X,
) -> X {
  match strategy {
    Immediate =>
      for i = 0; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(pred) && pred(err) => raise err
          err if @ev.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => ()
        } noraise {
          result => return result
        }
      }
    FixedDelay(t) =>
      for i = 0; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(pred) && pred(err) => raise err
          err if @ev.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => @wasip2.sleep(t)
        } noraise {
          result => return result
        }
      }
    ExponentialDelay(initial~, factor~, maximum~) =>
      for i = 0, timeout = initial; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(pred) && pred(err) => raise err
          err if @ev.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => {
            @wasip2.sleep(timeout)
            continue i + 1,
              @cmp.minimum(maximum, (timeout.to_double() * factor).to_int())
          }
        } noraise {
          result => return result
        }
      }
  }
}
