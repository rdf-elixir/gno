defmodule Gno.Manifest.Generator do
  @moduledoc """
  Generator for the manifest files of a Gno repository.
  """

  alias DCATR.Manifest.GeneratorError
  alias Gno.Store

  @doc """
  Returns the default template directory for manifest generation.

  ## Configuration

  The default template directory can be configured with the `:manifest_template_dir` option
  of the `:gno` application configuration:

      config :gno, manifest_template_dir: "custom/path"

  """
  def default_template_dir do
    Application.get_env(
      :gno,
      :manifest_template_dir,
      :gno |> :code.priv_dir() |> Path.join("manifest_template")
    )
  end

  @doc """
  Generates the manifest files for a Gno repository.

  The `project_dir` is the root directory of the project where additional directories
  may be created by custom manifest types. The manifest files themselves will be
  generated in a subdirectory determined by the last path in the load path.

  ## Options

  - `:adapter` - Initial store adapter (optional, default: `Gno.Store` for the generic store)
  - `:template` - Custom template directory
  - `:force` - Flag to overwrite existing destination directory (default: `false`)
  - `:assigns` - Additional assigns for EEx templates
  """
  @spec generate(Gno.Manifest.Type.t(), Path.t(), keyword()) :: :ok | {:error, any()}
  def generate(manifest_type, project_dir, opts \\ []) do
    with {:ok, adapter} <- Keyword.get(opts, :adapter) |> to_adapter() do
      opts = Keyword.put(opts, :assigns, [{:adapter, adapter} | Keyword.get(opts, :assigns, [])])
      DCATR.Manifest.Generator.generate(manifest_type, project_dir, opts)
    end
  end

  defp to_adapter(nil), do: {:ok, nil}
  defp to_adapter("generic"), do: {:ok, nil}
  defp to_adapter("Generic"), do: {:ok, nil}
  defp to_adapter("Store"), do: {:ok, nil}

  defp to_adapter(adapter_name) when is_binary(adapter_name) do
    if adapter = Store.Adapter.type(adapter_name) do
      {:ok, adapter}
    else
      {:error,
       GeneratorError.exception(
         "Invalid store adapter: #{inspect(adapter_name)}; available adapters: #{adapter_types()}"
       )}
    end
  end

  defp to_adapter(adapter) when is_atom(adapter) do
    if Store.Adapter.type?(adapter) do
      {:ok, adapter}
    else
      {:error,
       GeneratorError.exception(
         "Invalid store adapter: #{inspect(adapter)}; available adapters: #{adapter_types()}"
       )}
    end
  end

  def adapter_types do
    Enum.map_join(Store.adapters(), ", ", &Store.Adapter.type_name/1) <>
      " or Generic for the generic store adapter"
  end
end
