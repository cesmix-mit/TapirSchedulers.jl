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

fib_ws(N) = fib(N, WORK_STEALING_SCHEDULER[])
function fib_df(N)
    rollback_priority() do
        fib(N, DEPTH_FIRST_SCHEDULER[])
    end
end

test_fib_work_stealing() = check_fib(fib_ws)
test_fib_depth_first() = check_fib(fib_df)

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
