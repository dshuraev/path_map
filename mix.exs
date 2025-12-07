defmodule PathMap.MixProject do
  use Mix.Project

  def project do
    [
      app: :path_map,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "PathMap",
      source_url: "https://github.com/dshuraev/path_map",
      docs: &docs/0,
      package: package()
    ]
  end

  def cli do
    [preferred_envs: [coverage: :test]]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp package() do
    [
      name: "path_map",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/dshuraev/path_map"}
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
end
