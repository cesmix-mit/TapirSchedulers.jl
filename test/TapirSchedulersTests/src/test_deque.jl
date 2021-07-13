module TestDeque

using TapirSchedulers: BoundedWorkStealingDeque, isfull, maybepop!, maybepopfirst!, trypush!
using Test

function test_full()
    q = BoundedWorkStealingDeque{Int}(4)
    @testset for i in 1:3
        @test !isfull(q)
        @test trypush!(q, i)
    end
    @test isfull(q)
    @test !trypush!(q, 4)
    @test maybepop!(q) === Some(3)
    @test trypush!(q, 4)
    @test maybepop!(q) === Some(4)
    @test maybepopfirst!(q) === Some(1)
    @test maybepopfirst!(q) === Some(2)
    @test maybepopfirst!(q) === nothing
    @test maybepop!(q) === nothing
end

end  # module
