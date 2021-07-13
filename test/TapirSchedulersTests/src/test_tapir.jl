module TestTapir

using Base.Experimental: Tapir
using TapirSchedulers
using TapirSchedulersBenchmarks.BenchFib.WSFib: fib
using Test

@noinline produce(x) = Base.inferencebarrier(x)::typeof(x)

function simple_spawn()
    Tapir.@output a b
    Tapir.@sync WorkStealingTaskGroup() begin
        Tapir.@spawn a = produce(111)
        b = produce(222)
    end
    return a + b
end

function test_simple_spawn()
    @test simple_spawn() == 333
end

function simple_spawn_macro()
    Tapir.@output a b
    @sync_ws begin
        Tapir.@spawn a = produce(111)
        b = produce(222)
    end
    return a + b
end

function test_simple_spawn_macro()
    @test simple_spawn_macro() == 333
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
