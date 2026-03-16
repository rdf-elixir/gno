defmodule Gno.MixProject do
  use Mix.Project

  @scm_url "https://github.com/rdf-elixir/gno"

  def project do
    [
      app: :gno,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),

      # Docs
      name: "Gno",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  defp deps do
    [
      rdf_ex_dep(:rdf, "~> 2.0"),
      rdf_ex_dep(:grax, "~> 0.5"),
      rdf_ex_dep(:sparql_client, "~> 0.5"),
      rdf_ex_dep(:sparql, "~> 0.3"),
      rdf_ex_dep(:dcat, "~> 0.1"),
      rdf_ex_dep(:prov, "~> 0.1"),
      rdf_ex_dep(:dcatr, "~> 0.1"),
      # we are using YuriTemplate, because we have it already as a dependency of Grax
      {:yuri_template, "~> 1.1"},
      {:uniq, "~> 0.6"},
      {:nimble_options, "~> 1.1"},
      {:tesla, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:hackney, "~> 1.15", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp rdf_ex_dep(dep, version) do
    case System.get_env("RDF_EX_PACKAGES_SRC") do
      "LOCAL" -> {dep, path: "../#{dep}"}
      _ -> {dep, version}
    end
  end

  defp docs do
    [
      main: "Gno",
      source_url: @scm_url,
      groups_for_modules: [
        Model: [
          Gno.Service,
          Gno.Store,
          Gno.Store.Adapter,
          Gno.Store.SPARQL.Operation
        ],
        Changeset: [
          Gno.Changeset,
          Gno.EffectiveChangeset,
          Gno.Changeset.Action,
          Gno.Changeset.Action.Graph
        ],
        Commit: [
          Gno.Commit,
          Gno.Commit.Processor,
          Gno.CommitOperation,
          Gno.CommitOperation.Type,
          Gno.CommitMiddleware,
          Gno.CommitLogger
        ],
        "Store Adapters": [
          Gno.Store.Adapters.Fuseki,
          Gno.Store.Adapters.Oxigraph,
          Gno.Store.Adapters.GraphDB
        ],
        Manifest: [
          Gno.Manifest,
          Gno.Manifest.Type,
          Gno.Manifest.Generator
        ],
        Setup: [
          Gno.Service.Setup,
          Gno.Service.Setup.Extension
        ],
        Namespaces: [
          Gno.NS,
          Gno.NS.Gno,
          Gno.NS.GnoA
        ]
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <script>mermaid.initialize({startOnLoad: true})</script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [
        check: :test
      ]
    ]
  end

  defp aliases do
    [
      check: [
        "clean",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test --warnings-as-errors"
      ]
    ]
  end
end
