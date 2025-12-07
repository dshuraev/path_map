defmodule PathMap.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :path_map,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "PathMap",
      source_url: "https://github.com/dshuraev/path_map",
      docs: docs(),
      package: package()
    ]
  end

  def cli do
    [preferred_envs: [coverage: :test]]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/path_map",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "LICENSE"],
      filter_modules: &filter_docs_modules/2
    ]
  end

  defp package() do
    [
      name: "path_map",
      description: "Deterministic helpers for traversing nested maps with explicit key paths.",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/dshuraev/path_map",
        "Hexdocs" => "https://hex.pm/packages/path_map"
      },
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp filter_docs_modules(module, _metadata) do
    not String.starts_with?(Atom.to_string(module), "Elixir.Mix.Tasks.")
  end
end
