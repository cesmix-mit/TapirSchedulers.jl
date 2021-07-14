include("load.jl")

using Dates
using TapirSchedulersBenchmarks
suite = TapirSchedulersBenchmarks.BenchFib.setup([30])
bench = suite["N=30"]["ws"]

git_status = read(setenv(`git status`; dir = @__DIR__), String)
git_show = read(setenv(`git show --no-patch`; dir = @__DIR__), String)

stats = @timed for i in 1:1000
    @show (i, now())
    @time run(bench)
end

@info(
    "Finished successfully",
    git_status = Text(git_status),
    git_show = Text(git_show),
    time = Text(string(floor(Int, stats.time ÷ 60), " minutes")),
    VERSION,
    Base.GIT_VERSION_INFO,
)
