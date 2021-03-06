# TODO: maybe try 16 bit?
const Priority = UInt64

@enum PriorityType::UInt8 begin
    DEPTH_FIRST_PRIORITY
    CONSTANT_PRIORITY
    RANDOM_PRIORITY
end

struct DepthFirstScheduler <: Scheduler
    multiq::MultiQueue{Priority,Work}
    workers::Vector{Worker}
    state::SchedulerState
    priority_type::PriorityType
end

function DepthFirstScheduler(; priority_type::PriorityType = DEPTH_FIRST_PRIORITY)
    # TODO: Support and test "oversubscription"; useful for waitable tasks.
    nworkers = Threads.nthreads()
    sch = DepthFirstScheduler(
        MultiQueue{Priority,Work}(),
        Worker[],  # to be filled
        SchedulerState(nworkers),
        priority_type,
    )
    for wid in 1:nworkers
        function workerloop()
            try
                workerloop!(sch, wid)
            catch err
                @error "Worker loop exited" exception = (err, catch_backtrace())
                rethrow()
            end
        end
        task = Task(workerloop)
        task.sticky == true
        ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, (wid - 1) % nworkers)
        push!(sch.workers, Worker(WorkerState(WKR_WORKING), task))
    end
    for wkr in sch.workers
        schedule(wkr.task)
    end
    return sch
end

function workerloop!(sch::DepthFirstScheduler, wid::Integer)
    multiq = sch.multiq
    wkr = sch.workers[wid].state
    schstate = sch.state
    npolls = 0
    while true
        while true
            item = maybepopmin!(multiq)
            if item === nothing
                npolls += 1
                if npolls < 1_000_000
                    GC.safepoint()
                    ccall(:jl_cpu_pause, Cvoid, ())
                    # Main.@tlc loop_poll
                else
                    break
                end
            else
                run!(something(item::Some{Work}))
                GC.safepoint()
                npolls = 0
            end
        end

        @trace(label = :worker_start_sleep, threadid = Threads.threadid())
        @atomic wkr.state = WKR_WAITING
        @atomic schstate.counter -= 1
        wait()
        @assert (@atomic wkr.state) == WKR_NOTIFIED
        @atomic wkr.state = WKR_WORKING
        @trace(label = :worker_done_sleep, threadid = Threads.threadid())
        # Main.@tlc loop_wakeup
    end
end

const CURRENT_PRIORITY = gensym(:_CURRENT_PRIORITY_)

const PriorityRange = Pair{Priority,Priority}

entirerange(::Type{R}) where {T,R<:Pair{T,T}} = (typemin(T) => typemax(T) - oneunit(T))::R

# TODO: Better storage than `task_local_storage`?
get_current_priority_range() =
    get(task_local_storage(), CURRENT_PRIORITY, entirerange(PriorityRange))::PriorityRange
set_current_priority_range(pr::PriorityRange) = task_local_storage(CURRENT_PRIORITY, pr)

# For debugging:
reset_current_priority_range() = set_current_priority_range(entirerange(PriorityRange))

function halverange(pr::Pair)
    f = first(pr)
    l = last(pr)
    f >= l && return (pr, pr)
    m = (l - f) ?? 2 + f
    return (f => m, m => l)
end

"""
    rollback_priority(f)

Run `f()` and rollback the priority range. As such, `f` must synchronize all
child tasks.
"""
function rollback_priority(f)
    pr = get_current_priority_range()
    try
        f()
    finally
        set_current_priority_range(pr)
    end
end

function spawn!(f::F, sch::DepthFirstScheduler) where {F}
    pr = get_current_priority_range()
    low, high = halverange(pr)
    lb, ub = entirerange(PriorityRange)
    rnd1 = rand(lb:ub)
    rnd2 = rand(lb:ub)
    if sch.priority_type == CONSTANT_PRIORITY
        low = high = pr
    elseif sch.priority_type == RANDOM_PRIORITY
        low = rnd1 => rnd1
        high = rnd2 => rnd2
    end
    set_current_priority_range(low)  # more urgent
    subrange = high::PriorityRange   # less urgent

    # TODO: move this explicitly to `Work`?
    pdf_wrapper() = task_local_storage(f, CURRENT_PRIORITY, subrange)

    work = Work(pdf_wrapper)
    work.scheduler = sch
    if !trypush!(sch.multiq, first(subrange) => work)
        work.isenqueued = false
        run!(work)  # no deadlock; due to the serial-projection property
        return work
    end
    trywakeupall!(sch)
    return work
end

helpself_until!(isdone, ::DepthFirstScheduler) = false

function helpothers_until!(isdone, sch::DepthFirstScheduler)
    multiq = sch.multiq
    npolls = 0
    backoff = 1
    while true
        isdone() && return
        item = maybepopmin!(multiq)
        if item === nothing
            # TODO: DON'T SPIN!!!!
            # yield()
            nspins = rand(1:backoff)
            npolls += nspins
            for _ in 1:nspins
                GC.safepoint()
                ccall(:jl_cpu_pause, Cvoid, ())
            end
            backoff *= 2
            backoff = min(backoff, 1000)
            # Main.@tlc helpothers_poll
            if npolls > 1_000_000_000
                error("timeout")
            end
        else
            npolls = 0
            run!(something(item::Some{Work}))
            GC.safepoint()
            # Main.@tlc helpothers_helped
        end
    end
end

const DEPTH_FIRST_SCHEDULER = Ref{DepthFirstScheduler}()
const CONSTANT_PRIORITY_SCHEDULER = Ref{DepthFirstScheduler}()
const RANDOM_PRIORITY_SCHEDULER = Ref{DepthFirstScheduler}()

function init_depth_first_scheduler()
    DEPTH_FIRST_SCHEDULER[] = DepthFirstScheduler()
    CONSTANT_PRIORITY_SCHEDULER[] = DepthFirstScheduler(; priority_type = CONSTANT_PRIORITY)
    RANDOM_PRIORITY_SCHEDULER[] = DepthFirstScheduler(; priority_type = RANDOM_PRIORITY)
end

function Base.show(io::IO, sch::DepthFirstScheduler)
    if sch === DEPTH_FIRST_SCHEDULER[]
        print(io, TapirSchedulers, '.', "DEPTH_FIRST_SCHEDULER[]")
    elseif sch === CONSTANT_PRIORITY_SCHEDULER[]
        print(io, TapirSchedulers, '.', "CONSTANT_PRIORITY_SCHEDULER[]")
    elseif sch === RANDOM_PRIORITY_SCHEDULER[]
        print(io, TapirSchedulers, '.', "RANDOM_PRIORITY_SCHEDULER[]")
    else
        print(io, DepthFirstScheduler, "()")
    end
end

function Base.show(io::IO, ::MIME"text/plain", sch::DepthFirstScheduler)
    show(io, sch)
    print(io, " ", length(sch.workers), " workers")
    print(io, " (", sch.state.counter, " active worker(s))")
    println(io)
    print(io, "#items in multi queue:")
    for pq in sch.multiq.queues
        print(io, " ", pq.nitems)
    end
end
