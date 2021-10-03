mutable struct LockedPriorityQueue{K,V}
    # TODO: find a better queue
    items::Vector{Pair{K,V}}
    nitems::Int
    @atomic minkey::K
    @atomic locked::Bool
end

struct MultiQueue{K,V}
    queues::Vector{LockedPriorityQueue{K,V}}
end

function LockedPriorityQueue{K,V}(buffersize::Integer) where {K,V}
    items = Vector{Pair{K,V}}(undef, buffersize)
    return LockedPriorityQueue{K,V}(items, 0, typemax(K), false)
end

function MultiQueue{K,V}() where {K,V}
    nqueues = 4 * Threads.nthreads()
    queues = [LockedPriorityQueue{K,V}(128) for _ in 1:nqueues]
    return MultiQueue{K,V}(queues)
end

function Base.trylock(pq::LockedPriorityQueue)
    _, ok = @atomicreplace pq.locked false => true
    return ok
end

function Base.unlock(pq::LockedPriorityQueue)
    @_assert pq.locked
    @atomic pq.locked = false
    return
end

function _insert!(xs, n::Integer, i::Integer, x)
    @_assert n < length(xs)
    for j in n:-1:i
        @inbounds xs[j+1] = xs[j]
    end
    xs[i] = x
end

function trypush!(pq::LockedPriorityQueue{K,V}, x::Pair{K,V}) where {K,V}
    @_assert pq.locked
    @_assert first(x) < typemax(K)
    if length(pq.items) == pq.nitems
        # Main.@tlc lpq_full
        return false
    end
    i = searchsortedlast(view(pq.items, 1:pq.nitems), x; by = first, rev = true) + 1
    _insert!(pq.items, pq.nitems, i, x)
    pq.nitems += 1
    if i == 1
        @atomic :monotonic pq.minkey = first(x)
    end
    # Main.@tlc lpq_inserted
    return true
end

function maybepopmin!(pq::LockedPriorityQueue{K,V}) where {K,V}
    pq.minkey < typemax(K) || return nothing
    @_assert pq.locked
    @_assert pq.nitems > 0
    x = pq.items[pq.nitems]
    n = pq.nitems -= 1
    k = n == 0 ? typemax(K) : first(pq.items[n])
    @atomic :monotonic pq.minkey = k
    return Some{V}(last(x))
end

function trypush!(mq::MultiQueue{K,V}, x::Pair{K,V}) where {K,V}
    (; queues) = mq
    nfails = 0
    while true
        # TODO: cheaper RNG?
        a = rand(queues)
        if trylock(a)
            try
                trypush!(a, x) && return true
            finally
                unlock(a)
            end
        end
        nfails += 1
        if nfails > length(queues)  # TODO: what's the good threshold?
            # contention or full; not a good sign anyway
            return false
        end
        GC.safepoint()
    end
end

"""
    maybepopmin!(mq::MultiQueue{K,V}) -> Some(v::V) or nothing

Return approximately minimum element from the multi-queue `mq`; return `nothing`
if empty.
"""
function maybepopmin!(mq::MultiQueue{K,V}) where {K,V}
    (; queues) = mq
    while true
        # TODO: cheaper RNG?
        a = rand(queues)
        b = rand(queues)
        if a.minkey > b.minkey
            a = b
        end
        if a.minkey == typemax(K)
            found = false
            for outer a in queues
                if a.minkey < typemax(K)
                    found = true
                    break
                end
            end
            found || return nothing
        end
        if trylock(a)
            try
                y = maybepopmin!(a)
                y === nothing || return y
            finally
                unlock(a)
            end
        end
        GC.safepoint()
    end
end
