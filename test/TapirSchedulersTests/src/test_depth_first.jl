module TestDepthFirst

using TapirSchedulers
using TapirSchedulers:
    DEPTH_FIRST_SCHEDULER, Priority, rollback_priority, get_current_priority_range
using Test

current_priority() = first(get_current_priority_range())

function record_priority(n, sch = DEPTH_FIRST_SCHEDULER[])
    priorities = fill!(Vector{Priority}(undef, n), typemax(Priority))
    workers = zeros(Int, n)
    function recur(indices)
        if length(indices) == 0
        elseif length(indices) == 1
            @inbounds priorities[indices[1]] = current_priority()
            @inbounds workers[indices[1]] = Threads.threadid()
        else
            f = first(indices)
            l = last(indices)
            m = (l - f + 1) ÷ 2 + f - 1
            work = TapirSchedulers.spawn!(sch) do
                recur(m+1:l)
            end
            recur(f:m)
            fetch(work)::Nothing
        end
        return nothing
    end
    rollback_priority() do
        recur(eachindex(priorities))
    end
    return (; priorities, workers)
end

function test_priority()
    e = 5
    @assert e < sizeof(Priority) * 8
    (; priorities) = record_priority(2^e)
    @test all(<(typemax(Priority)), priorities)
    @test issorted(priorities)
end

end  # module
