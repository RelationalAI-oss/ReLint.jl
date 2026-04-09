# Rule hooks
# ==========

# TODO: `string_literal` syntax class
@define_rule_hook :exclude_files begin
    args = @pattern [{files}...]

    pre_check = @check [:files] begin
        file_names = map(s -> s.children[1].val, files.src)
        if any(contains.(current_file(), file_names))
            skip_match()
        end
    end

    post_check = nothing
end

@define_rule_hook :only_in_dirs begin
    args = @pattern [{dirs}...]

    pre_check = @check [:dirs] begin
        dir_names = map(s -> s.children[1].val, dirs.src)
        if !any(contains.(current_file(), dir_names))
            skip_match()
        end
    end

    post_check = nothing
end
