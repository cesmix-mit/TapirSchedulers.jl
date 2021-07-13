module DummyRecalls

@noinline notsupported() = error("tracing requiers Recalls.jl")

macro note(_...)
    :(notsupported())
end

end  # module
