defmodule Mix.Tasks.Coverage do
  use Mix.Task

  @shortdoc "Run tests with coverage and generate HTML report in cover/"

  @moduledoc """
  Runs `mix test --cover` to produce a coverage report.

  The HTML report is written under `cover/` (open `cover/index.html`).

  Any arguments are forwarded to `mix test`, e.g. `mix coverage --trace`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.shell().info("Running tests with coverage (report in cover/)...")
    Mix.Task.run("test", ["--cover" | args])
    Mix.shell().info("Coverage report written to #{Path.join(File.cwd!(), "cover")}")
  end
end
