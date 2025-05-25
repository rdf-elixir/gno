defmodule Gno.Manifest.GeneratorError do
  @moduledoc """
  Raised on errors when generating `Gno.Manifest` files.
  """
  defexception [:message]
end

defmodule Gno.Manifest.LoadingError do
  @moduledoc """
  Raised on errors when loading a `Gno.Manifest` graph.
  """
  defexception [:file, :reason]

  def message(%{file: nil, reason: :missing}) do
    "No manifest files found"
  end

  def message(%{file: nil, reason: reason}) do
    "Invalid manifest: #{inspect(reason)}"
  end

  def message(%{file: file, reason: reason}) do
    "Invalid manifest file #{file}: #{inspect(reason)}"
  end
end

defmodule Gno.ManifestError do
  @moduledoc """
  Raised on errors with `Gno.Manifest`.
  """
  defexception [:manifest, :reason]

  def message(%{manifest: manifest, reason: :no_service}) do
    "Manifest does not contain a unique service: #{inspect(manifest)}"
  end

  def message(%{manifest: conflicting_services, reason: :multiple_services}) do
    "Manifest contains multiple services: #{inspect(Enum.map_join(conflicting_services, ", ", & &1.service))}"
  end

  def message(%{manifest: manifest, reason: :no_user}) do
    "Manifest does not contain a user: #{inspect(manifest)}"
  end

  def message(%{manifest: manifest, reason: :multiple_users}) do
    "Manifest contains multiple users: #{inspect(manifest)}"
  end

  def message(%{manifest: manifest, reason: reason}) do
    "Invalid manifest #{inspect(manifest)}: #{inspect(reason)}"
  end
end

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
