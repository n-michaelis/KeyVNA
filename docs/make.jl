using Documenter

include("../src/KeyVNA.jl")
using .KeyVNA

# makedocs(
#     sitename="KeyVNA Documentation",
#     pages = [
#         "setup_file.md",
#         "Setup File" => "setup_file.md",
#         "Subsection" => []
#     ]
# )


format = Documenter.HTML(edit_link = "master",
                         prettyurls = get(ENV, "CI", nothing) == "true"
)

About = "About" => "index.md"

SetupFile = "Setup File" => "setup_file.md"

GettingStarted = "Getting Started" => "getting_started.md"

Methods = "Methods" => "methods.md"

License = "License" => "license.md"

PAGES = [
    About,
    Methods,
    SetupFile,
    GettingStarted,
    License
    ]

makedocs(
    modules = [KeyVNA],
    sitename = "KeyVNA.jl",
    # authors = "Christof Stocker",
    format = format,
    checkdocs = :exports,
    pages = PAGES
)

# operations_cb()

# deploydocs(repo = "github.com/da-boi/KeyVNA.jl")