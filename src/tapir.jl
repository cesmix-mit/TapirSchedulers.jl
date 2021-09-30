using .Tapir: ConcreteMaybe

"""
    WorkStealingTaskGroup()

A custom taskgroup implementation for `Base.Experimental.Tapir` using
work-stealing scheduler.

NOTE: This scheduler does not support any possibly blocking synchronization
between Tapir tasks between *any* syncregions (including the syncregions placed
in different concurrent `Task`s).

# Examples
```julia
Tapir.@sync WorkStealingTaskGroup() begin
    ...
end
```
"""
WorkStealingTaskGroup

function _WorkStealingTaskGroup end

refresh() = @eval invalidator() = nothing
invalidator() = nothing

struct WorkStealingTaskGroup
    global _WorkStealingTaskGroup() = new()
end

function WorkStealingTaskGroup()
    invalidator()
    return _WorkStealingTaskGroup()
end

# TODO: implement
function Tapir.spawn!(tg::WorkStealingTaskGroup, @nospecialize(f))
    error("Tapir.spawn!(::WorkStealingTaskGroup, _) not implemented yet")
    push!(tg, spawn(f))
end

#=
function Tapir.sync!(tg::WorkStealingTaskGroup)
    foreach(wait_nothrow, tg)
    ref = Ref{Union{Nothing,CompositeException}}(nothing)
    foreach(tg) do work
        if work.iserror
            local ex = ref[]
            if ex === nothing
                ex = ref[] = CompositeException()
            end
            push!(ex, work.result)
        end
    end
    ex = ref[]
    if ex !== nothing
        throw(ex)
    end
end
=#

Tapir.spawn(::Type{WorkStealingTaskGroup}, @nospecialize(f)) =
    spawn!(f, WORK_STEALING_SCHEDULER[])

function Tapir.synctasks(args::ConcreteMaybe{Work}...)
    ex = nothing
    for t in args
        if t !== nothing
            work::Work = something(t)
            wait_nothrow(work)
            if work.iserror
                if ex === nothing
                    ex = CompositeException()
                end
                push!(ex::CompositeException, work.result)
            end
        end
    end
    if ex !== nothing
        throw(ex)
    end
end

macro sync_ws(block)
    esc(:($Tapir.@sync $WorkStealingTaskGroup() $block))
end

"""
    DepthFirstTaskGroup()

A custom taskgroup implementation for `Base.Experimental.Tapir` using a relaxed
depth-first scheduler.

**NOTE**: Currently, it must used via `@sync_df`.
"""
DepthFirstTaskGroup

function _DepthFirstTaskGroup end

struct DepthFirstTaskGroup
    global _DepthFirstTaskGroup() = new()
end

function DepthFirstTaskGroup()
    invalidator()
    return _DepthFirstTaskGroup()
end

# TODO: implement
function Tapir.spawn!(tg::DepthFirstTaskGroup, @nospecialize(f))
    error("Tapir.spawn!(::DepthFirstTaskGroup, _) not implemented yet")
    push!(tg, spawn!(f, DEPTH_FIRST_SCHEDULER[]))
end

Tapir.spawn(::Type{DepthFirstTaskGroup}, @nospecialize(f)) =
    spawn!(f, DEPTH_FIRST_SCHEDULER[])

"""
    @sync_df block

Run Tapir tasks inside a `DepthFirstTaskGroup`.
"""
macro sync_df(block)
    @gensym pr
    if Meta.isexpr(block, :block)
        block = Expr(:block, __source__, block)
    end
    quote
        # TODO: make it possible to define this via Tapir entry points
        $pr = $get_current_priority_range()
        try
            $Tapir.@sync $DepthFirstTaskGroup() $block
        finally
            $set_current_priority_range($pr)
        end
    end |> esc
end
