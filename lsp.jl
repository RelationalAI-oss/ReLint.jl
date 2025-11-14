using JSON3
using ReLint

const Range = Dict{Symbol, Dict{Symbol, Int}}
#                  start/end   line/character
Range(start::NTuple{2, Int}, stop::NTuple{2, Int}) = Range(
    :start => Dict(:line => start[1] - 1, :character => start[2] - 1),
    :end => Dict(:line => stop[1] - 1, :character => stop[2] - 1),
)

struct Diagnostic
    range::Range
    severity::Int # 1: Error, 2: Warning, 3: Information, 4: Hint
    message::String
    source::String
    code::Union{String, Int, Nothing}
end


function lint_report_to_lsp_diagnostic(report::ReLint.LintRuleReport)::Diagnostic
    severity = ReLint.is_fatal(report) ?
        1 :
        ReLint.is_violation(report) ?
        1 :
        ReLint.is_recommendation(report) ?
        3 : 2

    # TODO: Should be length of the problematic token
    range = Range((report.line, report.column), (report.line, report.column))

    return Diagnostic(
        range,
        severity,
        report.msg,
        "ReLint",
        string(typeof(report.rule)) # Rule type as code
    )
end
function send_lsp_message(message_dict::Dict)
    json_message = JSON3.write(message_dict)
    content_length = sizeof(json_message)
    print(stdout, "Content-Length: $(content_length)\r\n")
    print(stdout, "Content-Type: application/json\r\n\r\n")
    print(stdout, json_message)
    return flush(stdout)
end
function read_lsp_message()::Union{Dict, Nothing}
    headers = Dict{String, String}()
    line = readline(stdin)

    while strip(line) != ""
        parts = split(line, ":", limit = 2)
        if length(parts) == 2
            headers[strip(parts[1])] = strip(parts[2])
        end
        line = readline(stdin)
    end

    if haskey(headers, "Content-Length")
        content_length = parse(Int, headers["Content-Length"])
        content_bytes = read(stdin, content_length)
        return JSON3.read(String(content_bytes))
    end
    return nothing
end
function publish_diagnostics(uri::String, text::String, lint_context::ReLint.LintContext)
    lsp_diagnostics = try
        ReLint.lint_text(text; filename = uri, context = lint_context) .|> lint_report_to_lsp_diagnostic
    catch e
        io = IOBuffer()
        Base.showerror(io, e)
        [Diagnostic(Range((1, 1), (1, 1)), 3, String(take!(io)), uri, "ERROR")]
    end

    return send_lsp_message(
        Dict(
            :jsonrpc => "2.0",
            :method => "textDocument/publishDiagnostics",
            :params => Dict(
                :uri => uri,
                :diagnostics => lsp_diagnostics
            )
        )
    )
end

documents = Dict{String, String}()
lint_context = ReLint.LintContext()

println("Starting server")

while true
    message = read_lsp_message()
    isnothing(message) && continue

    method = get(message, :method, "")
    params = get(message, :params, Dict())
    id = get(message, :id, nothing) # Requests have an ID, notifications don't

    if method == "initialize"
        capabilities = Dict(
            :textDocumentSync => Dict(:openClose => true, :change => 1), # 1 for full text sync
            :capabilities => Dict(
                :textDocumentSync => Dict(
                    :openClose => true,
                    :change => 1 # Full text synchronization
                ),
                :diagnosticProvider => Dict(
                    :interFileDependencies => false,
                    :workspaceDiagnostics => false
                )
            )
        )
        send_lsp_message(Dict(:jsonrpc => "2.0", :id => id, :result => capabilities))
    elseif method == "initialized"
        # good
    elseif method == "textDocument/didOpen"
        uri = params[:textDocument][:uri]
        text = params[:textDocument][:text]
        documents[uri] = text
        publish_diagnostics(uri, text, lint_context)
    elseif method == "textDocument/didChange"
        uri = params[:textDocument][:uri]
        # Assuming full text sync (change = 1)
        text = params[:contentChanges][1][:text]
        documents[uri] = text
        publish_diagnostics(uri, text, lint_context)
    elseif method == "textDocument/didClose"
        uri = params[:textDocument][:uri]
        delete!(documents, uri)
        # Clear diagnostics for the closed file
        send_lsp_message(
            Dict(
                :jsonrpc => "2.0",
                :method => "textDocument/publishDiagnostics",
                :params => Dict(
                    :uri => uri,
                    :diagnostics => []
                )
            )
        )
    elseif method == "exit" || method == "shutdown"
        break
    end
end
