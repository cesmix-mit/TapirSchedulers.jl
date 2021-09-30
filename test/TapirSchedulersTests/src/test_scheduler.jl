module TestScheduler

using TapirSchedulers:
    TapirSchedulers, WORK_STEALING_SCHEDULER, DEPTH_FIRST_SCHEDULER, rollback_priority
using Test

test_simple_spawn_work_stealing() = check_simple_spawn(WORK_STEALING_SCHEDULER[])

function test_simple_spawn_depth_first()
    rollback_priority() do
        check_simple_spawn(DEPTH_FIRST_SCHEDULER[])
    end
end

function check_simple_spawn(sch)
    w = TapirSchedulers.spawn!(sch) do
        1 + 1
    end
    @test fetch(w) == 2
end

function fib(N, sch)
    if N <= 1
        return N
    end
    t = TapirSchedulers.spawn!(sch) do
        fib(N - 2, sch)
    end
    y = fib(N - 1, sch)
    return fetch(t)::Int + y
end

test_fib_work_stealing() = check_fib(WORK_STEALING_SCHEDULER[])

function test_fib_depth_first()
    rollback_priority() do
        check_fib(DEPTH_FIRST_SCHEDULER[])
    end
end

function check_fib(sch)
    @test fib(1, sch) == 1
    @test fib(2, sch) == 1
    @test fib(3, sch) == 2
    @test fib(4, sch) == 3
    @test fib(5, sch) == 5
    @test fib(6, sch) == 8
    @test fib(10, sch) == 55
end

end  # module
