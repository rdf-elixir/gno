defmodule Gno.Changeset do
  alias Gno.Changeset.{Action, Validation, Helper}
  alias RDF.Graph

  import Gno.Utils, only: [bang!: 2]
  import Action, only: [is_action_map: 1]
  import Helper

  @fields Action.fields() -- [:overwrite]

  defstruct @fields

  @type t :: %__MODULE__{
          add: Graph.t() | nil,
          update: Graph.t() | nil,
          replace: Graph.t() | nil,
          remove: Graph.t() | nil
        }

  def fields, do: @fields

  @doc """
  Creates the empty changeset.
  """
  @spec empty :: t()
  def empty, do: %__MODULE__{}

  @doc """
  Creates a new valid changeset.
  """
  @spec new(t() | keyword, opts :: keyword) :: {:ok, t()} | {:error, any()}
  def new(changes, opts \\ [])

  def new(%__MODULE__{} = changeset, opts) do
    validate(changeset, opts)
  end

  def new(%{} = action_map, opts) when is_action_map(action_map) do
    %__MODULE__{
      add: Action.graph(Map.get(action_map, :add), :add),
      update: Action.graph(Map.get(action_map, :update), :update),
      replace: Action.graph(Map.get(action_map, :replace), :replace),
      remove: Action.graph(Map.get(action_map, :remove), :remove)
    }
    |> validate(opts)
  end

  def new(args, opts) when is_list(args) do
    with {:ok, changeset, _} <- extract(args ++ opts) do
      {:ok, changeset}
    end
  end

  @doc """
  Creates a new valid changeset.

  As opposed to `new/1` this function fails in error cases.
  """
  @spec new!(t() | keyword, keyword) :: t()
  def new!(args, opts \\ []), do: bang!(&new/2, [args, opts])

  @doc """
  Extracts a `Gno.Changeset` from the given keywords and returns it with the remaining unprocessed keywords.
  """
  def extract(keywords), do: Helper.extract(__MODULE__, keywords)

  @doc """
  Validates the given changeset structure.

  If valid, the given structure is returned unchanged in an `:ok` tuple.
  Otherwise, an `:error` tuple is returned.
  """
  def validate(%__MODULE__{} = changeset, opts \\ []), do: Validation.validate(changeset, opts)

  @doc """
  Returns if the given changeset is empty.
  """
  def empty?(%__MODULE__{add: nil, update: nil, replace: nil, remove: nil}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Returns a combined graph of all statements that will be inserted by the changeset.
  """
  def inserts(%__MODULE__{} = changeset), do: Helper.inserts(changeset)

  @doc """
  Returns a combined graph of all statements that will be deleted by the changeset.
  """
  def deletes(%__MODULE__{remove: nil}), do: RDF.graph()
  def deletes(%__MODULE__{remove: remove}), do: remove

  @doc """
  Inverts the changeset.
  """
  def invert(%__MODULE__{} = changeset) do
    %__MODULE__{
      add: changeset.remove,
      remove:
        changeset.add
        |> graph_add(changeset.update)
        |> graph_add(changeset.replace)
    }
  end

  def to_rdf(%__MODULE__{} = changeset, opts \\ []), do: Helper.to_rdf(changeset, opts)

  def from_rdf(%RDF.Dataset{} = dataset, opts \\ []),
    do: Helper.from_rdf(dataset, __MODULE__, opts)

  @doc """
  Updates the changes of a changeset.
  """
  def update(%__MODULE__{} = changeset, changes) do
    do_update(changeset, changes)
  end

  def update(changeset, changes) do
    with {:ok, changeset} <- new(changeset) do
      do_update(changeset, changes)
    else
      {:error, error} -> raise error
    end
  end

  defp do_update(changeset, [{action, update}]) do
    update = Action.graph(update, action)

    if update && not Graph.empty?(update) do
      Enum.reduce(
        @fields -- [action],
        Map.update!(changeset, action, &graph_add(&1, update)),
        fn other_actions, changeset ->
          Map.update!(changeset, other_actions, &graph_delete(&1, update))
        end
      )
    else
      changeset
    end
  end

  defp do_update(changeset, %_{} = change_struct) do
    do_update(changeset, Map.from_struct(change_struct))
  end

  defp do_update(changeset, changes) when is_list(changes) or is_map(changes) do
    changes
    |> Enum.filter(fn {action, _} -> action in @fields end)
    |> Enum.reduce(changeset, &do_update(&2, [&1]))
  end
end
