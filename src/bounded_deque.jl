# Based on unbounded work-stealing deque:
# https://github.com/tkf/ConcurrentCollections.jl/blob/master/src/workstealing.jl

struct CircularVector{T} <: AbstractVector{T}
    log2length::Int
    data::Vector{T}
end

function CircularVector{T}(log2length::Int) where {T}
    @assert log2length >= 0
    data = Vector{T}(undef, 1 << log2length)
    T <: Signed && fill!(data, typemin(T))
    return CircularVector{T}(log2length, data)
end

Base.size(A::CircularVector{T}) where {T} = size(A.data)

@noinline function _check_data_length(A::CircularVector)
    @assert 1 << A.log2length == length(A.data)
end

Base.@propagate_inbounds function indexof(A::CircularVector, i::Int)
    @boundscheck _check_data_length(A)
    return (i - 1) & ((1 << A.log2length) - 1) + 1
end

Base.@propagate_inbounds Base.getindex(A::CircularVector, i::Int) = A.data[indexof(A, i)]

Base.@propagate_inbounds function Base.setindex!(A::CircularVector, v, i::Int)
    v = convert(eltype(A), v)
    A.data[indexof(A, i)] = v
end

mutable struct BoundedWorkStealingDeque{T}
    buffer::CircularVector{T}
    @atomic top::Int
    @atomic bottom::Int
    # TODO: pad
end

BoundedWorkStealingDeque{T}(size::Integer) where {T} =
    BoundedWorkStealingDeque{T}(CircularVector{T}(ceil(Int, log2(size))), 1, 1)

Base.eltype(::Type{BoundedWorkStealingDeque{T}}) where {T} = T

function Base.length(deque::BoundedWorkStealingDeque)
    bottom = @atomic deque.bottom
    top = @atomic deque.top
    return bottom - top
end

function isfull(deque::BoundedWorkStealingDeque)
    buffer = deque.buffer
    return length(deque) >= length(buffer) - 1
end

function trypush!(deque::BoundedWorkStealingDeque, v)
    v = convert(eltype(deque), v)
    bottom = @atomic deque.bottom
    top = @atomic deque.top
    buffer = deque.buffer
    current_size = bottom - top
    if current_size >= length(buffer) - 1
        return false
    end
    buffer[bottom] = v
    bottom += 1
    @atomic deque.bottom = bottom
    return true
end

function maybepop!(deque::BoundedWorkStealingDeque)
    bottom = @atomic deque.bottom
    buffer = deque.buffer
    bottom -= 1
    @atomic deque.bottom = bottom
    top = @atomic deque.top
    next_size = bottom - top
    if next_size < 0
        @atomic deque.bottom = top
        return nothing
    end
    r = Some(buffer[bottom])
    if next_size > 0
        return r
    end
    bottom = top + 1
    if !@atomicreplace(deque.top, top => top + 1)[2]
        r = nothing
    end
    @atomic deque.bottom = bottom
    return r
end

function maybepopfirst!(deque::BoundedWorkStealingDeque)
    top = @atomic deque.top
    bottom = @atomic deque.bottom
    buffer = deque.buffer
    current_size = bottom - top
    if current_size <= 0
        return nothing
    end
    r = Some(buffer[top])
    if @atomicreplace(deque.top, top => top + 1)[2]
        return r
    else
        return nothing
    end
end

function Base.pop!(deque::BoundedWorkStealingDeque)
    r = maybepop!(deque)
    if r === nothing
        error("deque is empty")
    else
        return something(r)
    end
end

function Base.popfirst!(deque::BoundedWorkStealingDeque)
    r = maybepopfirst!(deque)
    if r === nothing
        error("deque is empty")
    else
        return something(r)
    end
end
