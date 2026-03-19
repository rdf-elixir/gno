defmodule GnoCase do
  @moduledoc """
  Common `ExUnit.CaseTemplate` for Gno tests with common imports, aliases and helpers.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use RDF

      import unquote(__MODULE__)
      import RDF, only: [iri: 1, literal: 1, bnode: 1]
      import RDF.Test.Assertions
      import Gno.TestFactories

      alias RDF.{IRI, BlankNode, Literal, Graph}
      alias Gno.{Manifest, Service, Store, Repository, Dataset, Changeset}
      alias Gno.Store.Adapters.{Fuseki, Oxigraph, Qlever, GraphDB}
      alias Gno.NS.GnoA
      alias Gno.TestData
      alias Gno.TestNamespaces.EX
      @compile {:no_warn_undefined, Gno.TestNamespaces.EX}

      setup :clean_manifest_cache
    end
  end

  alias RDF.{Graph, IRI}

  def clean_manifest_cache(_) do
    DCATR.Manifest.Cache.clear()
  end

  def configured_store_adapter do
    "config/gno/test/service.ttl"
    |> RDF.read_file!()
    |> Graph.query([
      {:_service, Gno.serviceStore(), :store?}
    ])
    |> case do
      [%{store: store}] ->
        store
        |> IRI.to_string()
        |> String.split("/")
        |> List.last()
        |> Gno.Store.Adapter.type() || Gno.Store

      [] ->
        raise "No configured store adapter found"

      multiple ->
        raise "Multiple configured store adapters found: #{inspect(multiple)}"
    end
  end

  def with_application_env(app, key, value, fun) do
    original = Application.get_env(app, key, :__undefined__)
    :ok = Application.put_env(app, key, value)

    try do
      fun.()
    after
      if original == :__undefined__ do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, original)
      end
    end
  end
end
