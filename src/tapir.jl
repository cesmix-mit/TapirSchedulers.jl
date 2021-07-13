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

Tapir.spawn(::Type{WorkStealingTaskGroup}, @nospecialize(f)) = spawn(f)

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
