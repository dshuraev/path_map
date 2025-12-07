defmodule Mix.Tasks.Coverage do
  use Mix.Task

  @shortdoc "Run tests with coverage and generate HTML report in cover/"

  @moduledoc false

  @impl Mix.Task
  def run(args) do
    Mix.shell().info("Running tests with coverage (report in cover/)...")
    Mix.Task.run("test", ["--cover" | args])
    Mix.shell().info("Coverage report written to #{Path.join(File.cwd!(), "cover")}")
  end
end
