module BenchFib

using BenchmarkTools

module SeqFib

function fib(N)
    if N <= 1
        return N
    end
    a = fib(N - 2)
    b = fib(N - 1)
    return a + b
end

end  # module SeqFib

module BaseFib

function fib(N)
    if N <= 1
        return N
    end
    a = Threads.@spawn fib(N - 2)
    b = fib(N - 1)
    return fetch(a)::Int + b
end

end  # module BaseFib


module TapirFib

using Base.Experimental: Tapir

function fib(N)
    if N <= 1
        return N
    end
    Tapir.@output a b
    Tapir.@sync begin
        Tapir.@spawn a = fib(N - 2)
        b = fib(N - 1)
    end
    return a + b
end

end  # module TapirFib


module WSFib

using Base.Experimental: Tapir
using TapirSchedulers

function fib(N)
    if N <= 1
        return N
    end
    Tapir.@output a b
    Tapir.@sync WorkStealingTaskGroup() begin
        Tapir.@spawn a = fib(N - 2)
        b = fib(N - 1)
    end
    return a + b
end

end  # module WSFib

function setup(Ns = [5, 10, 20])
    suite = BenchmarkGroup()
    for N in Ns
        s0 = suite["N=$N"] = BenchmarkGroup()
        s0["seq"] = @benchmarkable SeqFib.fib($N)
        s0["base"] = @benchmarkable BaseFib.fib($N)
        s0["tapir"] = @benchmarkable TapirFib.fib($N)
        s0["ws"] = @benchmarkable WSFib.fib($N)
    end
    return suite
end

function clear() end

end  # module BenchFib
