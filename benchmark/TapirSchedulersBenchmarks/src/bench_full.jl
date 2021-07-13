module BenchFull

using BenchmarkTools

module SeqFull
using Base.Cartesian: @nexprs

function f(height = 5)
    @nexprs 32 i -> g(i, height)
end

function g(i, height)
    height <= 0 && return
    i < 32 && return
    @nexprs 32 i -> g(i, height - 1)
end

end  # module SeqFull

module BaseFull
using Base.Cartesian: @nexprs

function f(height = 5)
    @sync begin
        @nexprs 32 i -> Threads.@spawn g(i, height)
    end
end

function g(i, height)
    height <= 0 && return
    i < 32 && return
    @sync begin
        @nexprs 32 i -> Threads.@spawn g(i, height - 1)
    end
end

end  # module BaseFull


module TapirFull
using Base.Cartesian: @nexprs
using Base.Experimental: Tapir

function f(height = 5)
    Tapir.@sync begin
        @nexprs 32 i -> Tapir.@spawn g(i, height)
    end
end

function g(i, height)
    height <= 0 && return
    i < 32 && return
    Tapir.@sync begin
        @nexprs 32 i -> Tapir.@spawn g(i, height - 1)
    end
end

end  # module TapirFull


module WSFull
using Base.Cartesian: @nexprs
using Base.Experimental: Tapir
using TapirSchedulers

function f(height = 5)
    Tapir.@sync WorkStealingTaskGroup() begin
        @nexprs 32 i -> Tapir.@spawn g(i, height)
    end
end

function g(i, height)
    height <= 0 && return
    i < 32 && return
    Tapir.@sync WorkStealingTaskGroup() begin
        @nexprs 32 i -> Tapir.@spawn g(i, height - 1)
    end
end

end  # module WSFull

function setup(heights = [5])
    suite = BenchmarkGroup()
    for height in heights
        s0 = suite["height=$height"] = BenchmarkGroup()
        s0["seq"] = @benchmarkable SeqFull.f($height)
        s0["base"] = @benchmarkable BaseFull.f($height)
        s0["tapir"] = @benchmarkable TapirFull.f($height)
        s0["ws"] = @benchmarkable WSFull.f($height)
    end
    return suite
end

function clear() end

end  # module BenchFull
