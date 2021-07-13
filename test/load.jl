try
    using TapirSchedulersTests
    true
catch
    false
end || begin
    let path = joinpath(@__DIR__, "TapirSchedulersTests")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    let path = joinpath(@__DIR__, "../benchmark/TapirSchedulersBenchmarks")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    using TapirSchedulersTests
end
