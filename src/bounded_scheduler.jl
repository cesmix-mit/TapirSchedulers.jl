mutable struct Work
    f::Any
    scheduler::Any
    isenqueued::Bool
    @atomic isdone::Bool
    result::Any
    iserror::Bool
    Work(@nospecialize(f)) = new(f, nothing, false, false, nothing, false)
end

scheduler(work::Work) = work.scheduler::WorkStealingScheduler

function run!(work::Work)
    work.result = try
        Base.invokelatest(work.f)
    catch err
        work.iserror = true
        err
    end
    @atomic work.isdone = true
end

mutable struct WorkerState
    @atomic state::UInt
end

struct Worker
    state::WorkerState
    task::Task
end

mutable struct SchedulerState
    @atomic counter::Int
end

struct WorkStealingScheduler
    queues::Vector{BoundedWorkStealingDeque{Work}}
    workers::Vector{Worker}
    state::SchedulerState
end

function WorkStealingScheduler(; dequesize = 2^7)
    sch = WorkStealingScheduler(
        [BoundedWorkStealingDeque{Work}(dequesize) for _ in 1:Threads.nthreads()],
        Worker[],
        SchedulerState(Threads.nthreads()),
    )
    for tid in 1:Threads.nthreads()
        function workerloop()
            try
                workerloop!(sch)
            catch err
                @error "Worker loop exited" exception = (err, catch_backtrace())
                rethrow()
            end
        end
        task = Task(workerloop)
        @assert task.sticky == true
        ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, tid - 1)
        push!(sch.workers, Worker(WorkerState(WKR_WORKING), task))
    end
    for wkr in sch.workers
        schedule(wkr.task)
    end
    return sch
end

function trypush!(sch::WorkStealingScheduler, work::Work)
    @assert work.scheduler === nothing
    work.scheduler = sch
    if !trypush!(sch.queues[Threads.threadid()], work)
        run!(work)
        @trace(label = :push_failed, threadid = Threads.threadid())
        return false
    end
    work.isenqueued = true
    @trace(
        label = :push_success,
        threadid = Threads.threadid(),
        length = length(sch.queues[Threads.threadid()]),
    )

    state = sch.state
    if (@atomic :monotonic state.counter) < Threads.nthreads()
        for wkr in sch.workers
            if trywakeup!(wkr)
                @atomic state.counter += 1
            end
        end
    end

    return true
end

const WKR_WAITING = UInt(0)
const WKR_WORKING = UInt(1)
const WKR_NOTIFIED = UInt(2)

function workerloop!(sch::WorkStealingScheduler)
    nspins = 1000
    wkr::WorkerState = sch.workers[Threads.threadid()].state
    schstate::SchedulerState = sch.state
    while true
        for _ in 1:nspins
            while helpself!(sch)
            end

            i = Threads.threadid() + 1
            for _ in 1:Threads.nthreads()-1
                if i == Threads.threadid()
                    i += 1
                end
                if i > Threads.nthreads()
                    i = 1
                end
                while true
                    item = maybepopfirst!(sch.queues[i])
                    if item === nothing
                        break
                    else
                        run!(something(item))
                        while helpself!(sch)
                        end
                    end
                    GC.safepoint()
                end
            end
        end

        @trace(label = :worker_start_sleep, threadid = Threads.threadid())
        @atomic wkr.state = WKR_WAITING
        @atomic schstate.counter -= 1
        wait()
        @assert (@atomic wkr.state) == WKR_NOTIFIED
        @atomic wkr.state = WKR_WORKING
        @trace(label = :worker_done_sleep, threadid = Threads.threadid())
    end
end

function trywakeup!(wkr::Worker)
    wkrstate = wkr.state
    _, issuccess = @atomicreplace wkrstate.state WKR_WAITING => WKR_NOTIFIED
    if issuccess
        schedule(wkr.task)
        @trace(label = :wakeup_scheduled, threadid = Threads.threadid())
        return true
    else
        return false
    end
end

function helpself!(sch::WorkStealingScheduler)
    item = maybepop!(sch.queues[Threads.threadid()])
    if item === nothing
        @trace(label = :helpself_fail, threadid = Threads.threadid())
        return false
    else
        run!(something(item))
        @trace(label = :helpself_success, threadid = Threads.threadid())
        GC.safepoint()
        return true
    end
end

function helpself_until!(f, sch::WorkStealingScheduler)
    while helpself!(sch)
        f() && return true
    end
    return false
end

function helpothers_until!(f, sch::WorkStealingScheduler)
    Threads.nthreads() == 1 && return
    i = Threads.threadid()
    while true
        i += 1
        if i == Threads.threadid()
            i += 1
        end
        if i > Threads.nthreads()
            i = 1
            GC.safepoint()
        end

        while true
            item = maybepopfirst!(sch.queues[i])
            if item === nothing
                f() && return
                @trace(label = :helpothers_empty, threadid = Threads.threadid())
                break
            else
                run!(something(item))
                @trace(label = :helpothers_success, threadid = Threads.threadid())
                f() && return
                helpself_until!(f, sch) && return
            end
        end
    end
end

function wait_nothrow(work::Work)
    @inline isdone() = @atomic work.isdone
    if !work.isenqueued
        @assert isdone()
        return
    end
    sch = scheduler(work)
    helpself_until!(isdone, sch) && return
    helpothers_until!(isdone, sch)
    # Note: assuming `work` is in `sch`, `helpothers_until!` will finish
    # eventually.
end

function Base.wait(work::Work)
    wait_nothrow(work)
    if work.iserror
        throw(work.result)
    end
end

function Base.fetch(work::Work)
    wait(work)
    return work.result
end

function spawn!(sch::WorkStealingScheduler, @nospecialize(f))
    work = Work(f)
    trypush!(sch, work)
    return work
end

spawn(@nospecialize(f)) = spawn!(WORK_STEALING_SCHEDULER[], f)

const WORK_STEALING_SCHEDULER = Ref{WorkStealingScheduler}()

function init_bounded_scheduler()
    WORK_STEALING_SCHEDULER[] = WorkStealingScheduler()
end
