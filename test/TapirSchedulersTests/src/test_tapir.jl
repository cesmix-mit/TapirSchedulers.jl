module TestTapir

using Base.Experimental: Tapir
using TapirSchedulers
using TapirSchedulersBenchmarks.BenchFib: WSFib, DFFib
using Test

@noinline produce(x) = Base.inferencebarrier(x)::typeof(x)

function simple_spawn(tgf)
    Tapir.@output a b
    Tapir.@sync tgf() begin
        Tapir.@spawn a = produce(111)
        b = produce(222)
    end
    return a + b
end

function test_simple_spawn()
    @test simple_spawn(WorkStealingTaskGroup) == 333
    @test simple_spawn(DepthFirstTaskGroup) == 333
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

test_fib_work_stealing() = check_fib(WSFib.fib)
test_fib_depth_first() = check_fib(DFFib.fib)

function check_fib(fib)
    @test fib(1) == 1
    @test fib(2) == 1
    @test fib(3) == 2
    @test fib(4) == 3
    @test fib(5) == 5
    @test fib(6) == 8
    @test fib(10) == 55
end

end  # module
