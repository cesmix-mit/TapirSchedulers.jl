module TestScheduler

using TapirSchedulers
using Test

function test_simple_spawn()
    w = TapirSchedulers.spawn() do
        1 + 1
    end
    @test fetch(w) == 2
end

function fib(N)
    if N <= 1
        return N
    end
    t = TapirSchedulers.spawn() do
        fib(N - 2)
    end
    y = fib(N - 1)
    return fetch(t)::Int + y
end

function test_fib()
    @test fib(1) == 1
    @test fib(2) == 1
    @test fib(3) == 2
    @test fib(4) == 3
    @test fib(5) == 5
    @test fib(6) == 8
    @test fib(10) == 55
end

end  # module
