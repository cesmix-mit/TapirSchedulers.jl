module TapirSchedulersTests

using Test

include("test_scheduler.jl")
include("test_deque.jl")
include("test_multi_queue.jl")
include("test_depth_first.jl")

if isdefined(Base.Experimental, :Tapir)
    include("test_tapir.jl")
end

function collect_modules(root::Module)
    modules = Module[]
    for n in names(root, all = true)
        m = getproperty(root, n)
        m isa Module || continue
        m === root && continue
        startswith(string(nameof(m)), "Test") || continue
        push!(modules, m)
    end
    return modules
end

collect_modules() = collect_modules(@__MODULE__)

function runtests(modules = collect_modules())
    @testset "$(nameof(m))" for m in modules
        tests = map(names(m, all = true)) do n
            n == :test || startswith(string(n), "test_") || return nothing
            f = getproperty(m, n)
            f !== m || return nothing
            parentmodule(f) === m || return nothing
            applicable(f) || return nothing  # removed by Revise?
            return f
        end
        filter!(!isnothing, tests)
        @testset "$f" for f in tests
            @debug "Testing $m.$f"
            f()
        end
    end
end

end  # module TapirSchedulersTests
