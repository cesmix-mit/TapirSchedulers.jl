module TapirSchedulers

include("dummy_recalls.jl")

const Recalls = try
    Base.require(Base.PkgId(Base.UUID(0x30af7cf3eb4344c7afa733725b72a81e), "Recalls"))
catch
    DummyRecalls
end

include("utils.jl")
include("bounded_deque.jl")
include("bounded_scheduler.jl")
include("multi_queue.jl")
include("depth_first_scheduler.jl")

if isdefined(Base.Experimental, :Tapir)
    export WorkStealingTaskGroup, DepthFirstTaskGroup, @sync_ws, @sync_df
    using Base.Experimental: Tapir
    include("tapir.jl")
end

function __init__()
    init_bounded_scheduler()
    init_depth_first_scheduler()
end

end
