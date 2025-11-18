defmodule Gno do
  @moduledoc """
  A unified API for managing RDF datasets as DCAT catalogs in various SPARQL triple stores.

  This module provides functions for executing various graph operations. By default,
  these functions target the dataset graph. This is the standard behavior for most
  operations, but there are limitations with certain SPARQL update operations.

  For SPARQL update operations (`INSERT`, `DELETE`, `UPDATE`), the graph must be
  specified in the query itself because SPARQL does not support executing these
  operations on a specific graph through protocol parameters.

  For data operations (`INSERT DATA`, `DELETE DATA`) where the data is specified as a `RDF.Graph`
  and graph store operations (LOAD, CLEAR, etc.), the `:graph` option works as expected.

      # Execute a SPARQL SELECT query
      Gno.select("SELECT * WHERE { ?s ?p ?o }")

      # Insert RDF data
      Gno.insert_data(graph)


  ## Options

  The graph operation functions in this module accept the following options:

  - `:service` - Use a specific service instead of the default one from the manifest. This allows
    operations to target different repositories.

  - `:store` - Use a specific store directly, bypassing service-level abstractions. When using
    this option, the `:graph` option must specify concrete graph IRIs rather than symbolic
    names like `:primary` or `:repo_manifest`.
    This option is not supported on `commit/2` and `effective_changeset/2`.

  - `:graph` - The target graph for the operation, which is processed through `Gno.Service.graph_name/2`
    to support special values like `:default` and `:repo_manifest`.
    Defaults to `Gno.default_target_graph/0` for most operations, except for `create/2`, `drop/2`, and
    `clear/2` which require an explicit graph argument, and for the SPARQL update operations (see above).

  - Additional options are passed to the underlying `SPARQL.Client` function. See the `SPARQL.Client`
    documentation for available options.


  ## Configuration

  See the `Gno.Manifest` module for details on configuring the service and its components.

  """

  import RDF.Namespace
  act_as_namespace Gno.NS.Gno

  alias Gno.{Service, Store}
  alias Gno.Store.SPARQL.Operation
  import Gno.Utils, only: [bang!: 2]

  def ansi_enabled? do
    Application.get_env(:gno, :ansi_enabled, true)
  end

  def default_target_graph do
    Application.get_env(:gno, :default_target_graph, :default)
  end

  defdelegate manifest(opts \\ []), to: Gno.Manifest
  defdelegate manifest!(opts \\ []), to: Gno.Manifest

  defdelegate service(opts \\ []), to: Gno.Manifest
  defdelegate service!(opts \\ []), to: Gno.Manifest

  defdelegate store(opts \\ []), to: Gno.Manifest
  defdelegate store!(opts \\ []), to: Gno.Manifest

  defdelegate repository(opts \\ []), to: Gno.Manifest
  defdelegate repository!(opts \\ []), to: Gno.Manifest

  @doc """
  Returns the specified graph(s) from the store.

  ## Arguments

    - `graph_spec` - Can be:
      - Any atom value supported by `Gno.Service.graph_name/2` (e.g., `:default`, `:primary`, `:repo_manifest`)
      - A single graph IRI - Returns that specific graph
      - A list of graph IRIs - Returns RDF.Dataset with those graphs (future)

    Note: The available atom values depend on the Repository implementation and can be
    extended by subclasses overriding `graph_name/2`.

  ## Examples

      # Get repository metadata graph
      {:ok, graph} = Gno.graph(:repo_manifest)
      
      # Get default graph content
      {:ok, graph} = Gno.graph(:default)
      
      # Get specific graph by IRI
      {:ok, graph} = Gno.graph("http://example.com/my-graph")
  """
  @spec graph(atom() | RDF.IRI.coercible(), keyword()) ::
          {:ok, RDF.Graph.t()} | {:error, any()}
  def graph(graph, opts \\ [])

  def graph(graph, opts) do
    execute(Gno.QueryUtils.graph_query(), Keyword.put(opts, :graph, graph))
  end

  @doc """
  Same as `graph/2` but raises on errors.
  """
  def graph!(graph_spec, opts \\ []), do: bang!(&graph/2, [graph_spec, opts])

  def graph_name(graph_id \\ default_target_graph(), opts \\ []) do
    Service.graph_name(service!(opts), graph_id)
  end

  @update_warning """
  > ### Important {: .warning}
  >
  > SPARQL update queries cannot be executed on a specific graph by default, so
  > the graph must be specified in the query.
  """

  @doc """
  Executes a SPARQL operation.

  #{@update_warning}

  ## Examples

      operation = Operation.select("SELECT * WHERE { ?s ?p ?o }")
      Gno.execute(operation)

      # With specific graph
      Gno.execute(operation, graph: "http://example.com/graph")
  """
  @spec execute(Operation.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def execute(operation, opts \\ []) do
    {service, opts} = Keyword.pop(opts, :service)
    {store, opts} = Keyword.pop(opts, :store)

    cond do
      service && store ->
        raise ArgumentError, "Cannot specify both :service and :store options"

      store ->
        {graph, opts} = Keyword.pop(opts, :graph)
        Store.handle_sparql(operation, store, graph, opts)

      service ->
        Service.handle_sparql(operation, service, opts)

      true ->
        with {:ok, service} <- service(opts) do
          Service.handle_sparql(operation, service, opts)
        end
    end
  end

  @doc """
  Same as `execute/2` but raises on errors.
  """
  def execute!(operation, opts \\ []), do: bang!(&execute/2, [operation, opts])

  @doc """
  Executes a SPARQL SELECT query.

  See the `Gno` moduledoc for available options.

  ## Examples

      Gno.select("SELECT * WHERE { ?s ?p ?o }")

      Gno.select("SELECT * WHERE { ?s ?p ?o }", graph: "http://example.com/graph")
  """
  def select(query, opts \\ []) do
    with {:ok, operation} <- Operation.select(query, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `select/2` but raises on errors.
  """
  def select!(query, opts \\ []), do: bang!(&select/2, [query, opts])

  @doc """
  Executes a SPARQL ASK query.

  ## Examples

      Gno.ask("ASK WHERE { <http://example.org/resource> ?p ?o }")

      Gno.ask("ASK WHERE { ?s ?p ?o }", graph: "http://example.com/graph")
  """
  def ask(query, opts \\ []) do
    with {:ok, operation} <- Operation.ask(query, opts),
         {:ok, %SPARQL.Query.Result{results: result}} <- execute(operation, opts) do
      {:ok, result}
    end
  end

  @doc """
  Same as `ask/2` but raises on errors.
  """
  def ask!(query, opts \\ []), do: bang!(&ask/2, [query, opts])

  @doc """
  Executes a SPARQL CONSTRUCT query.

  ## Examples

      Gno.construct("CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }")

      Gno.construct(
        "CONSTRUCT { ?s <http://example.org/name> ?name }
         WHERE { ?s <http://xmlns.com/foaf/0.1/name> ?name }",
        graph: "http://example.com/graph"
      )
  """
  def construct(query, opts \\ []) do
    with {:ok, operation} <- Operation.construct(query, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `construct/2` but raises on errors.
  """
  def construct!(query, opts \\ []), do: bang!(&construct/2, [query, opts])

  @doc """
  Executes a SPARQL DESCRIBE query.

  ## Examples

      Gno.describe("DESCRIBE <http://example.org/resource>")

      Gno.describe("DESCRIBE ?s WHERE { ?s a <http://xmlns.com/foaf/0.1/Person> }",
                    graph: "http://example.com/graph")
  """
  def describe(query, opts \\ []) do
    with {:ok, operation} <- Operation.describe(query, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `describe/2` but raises on errors.
  """
  def describe!(query, opts \\ []), do: bang!(&describe/2, [query, opts])

  @doc """
  Executes a SPARQL INSERT query.

  #{@update_warning}

  ## Examples

      # Insert data with a WHERE clause
      query = \"\"\"
      PREFIX dc: <http://purl.org/dc/elements/1.1/>

      INSERT
      { GRAPH <http://example/bookStore> { ?book dc:title "New Title" } }
      WHERE
      { GRAPH <http://example/bookStore> { ?book dc:title "Old Title" } }
      \"\"\"
      Gno.insert(query)
  """
  def insert(update, opts \\ []) do
    with {:ok, operation} <- Operation.insert(update, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `insert/2` but raises on errors.
  """
  def insert!(update, opts \\ []), do: bang!(&insert/2, [update, opts])

  @doc """
  Executes a SPARQL DELETE query.

  #{@update_warning}

  ## Examples

      \"\"\"
      PREFIX dc: <http://purl.org/dc/elements/1.1/>

      DELETE
      { GRAPH <http://example/bookStore> { ?book dc:title "Old Title" } }
      WHERE
      { GRAPH <http://example/bookStore> { ?book dc:title "Old Title" } }
      \"\"\"
      |> Gno.delete()
  """
  def delete(update, opts \\ []) do
    with {:ok, operation} <- Operation.delete(update, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `delete/2` but raises on errors.
  """
  def delete!(update, opts \\ []), do: bang!(&delete/2, [update, opts])

  @doc """
  Executes a combined SPARQL DELETE and INSERT query.

  #{@update_warning}

  ## Examples

      \"\"\"
      PREFIX dc: <http://purl.org/dc/elements/1.1/>

      DELETE
      { GRAPH <http://example/bookStore> { ?book dc:title "Old Title" } }
      INSERT
      { GRAPH <http://example/bookStore> { ?book dc:title "New Title" } }
      WHERE
      { GRAPH <http://example/bookStore> { ?book dc:title "Old Title" } }
      \"\"\"
      |> Gno.update()
  """
  def update(update, opts \\ []) do
    with {:ok, operation} <- Operation.update(update, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `update/2` but raises on errors.
  """
  def update!(update, opts \\ []), do: bang!(&update/2, [update, opts])

  @doc """
  Inserts RDF data directly.

  ## Examples

      graph = RDF.Graph.new([
        {EX.S, EX.p, EX.O}
      ])
      Gno.insert_data(graph)

      Gno.insert_data(graph, graph: "http://example.com/graph")

      description = RDF.Description.new(EX.S, EX.p, EX.O)
      Gno.insert_data(description)
  """
  def insert_data(data, opts \\ []) do
    with {:ok, operation} <- Operation.insert_data(data, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `insert_data/2` but raises on errors.
  """
  def insert_data!(data, opts \\ []), do: bang!(&insert_data/2, [data, opts])

  @doc """
  Deletes RDF data directly.

  ## Examples

      graph = RDF.Graph.new([
        {EX.S, EX.p, EX.O}
      ])
      Gno.delete_data(graph)

      Gno.delete_data(graph, graph: "http://example.com/graph")

      description = RDF.Description.new(EX.S, EX.p, EX.O)
      Gno.delete_data(description)
  """
  def delete_data(data, opts \\ []) do
    with {:ok, operation} <- Operation.delete_data(data, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `delete_data/2` but raises on errors.
  """
  def delete_data!(data, opts \\ []), do: bang!(&delete_data/2, [data, opts])

  @doc """
  Loads RDF data from a dereferenced IRI.

  Retrieves RDF data from the specified IRI and loads it into the dataset or a specific graph.

  ## Examples

      Gno.load("http://dbpedia.org/resource/Berlin")

      Gno.load("http://dbpedia.org/resource/Berlin", graph: "http://example.com/graph")

      Gno.load("http://dbpedia.org/resource/Berlin",
               graph: "http://example.com/graph",
               silent: true)
  """
  def load(iri, opts \\ []) do
    with {:ok, operation} <- Operation.load(iri, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `load/2` but raises on errors.
  """
  def load!(iri, opts \\ []), do: bang!(&load/2, [iri, opts])

  @doc """
  Clears a graph.

  Removes all triples from a graph without removing the graph itself.

  ## Arguments

  - `graph` - The graph to clear. This can be a URI string, `RDF.IRI`, vocabulary namespace term,
    or one of the special values `:default`, `:named`, or `:all`. The special value `:all` clears
    all graphs in the dataset.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      Gno.clear(:default)

      Gno.clear("http://example.com/graph")

      Gno.clear(:all)

      Gno.clear("http://example.com/graph", silent: true)
  """
  def clear(graph, opts \\ []) do
    opts = Keyword.put(opts, :graph, graph)

    with {:ok, operation} <- Operation.clear(opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `clear/2` but raises on errors.
  """
  def clear!(graph, opts \\ []), do: bang!(&clear/2, [graph, opts])

  @doc """
  Drops a graph.

  Removes a graph completely, including all its triples.

  ## Arguments

  - `graph` - The graph to drop. This can be a URI string, `RDF.IRI`, vocabulary namespace term,
    or one of the special values `:default`, `:named`, or `:all`. The special value `:all` drops
    all graphs in the dataset.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      # Drop the default graph
      Gno.drop(:default)

      # Drop a specific graph
      Gno.drop("http://example.com/graph")

      # Drop all graphs
      Gno.drop(:all)

      # Drop with silent option
      Gno.drop("http://example.com/graph", silent: true)
  """
  def drop(graph, opts \\ []) do
    opts = Keyword.put(opts, :graph, graph)

    with {:ok, operation} <- Operation.drop(opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `drop/2` but raises on errors.
  """
  def drop!(graph, opts \\ []), do: bang!(&drop/2, [graph, opts])

  @doc """
  Creates a graph.

  Creates a new graph. If the graph already exists, an error will be raised
  unless the `:silent` option is set to true.

  ## Arguments

  - `graph` - The graph to create. This must be a URI string, `RDF.IRI`, or vocabulary namespace term.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      Gno.create("http://example.com/graph")

  """
  def create(graph, opts \\ []) do
    opts = Keyword.put(opts, :graph, graph)

    with {:ok, operation} <- Operation.create(opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `create/2` but raises on errors.
  """
  def create!(graph, opts \\ []), do: bang!(&create/2, [graph, opts])

  @doc """
  Adds statements from one graph to another.

  This operation adds all statements from the `source` graph to the `destination` graph
  without removing any existing statements in the destination.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      # Add statements from one graph to another
      Gno.add("http://example.com/graph1", "http://example.com/graph2")

      # Add statements from the default graph to the datasets primary graph
      Gno.add(:default, :primary)

      Gno.add(
        "http://example.com/graph1",
        "http://example.com/graph2",
        silent: true
      )
  """
  def add(source, target, opts \\ []) do
    with {:ok, operation} <- Operation.add(source, target, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `add/1` but raises on errors.
  """
  def add!(source, target, opts \\ []), do: bang!(&add/3, [source, target, opts])

  @doc """
  Copies statements from one graph to another, replacing all statements in the destination.

  This operation replaces all statements in the `destination` graph with the statements
  from the `source` graph.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      # Copy statements from one graph to another
      Gno.copy("http://example.com/graph1", "http://example.com/graph2")

      # Copy statements from the default graph to a named graph
      Gno.copy(:default, "http://example.com/graph")

  """
  def copy(source, target, opts \\ []) do
    with {:ok, operation} <- Operation.copy(source, target, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `copy/1` but raises on errors.
  """
  def copy!(source, target, opts \\ []), do: bang!(&copy/3, [source, target, opts])

  @doc """
  Moves statements from one graph to another, removing them from the source.

  This operation moves all statements from the `source` graph to the `destination` graph,
  removing them from the source graph.

  > ### Warning {: .warning}
  >
  > All previous statements in the destination graph will be removed.

  ## Options

  Besides the general options, the following options are supported:

  - `:silent` - Whether to suppress errors (default: false)

  ## Examples

      # Move statements from one graph to another
      Gno.move("http://example.com/graph1", "http://example.com/graph2")

      # Move statements from the default graph to a named graph
      Gno.move(:default, "http://example.com/graph")

  """
  def move(source, target, opts \\ []) do
    with {:ok, operation} <- Operation.move(source, target, opts) do
      execute(operation, opts)
    end
  end

  @doc """
  Same as `move/1` but raises on errors.
  """
  def move!(source, target, opts \\ []), do: bang!(&move/3, [source, target, opts])

  @doc """
  Creates a new `Gno.Changeset`.

  ## Examples

      iex> Gno.changeset(add: EX.S |> EX.p(EX.O))
      {:ok, %Gno.Changeset{add: RDF.graph(EX.S |> EX.p(EX.O))}}
  """
  defdelegate changeset(changes), to: Gno.Changeset, as: :new

  def changeset!(changes), do: bang!(&changeset/1, [changes])

  @doc """
  Creates an `Gno.EffectiveChangeset`.

  ## Examples

      iex> Gno.insert_data(EX.S |> EX.p(EX.O1))
      iex> Gno.effective_changeset(add: EX.S |> EX.p([EX.O1, EX.O2]))
      {:ok, %Gno.EffectiveChangeset{add: RDF.graph(EX.S |> EX.p(EX.O2))}}
  """
  def effective_changeset(changes, opts \\ []) do
    with {:ok, service, _opts} <- resolve_service(opts) do
      Gno.EffectiveChangeset.Query.call(service, changes)
    end
  end

  def effective_changeset!(changes, opts \\ []),
    do: bang!(&effective_changeset/2, [changes, opts])

  def commit(changes, opts \\ []) do
    with {:ok, service, opts} <- resolve_service(opts),
         {:ok, processor} <- Gno.Commit.Processor.new(service),
         {:ok, commit, _processor} <- Gno.Commit.Processor.execute(processor, changes, opts) do
      {:ok, commit}
    end
  end

  def commit!(changes, opts \\ []), do: bang!(&commit/2, [changes, opts])

  def setup(opts \\ []) do
    with {:ok, service, opts} <- resolve_service(opts) do
      Gno.Service.Setup.setup(service, opts)
    end
  end

  def setup!(opts \\ []), do: bang!(&setup/1, [opts])

  defp resolve_service(opts) do
    case Keyword.pop(opts, :service) do
      {nil, opts} -> with {:ok, service} <- service(opts), do: {:ok, service, opts}
      {service, opts} -> {:ok, service, opts}
    end
  end
end
