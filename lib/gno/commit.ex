defmodule Gno.Commit do
  @moduledoc """
  The result of a successful commit operation.

  Created during the prepare step of the `Gno.Commit.Processor` pipeline.
  The commit's `__id__` is a UUID-based IRI generated automatically.

  ## Fields

  - `time` — `DateTime` when the commit was created (`prov:endedAtTime`)
  - `changeset` — the `Gno.EffectiveChangeset` that was applied
  """

  use Grax.Schema

  alias Gno.EffectiveChangeset

  import Gno.Utils, only: [bang!: 2]

  schema Gno.Commit do
    property time: PROV.endedAtTime(), type: :date_time

    field :changeset
  end

  @doc """
  Creates a new commit from an `Gno.EffectiveChangeset` or keyword arguments.

  Automatically generates a UUID-based commit ID and sets the timestamp.
  """
  def new(changes, args \\ [])

  def new(%EffectiveChangeset{} = changeset, args) do
    args =
      args
      |> Keyword.put_new_lazy(:time, fn -> DateTime.utc_now() end)

    build(init_id(changeset), args)
  end

  def new(args, []) do
    with {:ok, changeset, args} <- EffectiveChangeset.extract(args) do
      new(changeset, args)
    end
  end

  def new!(changes, args \\ []), do: bang!(&new/2, [changes, args])

  defp init_id(_changeset), do: RDF.iri(Uniq.UUID.uuid4(:urn))

  def validate(%__MODULE__{} = commit) do
    Grax.validate(commit)
  end
end
