is_tracing() = false
enable_tracing() = @eval (is_tracing() = true; refresh(); is_tracing())
disable_tracing() = @eval (is_tracing() = false; refresh(); is_tracing())

macro trace(args...)
    quote
        if is_tracing()
            Recalls.@note($(map(esc, args)...))
        end
        nothing
    end
end
