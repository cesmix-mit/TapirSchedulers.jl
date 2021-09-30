module TestMultiQueue

using TapirSchedulers: LockedPriorityQueue, MultiQueue, trypush!, maybepopmin!
using Test

function test_pq_simple()
    pq = LockedPriorityQueue{Int,Symbol}(2)
    @test trylock(pq)
    @test trypush!(pq, 2 => :b)
    @test trypush!(pq, 1 => :a)
    @test !trypush!(pq, 3 => :c)  # full
    @test maybepopmin!(pq) === Some(:a)
    @test maybepopmin!(pq) === Some(:b)
end

function test_multi_queue_simple()
    mq = MultiQueue{Int,Symbol}()
    @test trypush!(mq, 1 => :a)
    @test maybepopmin!(mq) === Some(:a)
end

end  # module
