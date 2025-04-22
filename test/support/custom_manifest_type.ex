defmodule CustomManifest do
  use Gno.Manifest.Type
  use Grax.Schema

  alias RDF.Graph

  alias Gno.TestNamespaces.EX

  schema EX.ManifestType < Gno.Manifest do
    property foo: EX.foo(), type: :string
  end

  def init_graph(_opts), do: {:ok, Graph.new({EX.S1, EX.P1, EX.O1})}

  def load_file(file, opts) do
    with {:ok, graph} <- super(file, opts) do
      {:ok, Graph.add(graph, {EX.S2, EX.P2, EX.O2})}
    end
  end

  def load_manifest(manifest, opts) do
    with {:ok, manifest} <- super(manifest, opts) do
      Grax.put(manifest, :foo, "bar")
    end
  end
end
