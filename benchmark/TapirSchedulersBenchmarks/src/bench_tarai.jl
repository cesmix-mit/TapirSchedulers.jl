# https://en.wikipedia.org/wiki/Tak_(function)
module BenchTarai

using BenchmarkTools

module SeqTarai

tarai(x, y, z) =
    if y < x
        tarai(tarai(x - 1, y, z), tarai(y - 1, z, x), tarai(z - 1, x, y))
    else
        y
    end

end  # module SeqTarai

module BaseTarai

tarai(x, y, z) =
    if y < x
        a = Threads.@spawn tarai(x - 1, y, z)
        b = Threads.@spawn tarai(y - 1, z, x)
        c = tarai(z - 1, x, y)
        tarai(fetch(a)::Int, fetch(b)::Int, c)
    else
        y
    end

end  # module BaseTarai


module TapirTarai

using Base.Experimental: Tapir

tarai(x, y, z) =
    if y < x
        Tapir.@output a b c
        Tapir.@sync begin
            Tapir.@spawn a = tarai(x - 1, y, z)
            Tapir.@spawn b = tarai(y - 1, z, x)
            c = tarai(z - 1, x, y)
        end
        tarai(a, b, c)
    else
        y
    end

end  # module TapirTarai


module WSTarai

using Base.Experimental: Tapir
using TapirSchedulers

tarai(x, y, z) =
    if y < x
        Tapir.@output a b c
        Tapir.@sync WorkStealingTaskGroup() begin
            Tapir.@spawn a = tarai(x - 1, y, z)
            Tapir.@spawn b = tarai(y - 1, z, x)
            c = tarai(z - 1, x, y)
        end
        tarai(a, b, c)
    else
        y
    end

end  # module WSTarai

function setup(xyz = [(3, 1, 10)])
    suite = BenchmarkGroup()
    for (x::Int, y::Int, z::Int) in xyz
        s0 = suite["x=$x, y=$y, z=$z"] = BenchmarkGroup()
        s0["seq"] = @benchmarkable SeqTarai.tarai($x, $y, $z)
        s0["base"] = @benchmarkable BaseTarai.tarai($x, $y, $z)
        s0["tapir"] = @benchmarkable TapirTarai.tarai($x, $y, $z)
        s0["ws"] = @benchmarkable WSTarai.tarai($x, $y, $z)
    end
    return suite
end

function clear() end

end  # module BenchTarai
