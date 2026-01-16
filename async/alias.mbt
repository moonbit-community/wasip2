///|
pub using @ev {async_run}

///|
/// Pause current task and give other tasks chance to execute.
pub using @ev {pause}

///|
/// Returns `true` if current task is being cancelled.
pub using @ev {is_being_cancelled}

///|
/// Protect an async function from cancellation.
pub using @ev {protect_from_cancel}

///|
/// Re-export of the async queue type.
pub using @aqueue {type Queue}

///|
/// Re-export of the async semaphore type.
pub using @semaphore {type Semaphore}
