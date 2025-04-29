defmodule Gno.MixProject do
  use Mix.Project

  def project do
    [
      app: :gno,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Gno.Application, []}
    ]
  end

  defp deps do
    [
      rdf_ex_dep(:rdf, "~> 2.0"),
      rdf_ex_dep(:grax, "~> 0.5"),
      rdf_ex_dep(:sparql_client, "~> 0.5"),
      rdf_ex_dep(:sparql, "~> 0.3"),
      rdf_ex_dep(:dcat, "~> 0.1"),
      # we are using YuriTemplate, because we have it already as a dependency of Grax
      {:yuri_template, "~> 1.1"},
      {:hackney, "~> 1.15", only: [:dev, :test]}
    ]
  end

  defp rdf_ex_dep(dep, version) do
    case System.get_env("RDF_EX_PACKAGES_SRC") do
      "LOCAL" -> {dep, path: "../#{dep}"}
      _ -> {dep, version}
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
