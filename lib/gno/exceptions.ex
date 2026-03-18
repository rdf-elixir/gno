defmodule Gno.Store.InvalidEndpointError do
  @moduledoc """
  Raised on invalid `Gno.Store` endpoints.
  """
  defexception [:message]

  def exception(value) do
    %__MODULE__{message: "Invalid store endpoint: #{value}"}
  end
end

defmodule Gno.Store.SPARQL.InvalidOperationError do
  @moduledoc """
  Raised when creating an invalid `Gno.Store.SPARQL.Operation`.
  """

  defexception [:operation]

  def message(%{operation: operation}) do
    "Invalid SPARQL operation: #{inspect(operation)}"
  end
end

defmodule Gno.InvalidChangesetError do
  @moduledoc """
  Raised on invalid `Gno.Changeset` args.
  """
  defexception [:changes, :reason]

  def message(%{reason: :empty}) do
    "Invalid changeset: no changes provided"
  end

  def message(%{reason: reason}) do
    "Invalid changeset: #{reason}"
  end
end

defmodule Gno.NoEffectiveChanges do
  @moduledoc """
  Raised when some changes wouldn't have any effects against the current repository.
  """
  defexception []

  def message(%__MODULE__{}) do
    "No effective changes."
  end
end

defmodule Gno.Commit.ProcessorError do
  @moduledoc """
  Raised on errors in `Gno.Commit.Processor`.
  """
  defexception [:processor]

  def message(%{processor: processor}) do
    "Commit processing error (#{processor.state}): #{processor.errors |> Enum.reverse() |> Enum.map_join("\n", &inspect/1)}"
  end
end

defmodule Gno.Commit.ProcessorRollbackError do
  @moduledoc """
  Raised on errors during rollback in `Gno.Commit.Processor`.
  """
  defexception [:processor, :error]

  def message(%{processor: processor, error: error}) do
    "Commit processing rollback error (#{processor.state}): #{inspect(error)}"
  end
end

defmodule Gno.Service.SetupError do
  @moduledoc """
  Error raised during setup operations.
  """

  defexception [:reason, :service]

  @type t :: %__MODULE__{
          reason: term(),
          service: Gno.Service.t() | nil
        }

  def message(%{reason: :already_setup, service: service}) do
    "Repository #{service.repository.__id__} is already set up"
  end

  def message(%{reason: reason}) do
    "Setup failed: #{inspect(reason)}"
  end
end

defmodule Gno.Store.UnsupportedOperationError do
  @moduledoc """
  Raised when a SPARQL operation is not supported by a store adapter.
  """

  defexception [:operation, :store]

  @type t :: %__MODULE__{
          operation: atom(),
          store: Gno.Store.Adapter.t()
        }

  def message(%{operation: operation, store: store}) do
    "Operation #{inspect(operation)} is not supported by #{Gno.Store.Adapter.type_name(store.__struct__)}"
  end
end

defmodule Gno.Store.UnavailableError do
  @moduledoc """
  Raised when a store is unavailable for operations.
  """

  defexception [:reason, :store, :endpoint, :error]

  @type t :: %__MODULE__{
          reason: any,
          store: Gno.Store.t(),
          endpoint: String.t() | nil,
          error: term() | nil
        }

  def message(%{reason: :server_unreachable, endpoint: endpoint}) do
    "Store server unreachable: #{endpoint}"
  end

  def message(%{reason: :dataset_not_found, store: store, endpoint: endpoint}) do
    "Dataset not found on store: #{store.dataset} at #{endpoint}"
  end

  def message(%{reason: :query_failed, endpoint: endpoint, error: error}) do
    "Query failed on store #{endpoint}: #{inspect(error)}"
  end

  def message(%{reason: :admin_query_failed, endpoint: endpoint, error: error}) do
    "Admin query failed on store #{endpoint}: #{inspect(error)}"
  end

  def message(%{reason: reason, endpoint: endpoint, error: nil}) do
    "Store unavailable (#{reason}): #{endpoint}"
  end

  def message(%{reason: reason, endpoint: endpoint, error: error}) do
    "Store unavailable (#{reason}): #{endpoint}: #{inspect(error)}"
  end
end
