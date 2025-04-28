defmodule Gno.Manifest.Generator do
  @moduledoc """
  Generator for the manifest files of a Gno repository.
  """

  alias Gno.Manifest.{LoadPath, GeneratorError}
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
  Returns the manifest directory path within the project directory.

  The manifest directory is determined from the configured load path.
  The last path in the load path with the highest precedence is used,
  since it is the most specific path.

  Returns an error if the last path in the load path is absolute, since
  manifest directories must be relative to the project directory.
  """
  def manifest_dir(opts \\ []) do
    manifest_dir = LoadPath.load_path(opts) |> List.last()

    if Path.type(manifest_dir) == :absolute do
      {:error,
       GeneratorError.exception("""
       Cannot use absolute path as manifest directory: #{manifest_dir}

       The manifest directory must be relative to the project directory to ensure proper
       organization of project files. Please use a relative path instead.
       """)}
    else
      {:ok, manifest_dir}
    end
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
    with {:ok, manifest_dir} <- manifest_dir(opts),
         {:ok, adapter} <- Keyword.get(opts, :adapter) |> to_adapter(),
         destination = Path.join(project_dir, manifest_dir),
         :ok <- create_manifest_dir(destination, Keyword.get(opts, :force, false)),
         {:ok, template_dir} <-
           Keyword.get(opts, :template, manifest_type.generator_template())
           |> check_template() do
      template_dir
      |> File.ls!()
      |> Enum.each(fn file ->
        base_file = Path.basename(file, ".eex")
        eex? = file != base_file

        copy_file!(
          Path.join(template_dir, file),
          Path.join(destination, base_file),
          eex? &&
            opts
            |> Keyword.get(:assigns, [])
            |> Keyword.merge(adapter: adapter)
        )
      end)

      :ok
    end
  end

  defp create_manifest_dir(dir, force?) do
    cond do
      not File.exists?(dir) -> File.mkdir_p(dir)
      force? -> :ok
      true -> {:error, GeneratorError.exception("Manifest directory already exists: #{dir}")}
    end
  end

  defp check_template(template) do
    if File.exists?(template) do
      {:ok, template}
    else
      {:error, GeneratorError.exception("Template does not exist: #{template}")}
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

  defp copy_file!(source, dest, false), do: File.copy!(source, dest)

  defp copy_file!(source, dest, assigns) do
    File.write!(dest, EEx.eval_file(source, assigns: assigns))
  end
end
