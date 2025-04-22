defmodule Gno.Manifest.LoadPath do
  @moduledoc """
  Manages the paths from which the `Gno.Manifest` graph is loaded.
  """

  @type t :: [String.t()]

  @default_load_path ["config/gno"]

  @extensions RDF.Serialization.formats() |> Enum.map(& &1.extension())
  @file_pattern "**/*.{#{Enum.join(@extensions, ",")}}"
  @env_file_pattern Map.new(
                      Gno.Manifest.environments(),
                      &{&1, "#{&1}/**/*.{#{Enum.join(@extensions, ",")}}"}
                    )
  @env_suffix_pattern Map.new(
                        Gno.Manifest.environments(),
                        &{&1, "**/*.#{&1}.{#{Enum.join(@extensions, ",")}}"}
                      )

  @doc """
  Returns the configured load path.

  By default, the load path is `#{@default_load_path}`, but can be configured with
  the `:load_path` option of the `:gno` application:

      config :gno, load_path: ["custom/path"]

  """
  @spec load_path(keyword()) :: t()
  def load_path(opts \\ []) do
    opts
    |> Keyword.get(:load_path, Application.get_env(:gno, :load_path, @default_load_path))
    |> List.wrap()
  end

  @doc """
  Resolves the load path into a list of concrete files, taking environment into account.

  ## Options

  Beyond the options for `load_path/1` the following options are supported:

  - `:env` - The environment to use for resolving the load path
  - `:load_path` - The load path to resolve, overriding the configured load path (see `load_path/1`)
  """
  @spec files(keyword()) :: t()
  def files(opts \\ []) do
    env = Gno.Manifest.env(opts)

    opts
    |> load_path()
    |> Enum.flat_map(fn path ->
      cond do
        not File.exists?(path) -> []
        File.dir?(path) -> find_files_in_directory(path, env)
        true -> [path]
      end
    end)
  end

  defp find_files_in_directory(dir, env) do
    {this_environment_specific_files, other_environment_specific_files} =
      Gno.Manifest.environments()
      |> Enum.map(fn environment ->
        {environment,
         (dir |> Path.join(@env_suffix_pattern[environment]) |> Path.wildcard()) ++
           (dir |> Path.join(@env_file_pattern[environment]) |> Path.wildcard())}
      end)
      |> Keyword.pop(env)

    dir
    |> Path.join(@file_pattern)
    |> Path.wildcard()
    |> Kernel.--(other_environment_specific_files |> Keyword.values() |> List.flatten())
    # We're removing and adding the environment-specific files to ensure that they are loaded last
    # having precedence over the general files
    |> Kernel.--(this_environment_specific_files)
    |> Kernel.++(this_environment_specific_files)
    |> Enum.reject(&ignored_file?/1)
    |> Enum.uniq()
  end

  defp ignored_file?(path) do
    Path.basename(path) |> String.starts_with?("_")
  end
end
